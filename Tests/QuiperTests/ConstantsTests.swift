import XCTest
@testable import Quiper

final class ConstantsTests: XCTestCase {
    func testBundleVersionExists() {
        // Verify that Bundle extension provides version info
        let version = Bundle.main.versionDisplayString
        XCTAssertFalse(version.isEmpty)
    }
    
    func testNotificationNamesAreDefined() {
        // Verify that notification names are properly defined
        let startCapture = Notification.Name.startGlobalHotkeyCapture
        XCTAssertNotNil(startCapture)
        XCTAssertFalse(startCapture.rawValue.isEmpty)
        
        let showSettings = Notification.Name.showSettings
        XCTAssertNotNil(showSettings)
        XCTAssertFalse(showSettings.rawValue.isEmpty)
        
        let inspectorChanged = Notification.Name.inspectorVisibilityChanged
        XCTAssertNotNil(inspectorChanged)
        XCTAssertFalse(inspectorChanged.rawValue.isEmpty)
    }
}
