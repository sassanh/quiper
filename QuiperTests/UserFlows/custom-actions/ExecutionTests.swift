import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ExecutionTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        Settings.shared.reset()
        windowController = MainWindowController()
        try await TestServer.shared.start()
    }
    
    override func tearDown() async throws {
        TestServer.shared.stop()
        Settings.shared.reset()
    }
    
    func testCustomActionsExecution() async throws {
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        Settings.shared.services = [testService]
        windowController.reloadServices([testService])
        
        // Create a custom action
        let customAction = CustomAction(
            id: UUID(),
            name: "Test Action",
            shortcut: HotkeyManager.Configuration(keyCode: 0, modifierFlags: 0)
        )
        Settings.shared.customActions = [customAction]
        
        // Add script to service
        let script = "document.getElementById('new-chat-btn').click();"
        ActionScriptStorage.saveScript(script, serviceID: testService.id, actionID: customAction.id)
        
        // Reload to apply
        windowController.reloadServices([testService])
        
        windowController.show()
        
        if let webView = windowController.activeWebView {
            await windowController.waitForNavigation(on: webView)
        } else {
            XCTFail("Active WebView should not be nil")
        }
        
        // Execute Action
        windowController.performCustomAction(customAction)
        
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Verify Effect
        let status = try await windowController.activeWebView?.evaluateJavaScript("document.getElementById('status').innerText") as? String
        XCTAssertEqual(status, "New Chat Started", "Custom action should have clicked the button")
    }
}
