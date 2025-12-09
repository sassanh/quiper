import XCTest
import SwiftUI
@testable import Quiper

@MainActor
final class ReorderServicesTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        Settings.shared.reset()
        windowController = MainWindowController()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testReorderServices() async throws {
        let s1 = Service(name: "S1", url: "http://s1", focus_selector: "")
        let s2 = Service(name: "S2", url: "http://s2", focus_selector: "")
        Settings.shared.services = [s1, s2]
        windowController.reloadServices([s1, s2])
        
        // Simulate reorder
        Settings.shared.services.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        windowController.reloadServices(Settings.shared.services)
        
        XCTAssertEqual(windowController.services[0].name, "S2")
        XCTAssertEqual(windowController.services[1].name, "S1")
    }
}
