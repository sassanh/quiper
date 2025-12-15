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
}

@objc protocol StandardEditActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

@MainActor
final class AppController: NSObject, NSWindowDelegate {
    
    private let windowController: MainWindowControlling
    let hotkeyManager: HotkeyManaging
    let engineHotkeyManager: EngineHotkeyManaging
    private let notificationDispatcher: NotificationDispatching
    private var lastNonQuiperApplication: NSRunningApplication?
    private let isRunningTests: Bool
    private let testDataStore: WKWebsiteDataStore
    
    
    
    init(windowController: MainWindowControlling? = nil,
         hotkeyManager: HotkeyManaging? = nil,
         engineHotkeyManager: EngineHotkeyManaging? = nil,
         notificationDispatcher: NotificationDispatching? = nil) {
        
        // Instantiate defaults inside the body (which is safely on MainActor)
        self.windowController = windowController ?? MainWindowController()
        self.hotkeyManager = hotkeyManager ?? HotkeyManager()
        self.engineHotkeyManager = engineHotkeyManager ?? EngineHotkeyManager()
        self.notificationDispatcher = notificationDispatcher ?? NotificationDispatcher.shared
        self.isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.testDataStore = WKWebsiteDataStore.nonPersistent()
        
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowSettingsNotification), name: .showSettings, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(handleApplicationDidActivate(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDockVisibilityChanged), name: .dockVisibilityChanged, object: nil)
    }
    
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    
    
    func start() {
        
        if Settings.shared.dockVisibility == .always {
            NSApp.setActivationPolicy(.regular)
        }
        
        registerOverlayHotkey()
        registerEngineHotkeys()
        UpdateManager.shared.handleLaunchIfNeeded()
        
    }
    
    
    
    @objc func showWindow(_ sender: Any?) {
        
        captureFrontmostNonQuiperApplication()
        let visibility = Settings.shared.dockVisibility
        if visibility == .always || visibility == .whenVisible {
            NSApp.setActivationPolicy(.regular)
        }
        windowController.show()
        NotificationCenter.default.post(name: .appVisibilityChanged, object: true)
        
    }
    
    
    
    @objc func hideWindow(_ sender: Any?) {
        windowController.hide()
        let visibility = Settings.shared.dockVisibility
        if visibility == .whenVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        if AppDelegate.sharedSettingsWindow.isVisible == true {
            dismissSettingsWindow()
        }
        activateLastKnownApplication()
        NotificationCenter.default.post(name: .appVisibilityChanged, object: false)
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
    
    
    
    @objc func toggleInspector(_ sender: Any?) {
        
        windowController.toggleInspector()
        
    }
    
    
    
    @objc func clearWebViewData(_ sender: Any?) {
        let store = isRunningTests ? testDataStore : WKWebsiteDataStore.default()
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
        AppDelegate.sharedSettingsWindow.makeKeyAndOrderFront(nil)
        
    }
    
    @objc func setHotkey(_ sender: Any?) {
        
        presentSettingsWindow()
        NotificationCenter.default.post(name: .startGlobalHotkeyCapture, object: nil)
        
    }
    
    
    
    @objc func openNotificationSettings(_ sender: Any?) {
        
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
        
        windowController.window?.makeKeyAndOrderFront(nil as Any?)
        
        windowController.focusInputInActiveWebview()
        
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
        windowController.window?.isVisible == true
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
                let visibility = Settings.shared.dockVisibility
                if visibility == .always || visibility == .whenVisible {
                    NSApp.setActivationPolicy(.regular)
                }
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
        let visibility = Settings.shared.dockVisibility
        if visibility == .always || visibility == .whenVisible {
            NSApp.setActivationPolicy(.regular)
        }
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
        
        let visibility = Settings.shared.dockVisibility
        if isWindowVisible == false && visibility == .whenVisible {
            NSApp.setActivationPolicy(.accessory)
        }
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

    @objc func showSettings(_ sender: Any?) {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
    
    private func createMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        NSApp.mainMenu = mainMenu
        
        // Application Menu (Quiper)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Quiper")
        appMenuItem.submenu = appMenu
        
        let aboutItem = NSMenuItem(title: "About Quiper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
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
        
        let hideAppItem = NSMenuItem(title: "Hide Quiper", action: #selector(AppController.closeSettingsOrHide(_:)), keyEquivalent: "w")
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
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu

        // Setting NSApp.helpMenu enables the system search field in the menu
        NSApp.helpMenu = helpMenu
        
        let helpItem = MenuFactory.createMenuItem(title: "Quiper Help", iconName: "questionmark.circle", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        helpMenu.addItem(helpItem)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController.appController.showWindow(nil)
        return true
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
         iconProvider: StatusIconProvider? = nil,
         menuBuilder: StatusMenuBuilder? = nil,
         buttonFactory: StatusButtonFactory? = nil) {
        
        self.statusItem = NSStatusBar.system.statusItem(withLength: statusItemLength)
        
        // Instantiate defaults safely inside the MainActor-isolated body
        self.iconProvider = iconProvider ?? StatusIconProvider()
        self.menuBuilder = menuBuilder ?? StatusMenuBuilder()
        self.buttonFactory = buttonFactory ?? StatusButtonFactory()
    }
    
    func install() {
        configureStatusItem()
        appController.start()
    }
    
    private func configureStatusItem() {
        statusItem.isVisible = true
        statusItem.behavior = [.removalAllowed]
        
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
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "🔍"
            button.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        }
        
        if statusItem.menu == nil {
            rebuildStatusMenu()
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
            NotificationCenter.default.addObserver(forName: .appVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
            NotificationCenter.default.addObserver(forName: .hotkeyConfigurationChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
            NotificationCenter.default.addObserver(forName: .notificationPermissionChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
        }
    }

    private func rebuildStatusMenu() {
        statusItem.menu = menuBuilder.buildStatusMenu(controller: appController)
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
        
        let isVisible = (controller as? AppController)?.isWindowVisible ?? false
        let showHideTitle = isVisible ? "Hide Quiper" : "Show Quiper"
        let showHideAction = isVisible ? #selector(AppController.hideWindow(_:)) : #selector(AppController.showWindow(_:))
        let showHideItem = NSMenuItem(title: showHideTitle, action: showHideAction, keyEquivalent: "")
        showHideItem.target = controller
        if let hotkey = keyEquivalent(for: Settings.shared.hotkeyConfiguration) {
            showHideItem.keyEquivalent = hotkey.key
            showHideItem.keyEquivalentModifierMask = hotkey.modifiers
        }
        menu.addItem(showHideItem)
        menu.addItem(.separator())
        addItem("Settings", #selector(AppController.showSettings(_:)), ",", [.command], controller)
        addItem("Show Inspector", #selector(AppController.toggleInspector(_:)), "i", [.command, .option], controller)
        addItem("Set New Hotkey", #selector(AppController.setHotkey(_:)), "", [], controller)
        
        let notifStatus = NotificationDispatcher.shared.authorizationStatus
        let notifTitle: String
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: notifTitle = "Notifications: Authorized"
        case .denied: notifTitle = "Notifications: Denied"
        case .notDetermined: notifTitle = "Notifications: Not Enabled"
        @unknown default: notifTitle = "Notifications: Unknown"
        }
        addItem(notifTitle, #selector(AppController.openNotificationSettings(_:)), "", [], controller)
        
        addItem("Check for Updates…", #selector(AppController.checkForUpdates(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Install at Login", #selector(AppController.installAtLogin(_:)), "", [], controller)
        addItem("Uninstall from Login", #selector(AppController.uninstallFromLogin(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Quit", #selector(NSApplication.terminate(_:)), "q", [.command, .shift, .control], NSApp)
        
        return menu
    }

    private func keyEquivalent(for configuration: HotkeyManager.Configuration) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags).intersection([.command, .option, .control, .shift])
        guard let key = character(for: UInt16(configuration.keyCode)) else { return nil }
        let normalizedKey = key.count == 1 ? key.lowercased() : key
        return (normalizedKey, modifiers)
    }

    private func character(for keyCode: UInt16) -> String? {
        if keyCode == UInt16(kVK_Delete) {
            return statusDeleteKeyEquivalent
        }
        if keyCode == UInt16(kVK_Space) {
            return " "
        }
        return statusKeyEquivalentMap[keyCode]
    }
}

private let statusDeleteKeyEquivalent: String = {
    guard let scalar = UnicodeScalar(NSDeleteCharacter) else { return "" }
    return String(Character(scalar))
}()

private let statusKeyEquivalentMap: [UInt16: String] = [
    UInt16(kVK_ANSI_A): "a",
    UInt16(kVK_ANSI_B): "b",
    UInt16(kVK_ANSI_C): "c",
    UInt16(kVK_ANSI_D): "d",
    UInt16(kVK_ANSI_E): "e",
    UInt16(kVK_ANSI_F): "f",
    UInt16(kVK_ANSI_G): "g",
    UInt16(kVK_ANSI_H): "h",
    UInt16(kVK_ANSI_I): "i",
    UInt16(kVK_ANSI_J): "j",
    UInt16(kVK_ANSI_K): "k",
    UInt16(kVK_ANSI_L): "l",
    UInt16(kVK_ANSI_M): "m",
    UInt16(kVK_ANSI_N): "n",
    UInt16(kVK_ANSI_O): "o",
    UInt16(kVK_ANSI_P): "p",
    UInt16(kVK_ANSI_Q): "q",
    UInt16(kVK_ANSI_R): "r",
    UInt16(kVK_ANSI_S): "s",
    UInt16(kVK_ANSI_T): "t",
    UInt16(kVK_ANSI_U): "u",
    UInt16(kVK_ANSI_V): "v",
    UInt16(kVK_ANSI_W): "w",
    UInt16(kVK_ANSI_X): "x",
    UInt16(kVK_ANSI_Y): "y",
    UInt16(kVK_ANSI_Z): "z",
    UInt16(kVK_ANSI_0): "0",
    UInt16(kVK_ANSI_1): "1",
    UInt16(kVK_ANSI_2): "2",
    UInt16(kVK_ANSI_3): "3",
    UInt16(kVK_ANSI_4): "4",
    UInt16(kVK_ANSI_5): "5",
    UInt16(kVK_ANSI_6): "6",
    UInt16(kVK_ANSI_7): "7",
    UInt16(kVK_ANSI_8): "8",
    UInt16(kVK_ANSI_9): "9",
    UInt16(kVK_ANSI_Grave): "`",
    UInt16(kVK_ANSI_Minus): "-",
    UInt16(kVK_ANSI_Equal): "=",
    UInt16(kVK_ANSI_LeftBracket): "[",
    UInt16(kVK_ANSI_RightBracket): "]",
    UInt16(kVK_ANSI_Semicolon): ";",
    UInt16(kVK_ANSI_Quote): "'",
    UInt16(kVK_ANSI_Comma): ",",
    UInt16(kVK_ANSI_Period): ".",
    UInt16(kVK_ANSI_Slash): "/",
    UInt16(kVK_ANSI_Backslash): "\\",
    UInt16(kVK_ISO_Section): "§",
    UInt16(kVK_F1): String(UnicodeScalar(NSF1FunctionKey)!),
    UInt16(kVK_F2): String(UnicodeScalar(NSF2FunctionKey)!),
    UInt16(kVK_F3): String(UnicodeScalar(NSF3FunctionKey)!),
    UInt16(kVK_F4): String(UnicodeScalar(NSF4FunctionKey)!),
    UInt16(kVK_F5): String(UnicodeScalar(NSF5FunctionKey)!),
    UInt16(kVK_F6): String(UnicodeScalar(NSF6FunctionKey)!),
    UInt16(kVK_F7): String(UnicodeScalar(NSF7FunctionKey)!),
    UInt16(kVK_F8): String(UnicodeScalar(NSF8FunctionKey)!),
    UInt16(kVK_F9): String(UnicodeScalar(NSF9FunctionKey)!),
    UInt16(kVK_F10): String(UnicodeScalar(NSF10FunctionKey)!),
    UInt16(kVK_F11): String(UnicodeScalar(NSF11FunctionKey)!),
    UInt16(kVK_F12): String(UnicodeScalar(NSF12FunctionKey)!),
    UInt16(kVK_UpArrow): String(UnicodeScalar(NSUpArrowFunctionKey)!),
    UInt16(kVK_DownArrow): String(UnicodeScalar(NSDownArrowFunctionKey)!),
    UInt16(kVK_LeftArrow): String(UnicodeScalar(NSLeftArrowFunctionKey)!),
    UInt16(kVK_RightArrow): String(UnicodeScalar(NSRightArrowFunctionKey)!),
    UInt16(kVK_Help): String(UnicodeScalar(NSHelpFunctionKey)!),
    UInt16(kVK_ForwardDelete): String(UnicodeScalar(NSDeleteFunctionKey)!),
    UInt16(kVK_Tab): "\t",
    UInt16(kVK_Return): "\r",
    UInt16(kVK_Escape): "\u{001B}",
    UInt16(kVK_PageUp): String(UnicodeScalar(NSPageUpFunctionKey)!),
    UInt16(kVK_PageDown): String(UnicodeScalar(NSPageDownFunctionKey)!),
    UInt16(kVK_End): String(UnicodeScalar(NSEndFunctionKey)!),
    UInt16(kVK_Home): String(UnicodeScalar(NSHomeFunctionKey)!),
    UInt16(kVK_ANSI_Keypad0): "0",
    UInt16(kVK_ANSI_Keypad1): "1",
    UInt16(kVK_ANSI_Keypad2): "2",
    UInt16(kVK_ANSI_Keypad3): "3",
    UInt16(kVK_ANSI_Keypad4): "4",
    UInt16(kVK_ANSI_Keypad5): "5",
    UInt16(kVK_ANSI_Keypad6): "6",
    UInt16(kVK_ANSI_Keypad7): "7",
    UInt16(kVK_ANSI_Keypad8): "8",
    UInt16(kVK_ANSI_Keypad9): "9",
    UInt16(kVK_ANSI_KeypadDecimal): ".",
    UInt16(kVK_ANSI_KeypadMultiply): "*",
    UInt16(kVK_ANSI_KeypadPlus): "+",
    UInt16(kVK_ANSI_KeypadClear): String(UnicodeScalar(NSClearDisplayFunctionKey)!),
    UInt16(kVK_ANSI_KeypadDivide): "/",
    UInt16(kVK_ANSI_KeypadEnter): "\r",
    UInt16(kVK_ANSI_KeypadMinus): "-",
    UInt16(kVK_ANSI_KeypadEquals): "="
]

private final class InteractionShieldView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}
