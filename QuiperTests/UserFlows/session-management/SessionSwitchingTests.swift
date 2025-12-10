import XCTest
import WebKit
@testable import Quiper

@MainActor
final class SessionSwitchingTests: XCTestCase {
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
    
    func testSessionSwitching() async throws {
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        Settings.shared.services = [testService]
        windowController.reloadServices([testService])
        
        // Verify window initialization
        XCTAssertNotNil(windowController.window, "Window should be initialized")
        XCTAssertNotNil(windowController.window?.contentView, "Window contentView should exist")
        
        windowController.show()
        
        // Get WebView and wait for initial navigation to complete
        guard let webView1 = windowController.activeWebView else {
            XCTFail("activeWebView should not be nil")
            return
        }
        
        // Wait for page load instead of arbitrary sleep
        await windowController.waitForNavigation(on: webView1)
        
        // Session 1: Type something
        _ = try await webView1.evaluateJavaScript("document.getElementById('prompt-textarea').value = 'Session 1 Data'")
        
        // Switch to Session 2
        windowController.switchSession(to: 1)
        
        guard let webView2 = windowController.activeWebView else {
            XCTFail("activeWebView for session 2 should not be nil")
            return
        }
        
        XCTAssertNotEqual(webView1, webView2, "Should have a different WebView for Session 2")
        
        // Wait for session 2 page load
        await windowController.waitForNavigation(on: webView2)
        
        // Verify Session 2 is empty
        let value2 = try await webView2.evaluateJavaScript("document.getElementById('prompt-textarea').value") as? String
        XCTAssertEqual(value2, "", "Session 2 should be empty")
        
        // Switch back to Session 1
        windowController.switchSession(to: 0)
        
        let webView1Again = windowController.activeWebView
        XCTAssertEqual(webView1, webView1Again, "Should return to original WebView")
        
        // Verify data preserved (no wait needed - already loaded)
        let value1 = try await webView1Again?.evaluateJavaScript("document.getElementById('prompt-textarea').value") as? String
        XCTAssertEqual(value1, "Session 1 Data", "Session 1 data should be preserved")
    }
}
