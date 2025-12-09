import XCTest
@testable import Quiper

@MainActor
final class DeleteServiceTests: XCTestCase {
    var windowController: MainWindowController!
    
    override func setUp() async throws {
        Settings.shared.reset()
        windowController = MainWindowController()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testDeleteService() async throws {
        let s1 = Service(name: "S1", url: "http://s1", focus_selector: "")
        Settings.shared.services = [s1]
        windowController.reloadServices([s1])
        
        XCTAssertEqual(windowController.services.count, 1)
        
        // Delete
        Settings.shared.services.removeAll()
        windowController.reloadServices(Settings.shared.services)
        
        XCTAssertEqual(windowController.services.count, 0)
    }
}
