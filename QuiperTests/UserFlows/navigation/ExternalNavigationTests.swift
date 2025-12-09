import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ExternalNavigationTests: XCTestCase {
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
    
    func testExternalNavigation() async throws {
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
        
        // Click external link
        // Note: In a real app this opens a browser. In test, we just verify the WebView didn't navigate.
        _ = try await windowController.activeWebView?.evaluateJavaScript("document.getElementById('external-link').click()")
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        // Verify URL did NOT change (navigation policy should block it)
        let currentURL = windowController.activeWebView?.url?.absoluteString
        XCTAssertEqual(currentURL, testService.url, "Should remain on original page")
    }
}
