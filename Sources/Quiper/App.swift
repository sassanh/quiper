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
}

@MainActor

final class AppController: NSObject, NSWindowDelegate {

    private let windowController = MainWindowController()

    private let hotkeyManager = HotkeyManager()
    private let engineHotkeyManager = EngineHotkeyManager()
    private let customActionDispatcher = CustomActionShortcutDispatcher()
    private var lastNonQuiperApplication: NSRunningApplication?



    override init() {

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(handleShowSettingsNotification), name: .showSettings, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(handleApplicationDidActivate(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)

    }



    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }



    func start() {

        registerOverlayHotkey()
        registerEngineHotkeys()
        UpdateManager.shared.handleLaunchIfNeeded()

    }



    @objc func showWindow(_ sender: Any?) {

        captureFrontmostNonQuiperApplication()
        windowController.show()
        customActionDispatcher.startMonitoring(windowController: windowController)

    }



    @objc func hideWindow(_ sender: Any?) {
        customActionDispatcher.stopMonitoring()
        windowController.hide()
        if AppDelegate.sharedSettingsWindow.isVisible == true {
            dismissSettingsWindow()
        }
        activateLastKnownApplication()
    }





    @objc func showSettings(_ sender: Any?) {

        presentSettingsWindow()

    }



    @objc func toggleInspector(_ sender: Any?) {

        windowController.toggleInspector()

    }



    @objc func clearWebViewData(_ sender: Any?) {

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in

            DispatchQueue.main.async {

                self?.windowController.focusInputInActiveWebview()

            }

        }

    }



    @objc func share(_ sender: Any?) {

        guard let url = windowController.currentWebViewURL(), let contentView = windowController.window?.contentView else {

            return

        }

        let anchor = NSView(frame: NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1))

        contentView.addSubview(anchor)

        let picker = NSSharingServicePicker(items: [url])

        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: NSRectEdge.maxY)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {

            anchor.removeFromSuperview()

        }

    }



    @objc func setHotkey(_ sender: Any?) {

        presentSettingsWindow()
        NotificationCenter.default.post(name: .startGlobalHotkeyCapture, object: nil)

    }



    @objc func openNotificationSettings(_ sender: Any?) {

        NotificationDispatcher.shared.openSystemNotificationSettings()

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
    }



    func focusMainWindowIfVisible() {

        guard windowController.window?.isVisible == true else { return }

        windowController.window?.makeKeyAndOrderFront(nil as Any?)

        windowController.focusInputInActiveWebview()

    }



    func setMainWindowShortcutsEnabled(_ enabled: Bool) {
        windowController.setShortcutsEnabled(enabled)
        guard windowController.window?.isVisible == true else {
            customActionDispatcher.stopMonitoring()
            return
        }
        if enabled {
            customActionDispatcher.startMonitoring(windowController: windowController)
        } else {
            customActionDispatcher.stopMonitoring()
        }
    }

    var currentServiceURL: String? {
        windowController.activeServiceURL
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
        app.activate(options: [.activateAllWindows])
    }

    @objc private func handleApplicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }
        lastNonQuiperApplication = app
    }



    private var mainWindowShield: InteractionShieldView?

    private func presentSettingsWindow() {
        let settingsWindow = AppDelegate.sharedSettingsWindow
        settingsWindow.appController = self
        guard let mainWindow = windowController.window else {
            if settingsWindow.isVisible == true {
                settingsWindow.orderOut(nil as Any?)
            } else {
                settingsWindow.makeKeyAndOrderFront(nil as Any?)
                NSApp.activate(ignoringOtherApps: true)
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
        settingsWindow.makeKeyAndOrderFront(nil as Any?)
        NSApp.activate(ignoringOtherApps: true)
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
    }

    private func registerOverlayHotkey() {
        hotkeyManager.registerCurrentHotkey { [weak self] in
            guard let self else { return }
            if AppDelegate.sharedSettingsWindow.isVisible && AppDelegate.sharedSettingsWindow.isKeyWindow {
                return
            }
            if self.windowController.window?.isVisible == true {
                self.hideWindow(nil)
            } else {
                self.showWindow(nil)
            }
        }
    }

    private func registerEngineHotkeys() {
        let overlayHotkey = Settings.shared.hotkeyConfiguration
        var blockedHotkeys: [HotkeyManager.Configuration] = [overlayHotkey]
        if isRunningInXcode, HotkeyManager.defaultConfiguration == overlayHotkey {
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
            if AppDelegate.sharedSettingsWindow.isVisible && AppDelegate.sharedSettingsWindow.isKeyWindow {
                return
            }
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

    private var isRunningInXcode: Bool {
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



        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        NotificationDispatcher.shared.configure(delegate: statusBarController.appController)

        createMainMenu()

        statusBarController.install()



        AppDelegate.sharedSettingsWindow.appController = statusBarController.appController



    }

    private func createMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        NSApp.mainMenu = mainMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// MARK: - Status Bar Controller
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let iconProvider: StatusIconProvider
    private let menuBuilder: StatusMenuBuilder
    private let buttonFactory: StatusButtonFactory

    let appController = AppController()

    init(statusItemLength: CGFloat = NSStatusItem.squareLength,
         iconProvider: StatusIconProvider = StatusIconProvider(),
         menuBuilder: StatusMenuBuilder = StatusMenuBuilder(),
         buttonFactory: StatusButtonFactory = StatusButtonFactory()) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.iconProvider = iconProvider
        self.menuBuilder = menuBuilder
        self.buttonFactory = buttonFactory
    }

    func install() {
        configureStatusItem()
        appController.start()
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        statusItem.behavior = [.removalAllowed]
        print("[StatusBar] Configuring status item…")

        guard let button = statusItem.button else {
            assertionFailure("Expected NSStatusItem.button to be available")
            return
        }

        let size = NSStatusBar.system.thickness
        button.frame = NSRect(x: 0, y: 0, width: size, height: size)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.focusRingType = .none

        if let logo = iconProvider.loadStatusBarIcon() {
            logo.isTemplate = true
            button.imagePosition = .imageOnly
            button.image = logo
            button.title = ""
            print("[StatusBar] Loaded template logo icon")
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "🔍"
            button.font = NSFont.systemFont(ofSize: 16, weight: .bold)
            print("[StatusBar] Using fallback glyph title")
        }

        if statusItem.menu == nil {
            statusItem.menu = menuBuilder.buildStatusMenu(controller: appController)
            NotificationCenter.default.addObserver(forName: .inspectorVisibilityChanged, object: nil, queue: .main) { [weak self] note in
                let visible = (note.object as? Bool) ?? false
                Task { @MainActor [weak self] in
                    guard let self, let menu = self.statusItem.menu else { return }
                    let title = visible ? "Hide Inspector" : "Show Inspector"
                    if let item = menu.items.first(where: { $0.action == #selector(AppController.toggleInspector(_:)) }) {
                        item.title = title
                    }
                }
            }
        }
    }
}

// MARK: - Status Button Factory
@MainActor
struct StatusButtonFactory {
    func makeCustomStatusButton(for statusItem: NSStatusItem) -> NSButton {
        guard let button = statusItem.button else {
            assertionFailure("Expected NSStatusItem.button to be available")
            return NSButton()
        }
        return button
    }
}

// MARK: - Icon Provider
@MainActor
struct StatusIconProvider {
    private let targetSize = NSSize(width: 18, height: 18)

    func loadStatusBarIcon() -> NSImage? {
        for url in statusIconCandidateURLs() {
            if let image = NSImage(contentsOf: url) {
                return resizedTemplateIcon(from: image)
            }
        }

        if let namedImage = NSImage(named: "logo") ?? NSImage(named: "logo_dark") {
            return resizedTemplateIcon(from: namedImage)
        }

        return nil
    }

    private func statusIconCandidateURLs() -> [URL] {
        var urls: [URL] = []

        if let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
            urls.append(url)
        }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "logo") {
            urls.append(url)
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("logo/logo.png", isDirectory: false),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            urls.append(resourceURL)
        }

        urls.append(contentsOf: developmentResourceCandidates())

        return urls
    }

    private func developmentResourceCandidates() -> [URL] {
        var candidates: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Sources/Quiper/logo/logo.png", isDirectory: false)
        if FileManager.default.fileExists(atPath: cwd.path) {
            candidates.append(cwd)
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent("logo/logo.png", isDirectory: false)
        if FileManager.default.fileExists(atPath: sourceFileURL.path) {
            candidates.append(sourceFileURL)
        }

        return candidates
    }

    private func resizedTemplateIcon(from image: NSImage) -> NSImage {
        let icon = NSImage(size: targetSize)
        icon.lockFocus()
        defer { icon.unlockFocus() }

        let rect = NSRect(origin: .zero, size: targetSize)
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        icon.isTemplate = true
        return icon
    }
}

// MARK: - Menu Builder
@MainActor
struct StatusMenuBuilder {
    func buildStatusMenu(controller: AnyObject) -> NSMenu {
        let menu = NSMenu()

        func addItem(_ title: String, _ action: Selector?, _ keyEquivalent: String = "", _ modifiers: NSEvent.ModifierFlags = [], _ target: AnyObject?) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }

        addItem("Show Quiper", #selector(AppController.showWindow(_:)), "", [], controller)
        addItem("Hide Quiper", #selector(AppController.hideWindow(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Settings", #selector(AppController.showSettings(_:)), ",", [.command], controller)
        addItem("Show Inspector", #selector(AppController.toggleInspector(_:)), "i", [.command, .option], controller)
        addItem("Share", #selector(AppController.share(_:)), "", [], controller)
        addItem("Set New Hotkey", #selector(AppController.setHotkey(_:)), "", [], controller)
        addItem("Notification Settings...", #selector(AppController.openNotificationSettings(_:)), "", [], controller)
        addItem("Check for Updates…", #selector(AppController.checkForUpdates(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Install at Login", #selector(AppController.installAtLogin(_:)), "", [], controller)
        addItem("Uninstall from Login", #selector(AppController.uninstallFromLogin(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Quit", #selector(NSApplication.terminate(_:)), "q", [.command], NSApp)

        return menu
    }
}

private final class InteractionShieldView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}
