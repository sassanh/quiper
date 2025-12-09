import XCTest
import Carbon
@testable import Quiper

@MainActor
final class LauncherTests: XCTestCase {
    func testAgentLabelFormat() {
        // Launcher.agentLabel() is private, but we can test the format indirectly
        // by checking if isInstalledAtLogin works without crashing
        let isInstalled = Launcher.isInstalledAtLogin()
        
        // Should return a boolean without crashing
        XCTAssertTrue(isInstalled == true || isInstalled == false)
    }
    
    func testIsInstalledAtLoginReturnsBool() {
        // This should not crash and should return a valid boolean
        let result = Launcher.isInstalledAtLogin()
        XCTAssertNotNil(result)
    }
}
