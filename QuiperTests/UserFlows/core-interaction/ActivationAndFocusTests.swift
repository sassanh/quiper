import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ActivationAndFocusTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        // Reset Settings State
        Settings.shared.reset()
        
        // Configure Settings with Local Test Service
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        Settings.shared.services = [testService]
        
        // Initialize Controllers
        windowController = MainWindowController()
        
        // Start Local Server
        try TestServer.shared.start()
    }
    
    override func tearDown() async throws {
        TestServer.shared.stop()
        Settings.shared.reset()
    }
    
    func testActivationAndFocus() async throws {
        // Setup
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        Settings.shared.services = [testService]
        windowController.reloadServices([testService])
        
        // Action: Show Window (directly via controller)
        windowController.show()
        
        // Verify 1: Window is visible
        XCTAssertTrue(windowController.window?.isVisible == true, "Window should be visible")
        
        // Wait for WebView to load
        let webView = windowController.activeWebView
        XCTAssertNotNil(webView, "Active WebView should exist")
        
        if let webView = webView {
            await windowController.waitForNavigation(on: webView)
            XCTAssertEqual(webView.url?.absoluteString, testService.url, "WebView should load the test service URL")
        }
        
        // Action: Focus Input (Manual trigger since windowDidBecomeKey might not fire in headless test)
        windowController.focusInputInActiveWebview()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Verify 3: Input is focused
        let isFocused = try await webView?.evaluateJavaScript("""
            document.activeElement.id === 'prompt-textarea'
        """) as? Bool
        
        XCTAssertTrue(isFocused == true, "Input field #prompt-textarea should be focused")
    }
}
