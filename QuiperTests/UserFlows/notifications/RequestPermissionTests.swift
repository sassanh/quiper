import XCTest
import WebKit
@testable import Quiper

@MainActor
final class RequestPermissionTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        Settings.shared.reset()
        windowController = MainWindowController()
        try TestServer.shared.start()
    }
    
    override func tearDown() async throws {
        TestServer.shared.stop()
        Settings.shared.reset()
    }
    
    func testRequestPermission() async throws {
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        Settings.shared.services = [testService]
        windowController.reloadServices([testService])
        
        windowController.show()
        if let webView = windowController.activeWebView {
            await windowController.waitForNavigation(on: webView)
        } else {
            XCTFail("Active WebView should not be nil")
        }
        
        // Inject script to request permission
        // Note: WebNotificationBridge has logic to skip actual permission prompt in tests if we mock it,
        // or we might hit a system prompt which blocks tests.
        // For now, we verify the bridge is installed.
        
        let result = try await windowController.activeWebView?.evaluateJavaScript("typeof window.__quiperNotificationBridge") as? String
        XCTAssertEqual(result, "object", "Notification bridge should be injected")
    }
}
