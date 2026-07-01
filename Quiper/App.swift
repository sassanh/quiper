import AppKit
import Foundation
import WebKit
import SwiftUI
import UserNotifications
import Carbon

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
    }

    private func presentTemplateActionSyncMigrationPromptIfNeeded() {
        guard Settings.shared.needsTemplateActionSyncMigrationPrompt,
              !Self.isRunningTests else {
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

            let shouldUpdate = alert.runModal() == .alertFirstButtonReturn
            Settings.shared.resolveTemplateActionSyncMigration(updateScripts: shouldUpdate)
            self.reloadServices()
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

        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }



    @objc func showWindow(_ sender: Any?) {
        captureFrontmostNonQuiperApplication()
        if isActiveSpaceFullscreen() {
            NSApp.setActivationPolicy(.accessory)
        }
        windowController.show()
    }

    @objc func hideWindow(_ sender: Any?) {
        windowController.hide()
    }

    private func isActiveSpaceFullscreen() -> Bool {
        guard let mainScreen = NSScreen.main else { return false }

        let screenFrame = mainScreen.frame
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in windowListInfo {
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let ownerPID = info[kCGWindowOwnerPID as String] as? Int ?? -1

            // Ignore windows owned by Quiper itself
            if ownerPID == NSRunningApplication.current.processIdentifier {
                continue
            }

            // Ignore system UI elements
            if ownerName == "Dock" || ownerName == "Window Server" || ownerName == "Control Center" {
                continue
            }

            guard layer < 20 else { continue }

            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            }

            let widthDiff = abs(bounds.width - screenFrame.width)
            let isXAligned = abs(bounds.minX - screenFrame.minX) < 10
            let yDiff = bounds.minY - screenFrame.minY
            let heightDiff = screenFrame.height - bounds.height

            // Allow a tolerance (up to 120 points) for notch area at the top of the screen
            if isXAligned && widthDiff < 10 && yDiff >= 0 && yDiff <= 120 && heightDiff >= 0 && heightDiff <= 120 {
                return true
            }
        }

        return false
    }


    @objc private func handleWindowDidShow(_ notification: Notification) {
        let visibility = Settings.shared.dockVisibility
        if visibility == .always || visibility == .whenVisible {
            if !isActiveSpaceFullscreen() {
                NSApp.setActivationPolicy(.regular)
            }
        }
        if UpdatePromptWindowController.shared.window?.isVisible == true {
            UpdatePromptWindowController.shared.window?.makeKeyAndOrderFront(nil)
        } else if AppDelegate.sharedSettingsWindow.isVisible {
            AppDelegate.sharedSettingsWindow.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .appVisibilityChanged, object: true)
    }

    @objc private func handleWindowDidHide(_ notification: Notification) {
        let visibility = Settings.shared.dockVisibility
        activateLastKnownApplication()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if visibility == .always {
                if !self.isActiveSpaceFullscreen() {
                    NSApp.setActivationPolicy(.regular)
                } else {
                    NSApp.setActivationPolicy(.accessory)
                }
            } else if visibility == .whenVisible {
                NSApp.setActivationPolicy(.accessory)
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
        guard let url = URL(string: "https://sassanh.github.io/quiper/") else { return }
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
            if windowController.window?.isVisible == true {
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

    func updateOverlayHotkey(_ configuration: HotkeyManager.Configuration) {
        hotkeyManager.updateConfiguration(configuration)
        NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)
    }



    func focusMainWindowIfVisible() {

        guard windowController.window?.isVisible == true else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if UpdatePromptWindowController.shared.window?.isVisible == true {
                UpdatePromptWindowController.shared.window?.makeKeyAndOrderFront(nil)
            } else if AppDelegate.sharedSettingsWindow.isVisible {
                AppDelegate.sharedSettingsWindow.makeKeyAndOrderFront(nil)
            } else {
                self.windowController.window?.makeKeyAndOrderFront(nil)
                if let sheet = self.windowController.window?.attachedSheet {
                    sheet.makeKeyAndOrderFront(nil)
                } else if !GhostOnboardingManager.shared.isActive {
                    self.windowController.focusInputInActiveWebviewWithFallback()
                }
            }
        }

    }



    func setMainWindowShortcutsEnabled(_ enabled: Bool) {
        windowController.setShortcutsEnabled(enabled)
        guard windowController.window?.isVisible == true else {
            return
        }
    }

    var currentServiceURL: String? {
        windowController.activeServiceURL
    }

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
    }

    @objc private func handleActiveSpaceDidChange(_ notification: Notification) {
        let visibility = Settings.shared.dockVisibility
        if visibility == .always {
            if !isActiveSpaceFullscreen() {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }

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
                settingsWindow.orderOut(nil as Any?)
            } else {
                let visibility = Settings.shared.dockVisibility
                if visibility == .always || visibility == .whenVisible {
                    NSApp.setActivationPolicy(.regular)
                }
                settingsWindow.makeKeyAndOrderFront(nil as Any?)
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
        settingsWindow.makeKeyAndOrderFront(nil as Any?)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .settingsWindowDidOpen, object: nil)
    }

    private func dismissSettingsWindow() {
        let settingsWindow = AppDelegate.sharedSettingsWindow
        if let parent = settingsWindow.parent {
            parent.removeChildWindow(settingsWindow)
        }
        settingsWindow.orderOut(nil as Any?)
        removeShieldIfNeeded(from: windowController.window)
        setMainWindowShortcutsEnabled(true)
        focusMainWindowIfVisible()

        let visibility = Settings.shared.dockVisibility
        if isWindowVisible == false && visibility == .whenVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.post(name: .settingsWindowDidClose, object: nil)
    }

    private func registerOverlayHotkey() {
        hotkeyManager.registerCurrentHotkey { [weak self] in
            guard let self else { return }
            if self.isWindowVisible {
                self.hideWindow(nil)
            } else {
                self.showWindow(nil)
            }
        }
    }

    private func registerEngineHotkeys() {
        let overlayHotkey = Settings.shared.hotkeyConfiguration
        var blockedHotkeys: [HotkeyManager.Configuration] = [overlayHotkey]
        if AppController.isRunningInXcode, HotkeyManager.defaultConfiguration == overlayHotkey {
            // Xcode fallback registers Ctrl+Space; keep engine hotkeys off it.
            blockedHotkeys.append(
                HotkeyManager.Configuration(
                    keyCode: UInt32(kVK_Space),
                    modifierFlags: NSEvent.ModifierFlags.control.rawValue
                )
            )
        }

        let entries: [EngineHotkeyManager.Entry] = Settings.shared.services.compactMap { service in
            guard let shortcut = service.activationShortcut,
                  isBlocked(shortcut, blockedHotkeys: blockedHotkeys) == false else { return nil }
            return EngineHotkeyManager.Entry(serviceID: service.id, configuration: shortcut)
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
            focusMainWindowIfVisible()
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
                                didActivateNotificationForServiceURL serviceURL: String?,
                                sessionIndex: Int?) {
        showWindow(nil)
        if let url = serviceURL {
            _ = windowController.selectService(withURL: url)
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

    static var sharedSettingsWindow = SettingsWindow.shared

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

    private func completeLaunch() {
        statusBarController = StatusBarController()

        NotificationDispatcher.shared.configure(delegate: statusBarController.appController)

        createMainMenu()

        statusBarController.install()

        AppDelegate.sharedSettingsWindow.appController = statusBarController.appController

        // Asynchronously scan and clean up orphaned persistent WebKit cache directories
        WebKitCacheCleaner.cleanOrphanedStores()

        // Show the window if the user launched the app intentionally (double-click, Spotlight, etc.)
        // but stay hidden if launched automatically by a LaunchAgent at system boot (parent is launchd, pid 1)
        if !isAutoLaunch {
            statusBarController.appController.showWindow(nil)
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
        statusBarController.appController.showWindow(nil)
        return true
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
                            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                            process.arguments = [
                                "detach",
                                "-force",
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
