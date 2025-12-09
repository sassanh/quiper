import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ServiceSwitchingTests: XCTestCase {
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
    
    func testServiceSwitching() async throws {
        let service1 = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        let service2 = Service(
            name: "Service2",
            url: TestServer.shared.baseURL.deletingLastPathComponent().appendingPathComponent("subpage.html").absoluteString,
            focus_selector: "body"
        )
        
        Settings.shared.services = [service1, service2]
        windowController.reloadServices([service1, service2])
        
        windowController.show()
        
        // Wait for initial load
        if let webView = windowController.activeWebView {
            await windowController.waitForNavigation(on: webView)
        } else {
            XCTFail("Active WebView should not be nil")
        }
        
        // Verify initial state
        XCTAssertEqual(windowController.activeServiceURL, service1.url, "Should start on Service1")
        
        // Switch to Service2 (triggers new load)
        windowController.selectService(at: 1)
        
        if let webView2 = windowController.activeWebView {
            await windowController.waitForNavigation(on: webView2)
            XCTAssertEqual(windowController.activeServiceURL, service2.url, "Should switch to Service2")
            XCTAssertTrue(webView2.url?.absoluteString.contains("subpage") == true, "Should load subpage")
        } else {
            XCTFail("WebView for Service2 should not be nil")
        }
        
        // Switch back to Service1 (already loaded, no navigation wait needed)
        windowController.selectService(at: 0)
        
        XCTAssertEqual(windowController.activeServiceURL, service1.url, "Should switch back to Service1")
    }
}
