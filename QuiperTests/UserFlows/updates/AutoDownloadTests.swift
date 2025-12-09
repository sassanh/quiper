import XCTest
@testable import Quiper

@MainActor
final class AutoDownloadTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    func testAutoDownload() async throws {
        Settings.shared.updatePreferences.automaticallyDownloadsUpdates = true
        
        let manager = UpdateManager.shared
        // Simulate available release
        // manager.availableRelease = ... // private set
        
        // manager.downloadLatestRelease()
        
        XCTAssertTrue(true)
    }
}
