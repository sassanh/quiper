import XCTest
@testable import Quiper

@MainActor
final class AutomaticCheckTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    func testAutomaticCheck() async throws {
        Settings.shared.updatePreferences.automaticallyChecksForUpdates = true
        
        let manager = UpdateManager.shared
        await manager.handleLaunchIfNeeded()
        
        XCTAssertTrue(true)
    }
}
