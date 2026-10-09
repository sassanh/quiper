import AppKit
import Carbon
import CoreServices
import Foundation
import LocalAuthentication
import ServiceManagement
import SwiftUI
import UserNotifications
import WebKit

extension Notification.Name {
    static let inspectorVisibilityChanged = Notification.Name("InspectorVisibilityChanged")
    static let showSettings = Notification.Name("QuiperShowSettings")
    static let startGlobalHotkeyCapture = Notification.Name("QuiperStartGlobalHotkeyCapture")
    static let appVisibilityChanged = Notification.Name("QuiperAppVisibilityChanged")
    static let hotkeyConfigurationChanged = Notification.Name("QuiperHotkeyConfigurationChanged")
    static let notificationPermissionChanged = Notification.Name("QuiperNotificationPermissionChanged")
    static let dockVisibilityChanged = Notification.Name("QuiperDockVisibilityChanged")
    static let selectorDisplayModeChanged = Notification.Name("QuiperSelectorDisplayModeChanged")
    static let topBarVisibilityChanged = Notification.Name("QuiperTopBarVisibilityChanged")
    static let dragAreaPositionChanged = Notification.Name("QuiperDragAreaPositionChanged")
    static let windowAppearanceChanged = Notification.Name("QuiperWindowAppearanceChanged")
    static let colorSchemeChanged = Notification.Name("QuiperColorSchemeChanged")
    static let showOnAllSpacesChanged = Notification.Name("QuiperShowOnAllSpacesChanged")
    static let keepOverlayOnTopChanged = Notification.Name("QuiperKeepOverlayOnTopChanged")
    static let focusLossEffectChanged = Notification.Name("QuiperFocusLossEffectChanged")
    static let windowDidShow = Notification.Name("QuiperWindowDidShow")
    static let windowDidHide = Notification.Name("QuiperWindowDidHide")
    static let settingsWindowDidOpen = Notification.Name("QuiperSettingsWindowDidOpen")
    static let settingsWindowDidClose = Notification.Name("QuiperSettingsWindowDidClose")
    static let servicesIconsUpdated = Notification.Name("QuiperServicesIconsUpdated")
    static let servicesOrderUpdated = Notification.Name("QuiperServicesOrderUpdated")
}

@objc protocol StandardEditActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

@MainActor
final class AppController: NSObject, NSWindowDelegate {

    private let windowController: MainWindowControlling
    var window: MainWindowControlling { return windowController }
    let hotkeyManager: HotkeyManaging
    let engineHotkeyManager: EngineHotkeyManaging
        private let notificationDispatcher: NotificationDispatching
        private var lastNonQuiperApplication: NSRunningApplication?
        private var lastActiveTime: Date?
        /// Set when a notification click summons the overlay. macOS delivers a
        /// reopen event as part of the same activation; it must show, not
        /// toggle-hide, the overlay it just summoned. Consumed by the reopen
        /// handler, cleared whenever the overlay hides or the app deactivates.
        private var pendingNotificationActivation = false
        private let testDataStore: WKWebsiteDataStore
        private var screenshotPromptController: ScreenshotPromptController?
        #if DEBUG
        private var templateValidationServer: TemplateValidationServer?
        #endif

        init(windowController: MainWindowControlling? = nil,

         hotkeyManager: HotkeyManaging? = nil,
         engineHotkeyManager: EngineHotkeyManaging? = nil,
         notificationDispatcher: NotificationDispatching? = nil) {

        // Instantiate defaults inside the body (which is safely on MainActor)
        self.windowController = windowController ?? MainWindowController()
        self.hotkeyManager = hotkeyManager ?? HotkeyManager()
        self.engineHotkeyManager = engineHotkeyManager ?? EngineHotkeyManager()
        self.notificationDispatcher = notificationDispatcher ?? NotificationDispatcher.shared
        self.testDataStore = WKWebsiteDataStore.nonPersistent()

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(handleShowSettingsNotification), name: .showSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidResignActive(_:)), name: NSApplication.didResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(handleApplicationDidActivate(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(handleActiveSpaceDidChange(_:)),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDockVisibilityChanged), name: .dockVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowDidShow), name: .windowDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowDidHide), name: .windowDidHide, object: nil)
    }



    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }



    func start() {
        if ProcessInfo.processInfo.arguments.contains("--interactive-mode") {
            screenshotPromptController = ScreenshotPromptController()
            showScreenshotPrompt()
        }

        #if DEBUG
        if TemplateValidationServer.shouldStart() {
            startTemplateValidationServer()
        }
        #endif

        if Settings.shared.dockVisibility == .always {
            NSApp.setActivationPolicy(.regular)
        }

        registerOverlayHotkey()
        registerEngineHotkeys()
        UpdateManager.shared.handleLaunchIfNeeded()
        presentTemplateActionSyncMigrationPromptIfNeeded()
        presentEngineShortcutToggleMigrationPromptIfNeeded()
        presentEngineMetadataMigrationPromptIfNeeded()
    }

    private func presentEngineMetadataMigrationPromptIfNeeded() {
        guard !Self.isRunningTests,
              !Constants.LaunchMode.shouldSuppressInterferenceUI else {
            return
        }
        guard EngineMetadataMigrationManager.shared.hasAnyLegacyMetadata(in: Settings.shared.services) else {
            return
        }
        Task { @MainActor in
            await EngineMetadataMigrationManager.shared.presentMigrationWizardIfNeeded(
                relativeTo: windowController.window
            )
        }
    }

    private func presentTemplateActionSyncMigrationPromptIfNeeded() {
        guard Settings.shared.needsTemplateActionSyncMigrationPrompt,
              !Self.isRunningTests,
              !Constants.LaunchMode.shouldSuppressInterferenceUI else {
            return
        }

        DispatchQueue.main.async {
            guard Settings.shared.needsTemplateActionSyncMigrationPrompt else { return }

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Update Default Action Scripts?"
            alert.informativeText = "Quiper can reconnect actions that match built-in templates to the latest bundled scripts. Choose Update to keep those template scripts in sync automatically. Choose Keep Custom to leave existing scripts editable and unchanged."
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Keep Custom")
            alert.buttons[1].keyEquivalent = "\u{1b}"

            let shouldUpdate = alert.runModal() == .alertFirstButtonReturn
            Settings.shared.resolveTemplateActionSyncMigration(updateScripts: shouldUpdate)
            self.reloadServices()
        }
    }

    private func presentEngineShortcutToggleMigrationPromptIfNeeded() {
        guard Settings.shared.needsEngineShortcutToggleMigrationPrompt,
              !Self.isRunningTests,
              !Constants.LaunchMode.shouldSuppressInterferenceUI else {
            return
        }

        DispatchQueue.main.async {
            guard Settings.shared.needsEngineShortcutToggleMigrationPrompt else { return }

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Use engine shortcuts to show and hide?"
            alert.informativeText = "Right now, pressing an engine's global shortcut while Quiper is already open on that engine does nothing. Enable this to hide Quiper instead—same idea as the main Show/Hide shortcut. You can change this later in Shortcuts settings."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Keep Current")
            alert.buttons[1].keyEquivalent = "\u{1b}"

            let shouldEnable = alert.runModal() == .alertFirstButtonReturn
            Settings.shared.resolveEngineShortcutToggleMigration(enable: shouldEnable)
        }
    }

    #if DEBUG
    private func startTemplateValidationServer() {
        guard let concreteWindowController = windowController as? MainWindowController else {
            NSLog("[Quiper] Template validation server could not start: unsupported window controller")
            return
        }

        let server = TemplateValidationServer(windowController: concreteWindowController)
        do {
            try server.start()
            templateValidationServer = server
        } catch {
            NSLog("[Quiper] Template validation server could not start: %@", error.localizedDescription)
        }
    }
    #endif

    private func showScreenshotPrompt() {
        let alert = NSAlert()
        alert.messageText = "Screenshot Generator (Interactive)"
        alert.informativeText = "The app is ready. Click 'Go' to start.\n\nFor each screenshot, a small floating window will appear. You can interact with the app, and click 'Take Screenshot' when you're ready."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }



    @objc func showWindow(_ sender: Any?) {
        captureFrontmostNonQuiperApplication()
        ensureActivationPolicyForShowingOverlay()
        windowController.show()
    }

    /// Single gate for the activation-policy flip when showing the overlay.
    /// Runs BEFORE the window orders front and the app activates: flipping
    /// accessory -> regular after activation resigns the app and leaves the
    /// focus-loss dim (and its click-eating shield) stuck on the focused
    /// window until the next click. handleWindowDidShow re-asserts the same
    /// value after the show, which is a no-op once set here.
    private func ensureActivationPolicyForShowingOverlay() {
        let visibility = Settings.shared.dockVisibility
        if !windowController.isWebContentFullscreen, visibility == .always || visibility == .whenVisible {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc func hideWindow(_ sender: Any?) {
        pendingNotificationActivation = false
        windowController.hide()
    }

    /// True when a notification click summoned the overlay and its reopen event
    /// has not been handled yet. Consumes the latch.
    func consumeNotificationActivation() -> Bool {
        guard pendingNotificationActivation else { return false }
        pendingNotificationActivation = false
        return true
    }

    /// Handles a URL another application handed Quiper: a link the resident
    /// link helper routed in through a `quiper://` route, or a direct
    /// handoff (`open -a Quiper <url>`). An enabled engine whose domains
    /// claim the link opens it there — a locked secure engine claims
    /// nothing, since its routing records live inside its encrypted
    /// bundle. Anything else keeps the system default behavior.
    func handleExternalURL(_ url: URL) {
        guard let link = resolvedExternalLink(from: url) else { return }
        guard let claimed = ExternalLinkRouting.claimedService(
            for: link,
            in: Settings.shared.services,
            isEngineUnlocked: { EncryptedVolumeManager.shared.isUnlocked(for: $0) }
        ) else {
            forwardUnclaimedExternalURL(link)
            return
        }
        // The reopen event macOS may deliver with this activation must show
        // the overlay, not toggle it straight back off.
        pendingNotificationActivation = true
        showWindow(nil)
        guard let mainWindowController = windowController as? MainWindowController else {
            NSLog("[Quiper] External link could not open: main window controller unavailable")
            return
        }
        mainWindowController.openExternalLink(link, for: claimed)
    }

    /// The web link a delivered URL carries: the payload of a `quiper://`
    /// route from the link helper, or the URL itself when handed over
    /// directly. Nil for anything that is not a web link.
    private func resolvedExternalLink(from url: URL) -> URL? {
        let link: URL
        if url.scheme?.lowercased() == QuiperLinkRoute.scheme {
            guard let routed = QuiperLinkRoute.link(in: url) else {
                NSLog("[Quiper] Ignoring malformed link route: %@", url.absoluteString)
                return nil
            }
            link = routed
        } else {
            link = url
        }
        guard link.scheme == "http" || link.scheme == "https" else {
            NSLog("[Quiper] Ignoring external URL with unsupported scheme: %@", link.absoluteString)
            return nil
        }
        return link
    }

    /// Keeps an unclaimed link behaving as it would without Quiper: it opens
    /// in the system default browser — unless that browser is Quiper itself,
    /// where forwarding would hand the link straight back, so it opens in
    /// the user's chosen fallback browser instead.
    private func forwardUnclaimedExternalURL(_ url: URL) {
        if Self.isQuiperDefaultOpener(for: url) {
            openInFallbackBrowser(url)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens the link in the fallback browser: the one recorded when Quiper
    /// became the default browser, or Safari when none is recorded or the
    /// recorded app is gone. The explicit application target keeps the open
    /// from routing back through the default — Quiper — in a loop.
    private func openInFallbackBrowser(_ url: URL) {
        let fallbackBundleIdentifier = DefaultBrowserRouting.fallbackBundleIdentifier(
            recorded: Settings.shared.defaultBrowserFallbackBundleIdentifier,
            quiperBundleIdentifier: Constants.BUNDLE_ID
        ) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallbackBundleIdentifier) else {
            NSLog("[Quiper] Unclaimed link could not open: no application for %@", fallbackBundleIdentifier)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("[Quiper] Unclaimed link could not open in %@: %@", fallbackBundleIdentifier, error.localizedDescription)
            }
        }
    }

    /// Whether Launch Services would open `url` in Quiper itself —
    /// forwarding such a link would bounce it straight back in a loop.
    private static func isQuiperDefaultOpener(for url: URL) -> Bool {
        DefaultBrowserRouting.isQuiperDefaultOpener(
            applicationURL: NSWorkspace.shared.urlForApplication(toOpen: url),
            quiperBundleIdentifier: Constants.BUNDLE_ID
        )
    }

    @objc private func handleWindowDidShow(_ notification: Notification) {
        ensureActivationPolicyForShowingOverlay()
        // Settings and the update prompt outrank the overlay: whichever is
        // visible takes key status back through the gate's single policy.
        KeyFocusGate.shared.applyPrecedence()
        NotificationCenter.default.post(name: .appVisibilityChanged, object: true)
    }

    @objc func handleWindowDidHide(_ notification: Notification) {
        activateLastKnownApplication()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            // The overlay can be re-shown within the delay (a quick
            // hide/show double-press). The show path already asserted the
            // visible state, so drop out instead of dropping the app back
            // to accessory and posting a stale hidden state.
            if self.windowController.window?.isVisible == true {
                return
            }
            // Read at execution time: the setting may change during the delay.
            let visibility = Settings.shared.dockVisibility
            if !self.windowController.isWebContentFullscreen {
                if visibility == .always {
                    NSApp.setActivationPolicy(.regular)
                } else if visibility == .whenVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            NotificationCenter.default.post(name: .appVisibilityChanged, object: false)
        }
    }

    @objc func closeSettingsOrHide(_ sender: Any?) {
        if AppDelegate.sharedSettingsWindow.isVisible == true && AppDelegate.sharedSettingsWindow.isKeyWindow {
            dismissSettingsWindow()
        } else {
            hideWindow(sender)
        }
    }





    @objc func showSettings(_ sender: Any?) {
        presentSettingsWindow()
    }

    @objc func openDocumentation(_ sender: Any?) {
        guard let url = URL(string: "https://quiper.sassanh.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func toggleInspector(_ sender: Any?) {
        windowController.toggleInspector()
    }



    @objc func clearWebViewData(_ sender: Any?) {
        let store = AppController.isRunningTests ? testDataStore : WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                         modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async {
                self?.windowController.focusInputInActiveWebview()
            }
        }
    }
    @objc func handleDockVisibilityChanged(_ notification: Notification) {

        let visibility = Settings.shared.dockVisibility

        switch visibility {
        case .always:
            NSApp.setActivationPolicy(.regular)
        case .never:
            NSApp.setActivationPolicy(.accessory)
        case .whenVisible:
            // An element-fullscreen session deliberately hides the overlay
            // while Quiper's own video fills a fullscreen Space, so the app
            // still counts as visible for the Dock icon.
            if windowController.window?.isVisible == true || windowController.isWebContentFullscreen {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // Force activation to prevent focus loss during policy switch
        NSApp.activate(ignoringOtherApps: true)

        // Removed: AppDelegate.sharedSettingsWindow.makeKeyAndOrderFront(nil)
        // This was causing the settings window to pop up unexpectedly (e.g. during drag reorder)
    }

    @objc func setHotkey(_ sender: Any?) {
        presentSettingsWindow()
        NotificationCenter.default.post(name: .startGlobalHotkeyCapture, object: nil)
    }

    @objc func openNotificationSettings(_ sender: Any?) {
        presentSettingsWindow()
        notificationDispatcher.openSystemNotificationSettings()
    }



    @objc func checkForUpdates(_ sender: Any?) {

        UpdateManager.shared.checkForUpdates(userInitiated: true)

    }



    @objc func installAtLogin(_ sender: Any?) {

        Launcher.installAtLogin()

    }



    @objc func uninstallFromLogin(_ sender: Any?) {

        Launcher.uninstallFromLogin()

    }



    func reloadServices() {

        windowController.reloadServices()
        registerEngineHotkeys()

    }

    /// Probe-only `beforeunload` query for Settings destructive actions.
    /// The caller folds the warning into its own confirmation dialog.
    func unloadInfosNeedingConfirmation(for serviceIDs: [UUID]) async -> [TabUnloadInfo] {
        await windowController.unloadInfosNeedingConfirmation(for: serviceIDs)
    }

    func updateOverlayHotkey(_ configuration: HotkeyManager.Configuration) {
        hotkeyManager.updateConfiguration(configuration)
        NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)
    }



    func focusMainWindowIfVisible() {

        guard windowController.window?.isVisible == true else { return }
        guard !windowController.isActiveSpaceWebFullscreen else {
            windowController.showWebFullScreenBanner()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // The same precedence the show restore and the key delegate
            // share: Settings, the update prompt, else the overlay.
            guard !KeyFocusGate.shared.applyPrecedence() else { return }
            let overlay = self.windowController.window
            KeyFocusGate.shared.focus(overlay)
            if let sheet = overlay?.attachedSheet {
                KeyFocusGate.shared.focus(sheet)
            } else if !GhostOnboardingManager.shared.isActive {
                self.windowController.focusInputInActiveWebviewWithFallback()
            }
        }

    }



    func setMainWindowShortcutsEnabled(_ enabled: Bool) {
        windowController.setShortcutsEnabled(enabled)
        guard windowController.window?.isVisible == true else {
            return
        }
    }

    var currentServiceID: UUID? { windowController.activeServiceID }

    var isWindowVisible: Bool {
        guard let window = windowController.window else { return false }
        return window.isVisible && window.isOnActiveSpace
    }

    private func captureFrontmostNonQuiperApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }
        lastNonQuiperApplication = frontmost
    }

    private func activateLastKnownApplication() {
        guard let app = lastNonQuiperApplication, !app.isTerminated else { return }

        if hasWindowOnActiveSpace(pid: app.processIdentifier) {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func hasWindowOnActiveSpace(pid: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t {
                if windowPID == pid {
                    return true
                }
            }
        }
        return false
    }

    @objc private func handleApplicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }
        lastNonQuiperApplication = app
    }

    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        lastActiveTime = nil
    }

    @objc private func handleApplicationDidResignActive(_ notification: Notification) {
        lastActiveTime = Date()
        pendingNotificationActivation = false
        hideOverlayForFocusLossIfNeeded()
    }

    /// Hides the overlay when it loses focus, if the user enabled
    /// "Hide on focus loss". Only hides when Quiper is alone: any other
    /// Quiper window (Settings, update prompt, attached sheet, modal) or an
    /// in-progress fullscreen/onboarding session inhibits the hide so nothing
    /// is dismissed out from under the user.
    private func hideOverlayForFocusLossIfNeeded() {
        guard Settings.shared.hideOnFocusLoss else { return }
        guard !Self.isRunningTests, !Constants.LaunchMode.shouldSuppressInterferenceUI else { return }
        guard isWindowVisible else { return }
        guard !windowController.isWebContentFullscreen else { return }
        guard windowController.window?.attachedSheet == nil else { return }
        guard NSApp.modalWindow == nil else { return }
        guard !AppDelegate.sharedSettingsWindow.isVisible else { return }
        guard UpdatePromptWindowController.shared.window?.isVisible != true else { return }
        guard !GhostOnboardingManager.shared.isActive else { return }
        hideWindow(nil)
    }

    @objc private func handleActiveSpaceDidChange(_ notification: Notification) {
        // While web content is fullscreen (in its own space) Quiper must not run
        // any app-global mutation on a space change: no activation-policy flips
        // (a background app can't keep a dedicated fullscreen space) and no
        // auto-focus of the overlay into the moving space. On any other app/
        // space, only an explicit show shortcut may bring Quiper forward.
        guard !windowController.isWebContentFullscreen else { return }

        guard Settings.shared.showOnAllSpaces else { return }

        let wasActive = NSApp.isActive || (lastActiveTime.map { Date().timeIntervalSince($0) < 1.5 } ?? false)
        if wasActive {
            NSApp.activate(ignoringOtherApps: true)
            focusMainWindowIfVisible()
        }
    }



    private var mainWindowShield: InteractionShieldView?

    private func presentSettingsWindow() {
        let settingsWindow = AppDelegate.sharedSettingsWindow
        settingsWindow.appController = self
        guard let mainWindow = windowController.window else {
            if settingsWindow.isVisible == true {
                KeyFocusGate.shared.orderOut(settingsWindow)
            } else {
                let visibility = Settings.shared.dockVisibility
                if visibility == .always || visibility == .whenVisible {
                    NSApp.setActivationPolicy(.regular)
                }
                KeyFocusGate.shared.focus(settingsWindow)
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .settingsWindowDidOpen, object: nil)
            }
            return
        }

        if settingsWindow.isVisible == true {
            dismissSettingsWindow()
        } else {
            beginModalSettingsWindow(settingsWindow, over: mainWindow)
        }
    }

    private func beginModalSettingsWindow(_ settingsWindow: NSWindow, over parent: NSWindow) {
        setMainWindowShortcutsEnabled(false)
        installShieldIfNeeded(on: parent)
        parent.addChildWindow(settingsWindow, ordered: .above)
        let visibility = Settings.shared.dockVisibility
        if visibility == .always || visibility == .whenVisible {
            NSApp.setActivationPolicy(.regular)
        }
        KeyFocusGate.shared.focus(settingsWindow)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .settingsWindowDidOpen, object: nil)
    }

    private func dismissSettingsWindow() {
        // Settings cannot leave while a secure-data migration runs — the
        // window's own close and order-out veto it. Bailing before any
        // cleanup keeps the dismissal atomic: otherwise the child-window
        // detach and shield removal run, then the gate hands focus off
        // for a departure that never happens, leaving Settings visible
        // without key status and the overlay dim behind its shield.
        if SecureDataMigrationManager.shared.isMigrationPending {
            NSSound.beep()
            return
        }
        let settingsWindow = AppDelegate.sharedSettingsWindow
        if let parent = settingsWindow.parent {
            parent.removeChildWindow(settingsWindow)
        }
        // Cleanup first, then the gate: the hand-back may key the overlay,
        // and its own key handling must be the one to land input focus —
        // the shield's responder reset may not run after it.
        removeShieldIfNeeded(from: windowController.window)
        setMainWindowShortcutsEnabled(true)
        // The gate's order-out decides the successor — the content window
        // the user was on before Settings interrupted it — and orders the
        // window out itself; no focus request of ours may follow, or it
        // would undo the hand-back.
        KeyFocusGate.shared.orderOut(settingsWindow)
        if windowController.window?.isVisible == true,
           windowController.isActiveSpaceWebFullscreen {
            windowController.showWebFullScreenBanner()
        }

        let visibility = Settings.shared.dockVisibility
        if isWindowVisible == false && visibility == .whenVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.post(name: .settingsWindowDidClose, object: nil)
    }

    private func registerOverlayHotkey() {
        hotkeyManager.registerCurrentHotkey { [weak self] in
            guard let self else { return }
            if self.windowController.isActiveSpaceWebFullscreen {
                self.activateLastKnownApplicationForFullscreenExit()
                return
            }
            let shouldHide = self.isWindowVisible && (
                Settings.shared.keepOverlayOnTop
                    || (NSApp.isActive && self.windowController.isAnyQuiperWindowKey)
            )
            if shouldHide {
                self.hideWindow(nil)
            } else {
                self.showWindow(nil)
            }
        }
    }

    private func activateLastKnownApplicationForFullscreenExit() {
        guard let app = lastNonQuiperApplication, !app.isTerminated else {
            NSLog("[FullSpace] hotkey in fullscreen: no last app to return to, showing banner")
            windowController.showWebFullScreenBanner()
            return
        }
        NSLog(
            "[FullSpace] hotkey in fullscreen: activating last app %@ (pid %d)",
            app.localizedName ?? app.bundleIdentifier ?? "unknown",
            app.processIdentifier
        )
        // Force activation even if its window is not on the current
        // (fullscreen) Space – this is how we leave the fullscreen Space
        // without exiting fullscreen and without private Space SPI.
        app.activate(options: [.activateAllWindows])
    }

    private func registerEngineHotkeys() {
        let overlayHotkey = Settings.shared.hotkeyConfiguration
        var blockedHotkeys: [HotkeyManager.Configuration] = [overlayHotkey]
        if (AppController.isRunningInXcode || Constants.LaunchMode.isTemplateValidationServer),
           HotkeyManager.defaultConfiguration == overlayHotkey {
            // Dev / template-validation fallback registers Ctrl+Space; keep engine hotkeys off it.
            blockedHotkeys.append(
                HotkeyManager.Configuration(
                    keyCode: UInt32(kVK_Space),
                    modifierFlags: NSEvent.ModifierFlags.control.rawValue
                )
            )
        }

        var entries: [EngineHotkeyManager.Entry] = Settings.shared.services.compactMap { service in
            guard let shortcut = service.activationShortcut,
                  isBlocked(shortcut, blockedHotkeys: blockedHotkeys) == false else { return nil }
            return EngineHotkeyManager.Entry(serviceID: service.id, configuration: shortcut)
        }

        if Settings.shared.globalEngineDigitShortcutsEnabled {
            let primaryModifiers = Settings.shared.appShortcutBindings.serviceDigitsPrimaryModifiers
            for (index, service) in Settings.shared.services.prefix(EngineDigitShortcut.maximumEngineCount).enumerated() {
                guard let shortcut = EngineDigitShortcut.configuration(
                    forEngineAt: index,
                    modifiers: primaryModifiers
                ), isBlocked(shortcut, blockedHotkeys: blockedHotkeys) == false else {
                    continue
                }
                entries.append(
                    EngineHotkeyManager.Entry(serviceID: service.id, configuration: shortcut)
                )
            }
        }
        guard !entries.isEmpty else {
            engineHotkeyManager.disable()
            return
        }
        engineHotkeyManager.register(entries: entries) { [weak self] serviceID in
            self?.activateService(for: serviceID)
        }
    }

    private func activateService(for serviceID: UUID) {
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == serviceID }) else {
            engineHotkeyManager.unregister(serviceID: serviceID)
            return
        }

        if windowController.isWebContentFullscreen {
            showWindow(nil)
            return
        }

        let alreadyActiveEngine =
            isWindowVisible
            && NSApp.isActive
            && windowController.activeServiceID == serviceID

        if Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut, alreadyActiveEngine {
            hideWindow(nil)
            return
        }

        showWindow(nil)
        windowController.selectService(at: index)
        windowController.focusInputInActiveWebview()
    }

    private func isBlocked(_ configuration: HotkeyManager.Configuration,
                           blockedHotkeys: [HotkeyManager.Configuration]) -> Bool {
        let normalizedModifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags)
            .intersection([.command, .option, .control, .shift]).rawValue
        return blockedHotkeys.contains {
            $0.keyCode == configuration.keyCode &&
            NSEvent.ModifierFlags(rawValue: $0.modifierFlags)
                .intersection([.command, .option, .control, .shift]).rawValue == normalizedModifiers
        }
    }

    static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isRunningInXcode: Bool {
        if (AppController.isRunningTests) {
            return false
        }
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil {
            return true
        }
        if let serviceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
           serviceName.contains("com.apple.dt.Xcode") {
            return true
        }
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/DerivedData/") {
            return true
        }
        return false
    }

    @objc private func handleShowSettingsNotification() {
        presentSettingsWindow()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == AppDelegate.sharedSettingsWindow {
            if SecureDataMigrationManager.shared.isMigrationPending {
                NSSound.beep()
                return false
            }
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == AppDelegate.sharedSettingsWindow {
            if let parent = windowController.window {
                parent.removeChildWindow(window)
            }
            removeShieldIfNeeded(from: windowController.window)
            setMainWindowShortcutsEnabled(true)
            // The gate decides the successor — the content window the user
            // was on before Settings interrupted it — so no focus request
            // of ours may follow and undo the hand-back. The fullscreen
            // banner is additional, in the same order as the toggle path:
            // both dismissals are the same action and take the same route.
            KeyFocusGate.shared.windowWillClose(window)
            if windowController.window?.isVisible == true,
               windowController.isActiveSpaceWebFullscreen {
                windowController.showWebFullScreenBanner()
            }
        }
    }

    private func installShieldIfNeeded(on window: NSWindow) {
        guard mainWindowShield == nil, let contentView = window.contentView else { return }
        let shield = InteractionShieldView(frame: contentView.bounds)
        shield.autoresizingMask = [.width, .height]
        contentView.addSubview(shield, positioned: .above, relativeTo: nil)
        mainWindowShield = shield
    }

    private func removeShieldIfNeeded(from window: NSWindow?) {
        guard let shield = mainWindowShield else { return }
        shield.removeFromSuperview()
        if let window {
            window.makeFirstResponder(window.contentView)
        }
        mainWindowShield = nil
    }

}

extension AppController: NotificationDispatcherDelegate {
    func notificationDispatcher(_ dispatcher: NotificationDispatcher,
                                didActivateNotificationForServiceID serviceID: UUID?,
                                sessionIndex: Int?) {
        pendingNotificationActivation = true
        showWindow(nil)
        if let serviceID {
            _ = windowController.selectService(withID: serviceID)
        }
        if let sessionIndex {
            windowController.switchSession(to: sessionIndex)
        }
        windowController.focusInputInActiveWebview()
    }
}

// MARK: - App Entry



@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!

    /// Links handed to Quiper before launch finished — a URL that starts the
    /// app arrives while `statusBarController` is still nil. Held here and
    /// routed once `completeLaunch` has built the app controller.
    private var pendingExternalURLs: [URL] = []

    static var sharedSettingsWindow = SettingsWindow.shared

    /// Set once termination passes the point where the keep/discard
    /// decision is made and every confirmation before it has resolved:
    /// from then on the saved tab state is final, and the teardown ahead
    /// must not feed a save a session that is coming apart.
    static var hasCommittedTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered before launch completes: a link that starts the app is
        // delivered as a launch-time kAEGetURL event, which goes unhandled
        // unless the handler exists by then.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Another application asked Quiper to open a URL — right-click → Open
    /// Link With, `open -a Quiper <url>`, or a launch-time link.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor?) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        pendingExternalURLs.append(url)
        flushExternalURLsIfReady()
    }

    /// Routes queued links once the app controller exists.
    private func flushExternalURLsIfReady() {
        guard !pendingExternalURLs.isEmpty,
              let appController = statusBarController?.appController else { return }
        let urls = pendingExternalURLs
        pendingExternalURLs.removeAll()
        for url in urls {
            appController.handleExternalURL(url)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Clean up any stale mounts from previous crashed sessions
        unmountAllEncryptedVolumes()

        NSApp.setActivationPolicy(.accessory)

        if OnboardingWizard.needsOnboarding {
            OnboardingWizard.show { [weak self] in
                self?.completeLaunch()
            }
        } else {
            completeLaunch()
        }
    }

    /// The nested helper bundle inside this app; nil when the app was
    /// assembled without it.
    private var linkHelperBundleURL: URL? {
        let url = LinkHelperRouting.helperBundleURL(hostBundleURL: Bundle.main.bundleURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The helper's bundle identifier: this build's identifier with the
    /// helper suffix, matching the helper target's product bundle identifier.
    private static var linkHelperBundleIdentifier: String {
        Constants.BUNDLE_ID + ".LinkHelper"
    }

    /// Keeps the link helper resident so an unclaimed link never pays its
    /// cold start: registers it as a login item for the next boot, launches
    /// it for this session, and inherits nothing the user chose — a default
    /// assignment that still names a build of Quiper moves over too.
    private func ensureLinkHelperResident() {
        guard !AppController.isRunningTests, !Constants.LaunchMode.isUITesting,
              let helperURL = linkHelperBundleURL else { return }
        registerLinkHelperLoginItem()
        repointLegacyDefaultBrowserToLinkHelper(helperURL: helperURL)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
            if let error {
                NSLog("[Quiper] Link helper could not start: %@", error.localizedDescription)
            }
        }
    }

    /// Registers the helper as a login item so it runs from the next login
    /// on, even when Quiper itself never opens.
    private func registerLinkHelperLoginItem() {
        let service = SMAppService.loginItem(identifier: Self.linkHelperBundleIdentifier)
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            NSLog("[Quiper] Link helper login item could not register: %@", error.localizedDescription)
        }
    }

    /// A default assignment that still names a build of Quiper — an app
    /// updated before the helper existed — moves to the helper, preserving
    /// the recorded fallback browser. Links resolve to Quiper either way;
    /// only the receiving build changes.
    private func repointLegacyDefaultBrowserToLinkHelper(helperURL: URL) {
        let probeURL = URL(string: "https://example.com")!
        guard let defaultApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL),
              let defaultBundleIdentifier = Bundle(url: defaultApplicationURL)?.bundleIdentifier,
              defaultBundleIdentifier != Self.linkHelperBundleIdentifier,
              DefaultBrowserRouting.isQuiperBundleIdentifier(
                  defaultBundleIdentifier,
                  quiperBundleIdentifier: Constants.BUNDLE_ID
              ) else {
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: helperURL, toOpenURLsWithScheme: "http") { error in
            if let error {
                NSLog("[Quiper] Default browser could not move to the link helper: %@", error.localizedDescription)
            } else {
                NSLog("[Quiper] Default browser moved from %@ to the link helper", defaultBundleIdentifier)
            }
        }
    }

    private func completeLaunch() {
        if presentCorruptedSettingsRecoveryIfNeeded() {
            return
        }

        statusBarController = StatusBarController()

        NotificationDispatcher.shared.configure(delegate: statusBarController.appController)

        createMainMenu()

        statusBarController.install()

        AppDelegate.sharedSettingsWindow.appController = statusBarController.appController

        // Asynchronously scan and clean up orphaned persistent WebKit cache directories
        WebKitCacheCleaner.cleanOrphanedStores()

        EncryptedVolumeManager.shared.applySpotlightExclusionToAllSecuredEngines()

        // Show the window if the user launched the app intentionally (double-click, Spotlight, etc.)
        // but stay hidden if launched automatically by a LaunchAgent at system boot (parent is launchd, pid 1)
        if !isAutoLaunch {
            statusBarController.appController.showWindow(nil)
        }

        flushExternalURLsIfReady()

        ensureLinkHelperResident()
    }

    @MainActor
    private func presentCorruptedSettingsRecoveryIfNeeded() -> Bool {
        guard !AppController.isRunningTests, !Constants.LaunchMode.shouldSuppressInterferenceUI else { return false }
        // Ensure Settings has attempted to load; this populates SettingsPersistence.corruptedState under the single gate.
        _ = Settings.shared
        guard let state = SettingsPersistence.corruptedState else { return false }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let backups = SettingsPersistence.availableBackups().filter { $0 != state.backupFile && $0 != state.file }
        let mostRecentBackup = backups.first
        let backupList = backups.prefix(3).map { $0.lastPathComponent }.joined(separator: ", ")
        let previewSnippet = String(state.preview.prefix(500))

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Quiper settings are corrupted"
        var info = "Your settings file could not be read and was not overwritten.\n\n"
        info += "File: \(state.file.path)\n"
        info += "Backup of corrupted file: \(state.backupFile.path)\n"
        if !backupList.isEmpty {
            info += "Recent backups: \(backupList)\n"
        }
        info += "\nError: \(String(describing: state.underlying))\n"
        if !previewSnippet.isEmpty {
            info += "\nPreview: \(previewSnippet)\n"
        }
        info += "\nChoose Quit to keep the file for manual repair, Reveal to show it in Finder, "
        if mostRecentBackup != nil {
            info += "Restore to replace it with \(mostRecentBackup!.lastPathComponent), "
        }
        info += "or Reset to start with defaults (the corrupted file stays backed up)."
        alert.informativeText = info

        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Reveal in Finder")
        if mostRecentBackup != nil {
            alert.addButton(withTitle: "Restore Backup")
        }
        alert.addButton(withTitle: "Reset to Defaults")

        let response = alert.runModal()
        // Button order: Quit=1000, Reveal=1001, (Restore=1002 if present), Reset=last
        let hasRestore = mostRecentBackup != nil
        if response == .alertFirstButtonReturn {
            NSApp.terminate(nil)
            return true
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([state.file, state.backupFile])
            NSApp.terminate(nil)
            return true
        } else if hasRestore && response == .alertThirdButtonReturn {
            if let backup = mostRecentBackup {
                Settings.shared.restoreCorruptedConfig(from: backup)
                // Continue launch after restore
                return false
            }
            NSApp.terminate(nil)
            return true
        } else {
            // Reset (third without restore, or fourth with restore)
            Settings.shared.resetCorruptedConfigToDefaults()
            return false
        }
    }

    private var isAutoLaunch: Bool {
        return CommandLine.arguments.contains("--autostart")
    }

    @objc func showSettings(_ sender: Any?) {
        statusBarController?.appController.showSettings(sender)
    }

    @objc func openDocumentation(_ sender: Any?) {
        statusBarController?.appController.openDocumentation(sender)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.keyWindow?.level = .modalPanel
    }

    private func createMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        NSApp.mainMenu = mainMenu

        // Application Menu (Quiper)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Quiper")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: "About Quiper", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = MenuFactory.createSettingsItem()
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        // Services Menu (Standard)
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(.separator())

        let hideAppItem = NSMenuItem(title: "Hide Quiper", action: #selector(AppController.closeSettingsOrHide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideAppItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(.separator())

        let quitItem = MenuFactory.createQuitItem()
        appMenu.addItem(quitItem)

        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = MenuFactory.createEditMenu()

        // View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        viewMenuItem.submenu = MenuFactory.createViewMenu()

        // Actions Menu
        let actionsMenuItem = NSMenuItem()
        mainMenu.addItem(actionsMenuItem)
        let actionsMenu = MenuFactory.createActionsMenu()
        actionsMenuItem.submenu = actionsMenu

        // Window Menu (Native)
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        // For Native Menu, we often want system behavior for "Minimize"/"Zoom".
        // MenuFactory creates them with standard selectors.
        let windowMenu = MenuFactory.createWindowMenu()
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = MenuFactory.createHelpMenu()
        helpMenuItem.submenu = helpMenu

        // Setting NSApp.helpMenu enables the system search field in the menu
        NSApp.helpMenu = helpMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let appController = statusBarController.appController
        if appController.consumeNotificationActivation() {
            appController.showWindow(nil)
        } else if NSApp.isActive && appController.isWindowVisible {
            appController.hideWindow(nil)
        } else {
            appController.showWindow(nil)
        }
        return true
    }

    /// The durability snapshot: the user has stepped away with the tab
    /// state still current, so capture it now in case a crash never
    /// brings them back. Focus events never save tab state — key status
    /// changes just as readily while windows are being torn down as when
    /// the user moves focus.
    func applicationDidResignActive(_ notification: Notification) {
        statusBarController?.appController.window.saveTabsState()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        statusBarController?.appController.window.saveTabsState()
        if Settings.shared.tabSurvivalPolicy == .askOnExit {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Close all tabs before exiting?"
            alert.informativeText = "Would you like to close all your open tabs, or keep them for your next session?"
            alert.addButton(withTitle: "Keep Tabs")
            alert.addButton(withTitle: "Close All Tabs")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[1].keyEquivalent = "\u{1b}"
            alert.alertStyle = .informational

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                Settings.shared.discardSavedTabs()
            } else if response == .alertThirdButtonReturn {
                return .terminateCancel
            }
        } else if Settings.shared.tabSurvivalPolicy == .never {
            Settings.shared.discardSavedTabs()
        }

        // The keep/discard decision is made: the saved tab state is
        // final, and every later save must stay out of its way — the
        // teardown ahead would rebuild it from a session coming apart
        // and resurrect tabs the user just chose to close.
        AppDelegate.hasCommittedTermination = true

        // 1b. Web `beforeunload`: quitting destroys every tab, so pages
        // reporting unsaved state get one shared confirmation. Synchronous
        // by necessity (see below); cancelling aborts the quit.
        if let mainWindow = statusBarController?.appController.window as? MainWindowController {
            let blocking = mainWindow.openTabsNeedingUnloadConfirmationSync()
            if !blocking.isEmpty {
                NSApp.activate(ignoringOtherApps: true)
                if !mainWindow.confirmUnloadSync(tabs: blocking, reason: .quit) {
                    // The quit is off and the app keeps running: the saves
                    // that keep the tab state current resume.
                    AppDelegate.hasCommittedTermination = false
                    return .terminateCancel
                }
            }
        }

        // 1. Immediately lock all encrypted engines in state
        for service in Settings.shared.services {
            if service.isEncrypted {
                EncryptedVolumeManager.shared.markLocked(service.id)
            }
        }

        // 2. Show the beautiful full-screen overlay in the main window
        statusBarController?.appController.window.showQuitOverlay()

        // 3. Perform unmounting on a background thread, then reply from there.
        // Must use GCD here, not Swift Task — NSApp.terminate() blocks the main thread
        // in a nested run loop that does not drain the Swift concurrency queue, so
        // Task { @MainActor in } and DispatchQueue.main.async both deadlock here.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.unmountAllEncryptedVolumes()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    private func hasMountedEncryptedVolumes() -> Bool {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let bundleID = Constants.BUNDLE_ID
        let webKitBase = libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")

        guard let contents = try? fileManager.contentsOfDirectory(at: webKitBase, includingPropertiesForKeys: nil) else {
            return false
        }

        for storeURL in contents {
            var statInfo = stat()
            if lstat(storeURL.path, &statInfo) == 0 {
                let isDir = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
                if isDir {
                    if let values = try? storeURL.resourceValues(forKeys: [.isVolumeKey]),
                       let isVol = values.isVolume,
                       isVol {
                        return true
                    }
                }
            }
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Fallback synchronous unmount to be completely safe
        unmountAllEncryptedVolumes()
    }

    nonisolated private func unmountAllEncryptedVolumes() {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let bundleID = Constants.BUNDLE_ID
        let webKitBase = libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")

        if let contents = try? fileManager.contentsOfDirectory(at: webKitBase, includingPropertiesForKeys: nil) {
            for storeURL in contents {
                var statInfo = stat()
                if lstat(storeURL.path, &statInfo) == 0 {
                    let isDir = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
                    if isDir {
                        var isVolume = false
                        if let values = try? storeURL.resourceValues(forKeys: [.isVolumeKey]),
                           let isVol = values.isVolume {
                            isVolume = isVol
                        }

                        if isVolume {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                            process.arguments = [
                                "eject",
                                "force",
                                storeURL.path
                            ]
                            try? process.run()
                            process.waitUntilExit()

                            try? fileManager.removeItem(at: storeURL)
                        }
                    }
                }
            }
        }
    }
}



// StatusBar components extracted to StatusBar.swift
