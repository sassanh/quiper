import XCTest
import WebKit
@testable import Quiper

@MainActor
final class InAppNavigationTests: XCTestCase {
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
    
    func testInAppNavigation() async throws {
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
            return
        }
        
        // Click internal link
        if let webView = windowController.activeWebView {
            // Trigger navigation
            _ = try await webView.evaluateJavaScript("document.getElementById('internal-link').click()")
            
            // Wait for navigation to complete
            await windowController.waitForNavigation(on: webView)
            
            // Verify URL changed
            let currentURL = webView.url?.absoluteString
            XCTAssertTrue(currentURL?.contains("subpage") == true, "Should navigate to subpage")
        }
    }
}
