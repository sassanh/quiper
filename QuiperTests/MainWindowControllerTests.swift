import XCTest
@testable import Quiper

@MainActor
final class MainWindowControllerTests: XCTestCase {

    func testSelectServiceWithURL() {
        // Given
        let service1 = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let service2 = Service(id: UUID(), name: "Service 2", url: "https://example.com/2", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service1, service2])
        
        // When selecting existing service
        let result1 = controller.selectService(withURL: "https://example.com/2")
        
        // Then
        XCTAssertTrue(result1)
        XCTAssertEqual(controller.activeServiceURL, "https://example.com/2")
        XCTAssertEqual(controller.currentServiceName, "Service 2")
        
        // When selecting non-existent service
        let result2 = controller.selectService(withURL: "https://example.com/3")
        
        // Then
        XCTAssertFalse(result2)
        // Should remain on previous selection
        XCTAssertEqual(controller.activeServiceURL, "https://example.com/2")
    }
}
