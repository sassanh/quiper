import XCTest
import WebKit
@testable import Quiper

class MockHotkeyManager: HotkeyManaging {
    var registerCurrentHotkeyCalled = false
    var updateConfigurationCalled = false
    var callback: (() -> Void)?

    func registerCurrentHotkey(_ callback: @escaping () -> Void) {
        registerCurrentHotkeyCalled = true
        self.callback = callback
    }

    func updateConfiguration(_ configuration: HotkeyManager.Configuration) {
        updateConfigurationCalled = true
    }
}

class MockEngineHotkeyManager: EngineHotkeyManaging {
    var registerCalled = false
    var disableCalled = false
    var updateCalled = false
    var unregisterCalled = false

    func register(entries: [EngineHotkeyManager.Entry], onTrigger: @escaping (UUID) -> Void) {
        registerCalled = true
    }

    func disable() {
        disableCalled = true
    }

    func update(configuration: HotkeyManager.Configuration, for serviceID: UUID) {
        updateCalled = true
    }

    func unregister(serviceID: UUID) {
        unregisterCalled = true
    }
}

@MainActor
class MockMainWindowController: MainWindowControlling {
    var showCalled = false
    var hideCalled = false
    var toggleInspectorCalled = false
    var window: NSWindow? = NSWindow()
    var currentWebViewURLToReturn: URL? = URL(string: "https://example.com")
    var activeServiceID: UUID?
    var activeWebView: WKWebView? = nil
    var focusInputInActiveWebviewCalled = false
    var focusInputInActiveWebviewWithFallbackCalled = false
    var reloadServicesCalled = false
    var setShortcutsEnabledCalled = false
    var performCustomActionCalled = false
    var selectServiceAtIndex: Int?
    var selectServiceWithIDCalled = false
    var switchSessionCalled = false
    var showQuitOverlayCalled = false
    var saveTabsStateCalled = false
    var showWebFullScreenBannerCalled = false
    var isWebContentFullscreen = false
    var isActiveSpaceWebFullscreen = false
    /// Simulates any other Quiper window (popup, HUD, Settings, update
    /// prompt) holding key status in the real controller.
    var otherQuiperWindowHasKeyStatus = false
    var isAnyQuiperWindowKey: Bool {
        window?.isKeyWindow == true || otherQuiperWindowHasKeyStatus
    }
    
    func showWebFullScreenBanner() {
        showWebFullScreenBannerCalled = true
    }

    func showQuitOverlay() {
        showQuitOverlayCalled = true
    }

    func saveTabsState() {
        saveTabsStateCalled = true
    }

    /// Mimics the real controller: show() and hide() post these so
    /// AppController's visibility handling runs in tests too.
    func show() {
        showCalled = true
        window?.orderFront(nil)
        NotificationCenter.default.post(name: .windowDidShow, object: nil)
    }

    func hide() {
        hideCalled = true
        window?.orderOut(nil)
        NotificationCenter.default.post(name: .windowDidHide, object: nil)
    }

    func toggleInspector() {
        toggleInspectorCalled = true
    }
    
    func focusInputInActiveWebview() {
        focusInputInActiveWebviewCalled = true
    }

    func focusInputInActiveWebviewWithFallback() {
        focusInputInActiveWebviewWithFallbackCalled = true
    }

    func reloadServices() {
        reloadServicesCalled = true
    }

    func unloadInfosNeedingConfirmation(for serviceIDs: [UUID]) async -> [TabUnloadInfo] {
        return []
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        setShortcutsEnabledCalled = true
    }

    func performCustomAction(_ action: CustomAction) {
        performCustomActionCalled = true
    }

    func selectService(at index: Int) {
        selectServiceAtIndex = index
    }

    func selectService(withID id: UUID) -> Bool {
        selectServiceWithIDCalled = true
        return true
    }

    func switchSession(to index: Int) {
        switchSessionCalled = true
    }
}

class MockNotificationDispatcher: NotificationDispatching {
    var openSystemNotificationSettingsCalled = false
    var configureCalled = false

    func openSystemNotificationSettings() {
        openSystemNotificationSettingsCalled = true
    }
    
    func configure(delegate: NotificationDispatcherDelegate?) {
        configureCalled = true
    }
}


@MainActor
final class AppControllerTests: XCTestCase {

    var appController: AppController!
    var mockHotkeyManager: MockHotkeyManager!
    var mockEngineHotkeyManager: MockEngineHotkeyManager!
    var mockMainWindowController: MockMainWindowController!
    var mockNotificationDispatcher: MockNotificationDispatcher!
    var originalActivationPolicy: NSApplication.ActivationPolicy!

    override func setUp() async throws {
        try await super.setUp()
        
        mockHotkeyManager = MockHotkeyManager()
        mockEngineHotkeyManager = MockEngineHotkeyManager()
        mockMainWindowController = MockMainWindowController()
        mockNotificationDispatcher = MockNotificationDispatcher()
        
        originalActivationPolicy = NSApp.activationPolicy()
        await MainActor.run {
            Settings.shared.wipeAllData()
            _ = Settings.shared.loadSettings()
            appController = AppController(windowController: mockMainWindowController, hotkeyManager: mockHotkeyManager, engineHotkeyManager: mockEngineHotkeyManager, notificationDispatcher: mockNotificationDispatcher)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mockMainWindowController.window?.orderOut(nil)
            NSApp.setActivationPolicy(originalActivationPolicy)
            Settings.shared.reset()
            Settings.shared.wipeAllData()
            appController = nil
            mockHotkeyManager = nil
            mockEngineHotkeyManager = nil
            mockMainWindowController = nil
            mockNotificationDispatcher = nil
        }
        try await super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(appController, "AppController should be initialized.")
        XCTAssert(appController.hotkeyManager is MockHotkeyManager, "HotkeyManager should be a mock.")
        XCTAssert(appController.engineHotkeyManager is MockEngineHotkeyManager, "EngineHotkeyManager should be a mock.")
        // Temporarily disabled due to type/actor isolation issues:
        // XCTAssert(appController.notificationDispatcher === mockNotificationDispatcher, "NotificationDispatcher should be the injected mock instance.")
        // Also assert that the configure method is called during AppDelegate's applicationDidFinishLaunching
        // This is not directly testable here as AppDelegate is not mocked.
    }

    func testStart() {
        // Setup a service with an activation shortcut to ensure registerEngineHotkeys proceeds
        let shortcut = HotkeyManager.Configuration(keyCode: 0, modifierFlags: 0)
        let service = Service(name: "Test Service", url: "https://test.com", focus_selector: "", activationShortcut: shortcut)
        let originalServices = Settings.shared.services
        Settings.shared.services = [service]
        
        defer {
            Settings.shared.services = originalServices
        }
        
        appController.start()
        
        XCTAssertTrue(mockHotkeyManager.registerCurrentHotkeyCalled)
        XCTAssertTrue(mockEngineHotkeyManager.registerCalled)
    }

    func testOverlayHotkeyShowsHiddenWindowForBothLevels() throws {
        appController.start()
        let callback = try XCTUnwrap(mockHotkeyManager.callback)
        let window = try XCTUnwrap(mockMainWindowController.window)

        for keepOnTop in [true, false] {
            Settings.shared.keepOverlayOnTop = keepOnTop
            window.orderOut(nil)
            XCTAssertFalse(window.isVisible)
            callback()
            XCTAssertTrue(window.isVisible)
        }
    }

    func testTopmostOverlayHotkeyStillHidesVisibleWindow() throws {
        Settings.shared.keepOverlayOnTop = true
        appController.start()
        let callback = try XCTUnwrap(mockHotkeyManager.callback)
        let window = try XCTUnwrap(mockMainWindowController.window)
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isOnActiveSpace)

        callback()
        XCTAssertFalse(window.isVisible)
    }

    func testNormalOverlayHotkeyDoesNotHideVisibleNonKeyWindow() throws {
        Settings.shared.keepOverlayOnTop = false
        appController.start()
        let callback = try XCTUnwrap(mockHotkeyManager.callback)
        let window = try XCTUnwrap(mockMainWindowController.window)
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.orderFront(nil)
        window.resignKey()
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isOnActiveSpace)
        XCTAssertFalse(window.isKeyWindow)

        callback()
        XCTAssertTrue(window.isVisible)
    }

    func testNormalOverlayHotkeyHidesWhenAnotherQuiperWindowHasKeyStatus() throws {
        Settings.shared.keepOverlayOnTop = false
        appController.start()
        let callback = try XCTUnwrap(mockHotkeyManager.callback)
        let window = try XCTUnwrap(mockMainWindowController.window)
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)

        NSApp.activate(ignoringOtherApps: true)
        guard NSApp.isActive else {
            throw XCTSkip("The test host refused activation")
        }
        mockMainWindowController.otherQuiperWindowHasKeyStatus = true

        callback()
        XCTAssertFalse(window.isVisible)
    }

    func testOverlayHotkeyPreservesFullscreenException() throws {
        appController.start()
        let callback = try XCTUnwrap(mockHotkeyManager.callback)
        let window = try XCTUnwrap(mockMainWindowController.window)
        mockMainWindowController.isActiveSpaceWebFullscreen = true

        for keepOnTop in [true, false] {
            Settings.shared.keepOverlayOnTop = keepOnTop
            window.orderOut(nil)
            callback()
            XCTAssertFalse(window.isVisible)
        }
    }

    func testShowWindow() {
        appController.showWindow(nil)

        XCTAssertTrue(mockMainWindowController.showCalled)
    }

    func testHideWindow() {
        appController.hideWindow(nil)

        XCTAssertTrue(mockMainWindowController.hideCalled)
    }

    func testToggleInspector() {
        appController.toggleInspector(nil)
        XCTAssertTrue(mockMainWindowController.toggleInspectorCalled)
    }

    func testClearWebViewData() async {
        // clearWebViewData calls WKWebsiteDataStore.removeData which is async.
        // We poll for the expected side effect instead of using a fixed delay.
        appController.clearWebViewData(nil)
        
        let predicate = NSPredicate { _, _ in
            self.mockMainWindowController.focusInputInActiveWebviewCalled
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertTrue(mockMainWindowController.focusInputInActiveWebviewCalled)
    }
    

    func testOpenNotificationSettings() {
        appController.openNotificationSettings(nil)
        XCTAssertTrue(mockNotificationDispatcher.openSystemNotificationSettingsCalled)
    }
    
    func testCheckForUpdates() {
        // This method calls a shared instance method on UpdateManager.
        // Mocking UpdateManager.shared is complex due to its singleton pattern.
        // This test ensures the method is callable and does not crash.
        appController.checkForUpdates(nil)
    }
    
    func testInstallAtLogin() {
        // This method calls a static method on Launcher, which is hard to mock.
        // The test ensures the method is callable and does not crash.
        appController.installAtLogin(nil)
    }
    
    func testUninstallFromLogin() {
        // This method calls a static method on Launcher, which is hard to mock.
        // The test ensures the method is callable and does not crash.
        appController.uninstallFromLogin(nil)
    }
}
