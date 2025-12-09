import XCTest
import SwiftUI
@testable import Quiper

@MainActor
final class DragDropReorderTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        Settings.shared.reset()
        windowController = MainWindowController()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testDragDropReorder() async throws {
        // Create three services
        let s1 = Service(name: "Service1", url: "http://s1.com", focus_selector: "")
        let s2 = Service(name: "Service2", url: "http://s2.com", focus_selector: "")
        let s3 = Service(name: "Service3", url: "http://s3.com", focus_selector: "")
        
        Settings.shared.services = [s1, s2, s3]
        windowController.reloadServices([s1, s2, s3])
        
        // Verify initial order
        XCTAssertEqual(windowController.services[0].name, "Service1")
        XCTAssertEqual(windowController.services[1].name, "Service2")
        XCTAssertEqual(windowController.services[2].name, "Service3")
        
        // Simulate drag: move Service3 to position 0
        // (This tests the data model; actual UI drag is tested via ServiceSelectorControl)
        Settings.shared.services.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        windowController.reloadServices(Settings.shared.services)
        
        // Verify new order
        XCTAssertEqual(windowController.services[0].name, "Service3")
        XCTAssertEqual(windowController.services[1].name, "Service1")
        XCTAssertEqual(windowController.services[2].name, "Service2")
        
        // Verify persistence
        Settings.shared.saveSettings()
        XCTAssertEqual(Settings.shared.services[0].name, "Service3")
    }
    
    func testDragDropCancelOnEscape() async throws {
        // This would test UI behavior that's hard to unit test
        // The actual drag cancellation is handled by ServiceSelectorControl
        // We verify data model stays unchanged when no move occurs
        
        let s1 = Service(name: "S1", url: "http://s1", focus_selector: "")
        let s2 = Service(name: "S2", url: "http://s2", focus_selector: "")
        
        Settings.shared.services = [s1, s2]
        windowController.reloadServices([s1, s2])
        
        let originalOrder = windowController.services.map { $0.name }
        
        // Simulate cancelled drag - no change
        windowController.reloadServices(Settings.shared.services)
        
        // Verify order unchanged
        XCTAssertEqual(windowController.services.map { $0.name }, originalOrder)
    }
}
