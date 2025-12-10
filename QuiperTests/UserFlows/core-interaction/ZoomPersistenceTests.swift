import XCTest
import WebKit
@testable import Quiper

@MainActor
final class ZoomPersistenceTests: XCTestCase {
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
    
    func testZoomLevelPersistence() async throws {
        let testService = Service(
            name: "LocalTest",
            url: TestServer.shared.baseURL.absoluteString,
            focus_selector: "#prompt-textarea"
        )
        let service2 = Service(
            name: "Service2",
            url: TestServer.shared.baseURL.deletingLastPathComponent().appendingPathComponent("subpage.html").absoluteString,
            focus_selector: "body"
        )
        
        Settings.shared.services = [testService, service2]
        windowController.reloadServices([testService, service2])
        
        windowController.show()
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        
        let webView1 = windowController.activeWebView
        
        // Get initial zoom level (should be 1.0 by default)
        let initialZoom = webView1?.pageZoom ?? 0
        XCTAssertEqual(initialZoom, 1.0, "Initial zoom should be 1.0")
        
        // Simulate zoom in using the controller method
        windowController.zoom(by: 0.2) // Zoom.step is 0.2 (usually)
        
        // Switch to Service2
        windowController.selectService(at: 1)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        let webView2 = windowController.activeWebView
        let service2Zoom = webView2?.pageZoom ?? 0
        XCTAssertEqual(service2Zoom, 1.0, "Service2 should have default zoom")
        
        // Switch back to Service1
        windowController.selectService(at: 0)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        let webView1Again = windowController.activeWebView
        let persistedZoom = webView1Again?.pageZoom ?? 0
        
        // Verify zoom persisted (allow small float diff)
        XCTAssertEqual(persistedZoom, 1.2, accuracy: 0.01, "Service1 should persist zoom level")
    }
}
