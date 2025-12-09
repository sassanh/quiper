import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ReceiveNotificationTests: XCTestCase {
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
    
    func testReceiveNotification() async throws {
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
        
        // Verify Notification object is replaced
        let isReplaced = try await windowController.activeWebView?.evaluateJavaScript("window.Notification.__quiperBridgeInstalled") as? Bool
        XCTAssertTrue(isReplaced == true, "Notification object should be replaced by bridge")
    }
}
