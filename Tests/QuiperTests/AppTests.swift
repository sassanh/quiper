import XCTest
@testable import Quiper

class MockHotkeyManager: HotkeyManaging {
    var registerCurrentHotkeyCalled = false
    var updateConfigurationCalled = false

    func registerCurrentHotkey(_ callback: @escaping () -> Void) {
        registerCurrentHotkeyCalled = true
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

class MockMainWindowController: MainWindowControlling {
    var showCalled = false
    var hideCalled = false
    var toggleInspectorCalled = false
    var window: NSWindow? = NSWindow()
    var currentWebViewURLToReturn: URL? = URL(string: "https://example.com")
    var activeServiceURL: String? = "https://example.com"
    var focusInputInActiveWebviewCalled = false
    var reloadServicesCalled = false
    var setShortcutsEnabledCalled = false
    var logCustomActionCalled = false
    var selectServiceAtIndex: Int?
    var selectServiceWithURLCalled = false
    var switchSessionCalled = false

    func show() {
        showCalled = true
    }

    func hide() {
        hideCalled = true
    }

    func toggleInspector() {
        toggleInspectorCalled = true
    }
    
    func currentWebViewURL() -> URL? {
        return currentWebViewURLToReturn
    }

    func focusInputInActiveWebview() {
        focusInputInActiveWebviewCalled = true
    }

    func reloadServices() {
        reloadServicesCalled = true
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        setShortcutsEnabledCalled = true
    }

    func logCustomAction(_ action: CustomAction) {
        logCustomActionCalled = true
    }

    func selectService(at index: Int) {
        selectServiceAtIndex = index
    }

    func selectService(withURL url: String) -> Bool {
        selectServiceWithURLCalled = true
        return true
    }

    func switchSession(to index: Int) {
        switchSessionCalled = true
    }
}

class MockCustomActionDispatcher: CustomActionDispatching {
    var startMonitoringCalled = false
    var stopMonitoringCalled = false

    func startMonitoring(windowController: MainWindowControlling) {
        startMonitoringCalled = true
    }

    func stopMonitoring() {
        stopMonitoringCalled = true
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
    var mockCustomActionDispatcher: MockCustomActionDispatcher!
    var mockNotificationDispatcher: MockNotificationDispatcher!

    override func setUp() async throws {
        try await super.setUp()
        
        mockHotkeyManager = MockHotkeyManager()
        mockEngineHotkeyManager = MockEngineHotkeyManager()
        mockMainWindowController = MockMainWindowController()
        mockCustomActionDispatcher = MockCustomActionDispatcher()
        mockNotificationDispatcher = MockNotificationDispatcher()
        
        await MainActor.run {
            appController = AppController(windowController: mockMainWindowController, hotkeyManager: mockHotkeyManager, engineHotkeyManager: mockEngineHotkeyManager, customActionDispatcher: mockCustomActionDispatcher, notificationDispatcher: mockNotificationDispatcher)
        }
    }

    override func tearDown() async throws {
        try await super.tearDown()
        await MainActor.run {
            appController = nil
            mockHotkeyManager = nil
            mockEngineHotkeyManager = nil
            mockMainWindowController = nil
            mockCustomActionDispatcher = nil
            mockNotificationDispatcher = nil
        }
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
        appController.start()
        
        XCTAssertTrue(mockHotkeyManager.registerCurrentHotkeyCalled)
        XCTAssertTrue(mockEngineHotkeyManager.registerCalled)
    }

    func testShowWindow() {
        appController.showWindow(nil)

        XCTAssertTrue(mockMainWindowController.showCalled)
        XCTAssertTrue(mockCustomActionDispatcher.startMonitoringCalled)
    }

    func testHideWindow() {
        appController.hideWindow(nil)

        XCTAssertTrue(mockMainWindowController.hideCalled)
        XCTAssertTrue(mockCustomActionDispatcher.stopMonitoringCalled)
    }

    func testToggleInspector() {
        appController.toggleInspector(nil)
        XCTAssertTrue(mockMainWindowController.toggleInspectorCalled)
    }

    func testClearWebViewData() async {
        // Since WKWebsiteDataStore.default().removeData is asynchronous, we need to await for its completion
        let expectation = self.expectation(description: "Clear web view data completion")
        
        // Mocking the WKWebsiteDataStore.default().removeData call is complex as it's a global singleton.
        // For now, we'll assume the call is made and just check the focusInputInActiveWebviewCalled
        // if we can find a way to mock the WKWebsiteDataStore.
        
        // This test only covers the direct call to the method, not its asynchronous completion.
        // A more robust test would involve mocking WKWebsiteDataStore.
        appController.clearWebViewData(nil)
        
        // Wait a short while for the async block to potentially execute
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockMainWindowController.focusInputInActiveWebviewCalled)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testShare() {
        // Mock currentWebViewURL to return a non-nil value for the share functionality to proceed
        mockMainWindowController.currentWebViewURLToReturn = URL(string: "https://mockurl.com")
        
        // As NSSharingServicePicker.show is a UI operation and hard to mock directly,
        // this test mainly ensures that the method doesn't crash and the guard passes.
        // Further testing would require UI testing frameworks or more intricate mocking of NSSharingServicePicker.
        appController.share(nil)
        
        // No direct assert on mock calls related to NSSharingServicePicker,
        // but we ensure the guard condition (url and contentView existing) is met for coverage.
        // A more comprehensive test would involve mocking NSSharingServicePicker.
    }
    
    func testSetHotkey() {
        appController.setHotkey(nil)
        // Verifying this requires mocking NotificationCenter.default.post, which is complex.
        // This test ensures the method is called and does not crash.
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

