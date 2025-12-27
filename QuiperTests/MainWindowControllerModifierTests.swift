import XCTest
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class MainWindowControllerModifierTests: XCTestCase {
    
    private func getPrivateProperty<T>(_ object: Any, _ name: String) -> T? {
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if child.label == name {
                return child.value as? T
            }
        }
        return nil
    }

    override func tearDown() {
        super.tearDown()
        Settings.shared.reset()
    }

    func testModifierKeysExpandSessionSelector() async throws {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        
        // Force Auto/Compact mode to ensure they are visible/created
        Settings.shared.selectorDisplayMode = .compact
        NotificationCenter.default.post(name: .selectorDisplayModeChanged, object: nil)
        
        guard let sessionSel: CollapsibleSelector = getPrivateProperty(controller, "collapsibleSessionSelector") else {
            XCTFail("Could not find collapsibleSessionSelector via Mirror")
            return
        }
        
        // Initial state
        XCTAssertFalse(sessionSel.isExpanded)
        
        // Send Flags Changed Event: Cmd (Default for session digits)
        let event = NSEvent.keyEvent(with: .flagsChanged,
                                     location: .zero,
                                     modifierFlags: [.command],
                                     timestamp: 0,
                                     windowNumber: controller.window?.windowNumber ?? 0,
                                     context: nil,
                                     characters: "",
                                     charactersIgnoringModifiers: "",
                                     isARepeat: false,
                                     keyCode: 0)!
        
        controller.handleFlagsChanged(event: event)
        XCTAssertTrue(sessionSel.isExpanded, "Session selector should expand on Cmd")
        
        // Release keys
        let releaseEvent = NSEvent.keyEvent(with: .flagsChanged,
                                            location: .zero,
                                            modifierFlags: [],
                                            timestamp: 0,
                                            windowNumber: controller.window?.windowNumber ?? 0,
                                            context: nil,
                                            characters: "",
                                            charactersIgnoringModifiers: "",
                                            isARepeat: false,
                                            keyCode: 0)!
        
        controller.handleFlagsChanged(event: releaseEvent)
        
        // Wait for collapse (should be immediate now)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(sessionSel.isExpanded, "Session selector should collapse immediately on key release")
    }

    func testModifierKeysExpandServiceSelector() async throws {
        // Need at least 2 services to have segments? Or just 1 is enough for the selector to exist.
        // CollapsibleSelector works with 1 item.
        let services = [Service(name: "A", url: "a", focus_selector: ""), Service(name: "B", url: "b", focus_selector: "")]
        let controller = MainWindowController(services: services)
        Settings.shared.selectorDisplayMode = .compact
        NotificationCenter.default.post(name: .selectorDisplayModeChanged, object: nil)
        
        guard let serviceSel: CollapsibleSelector = getPrivateProperty(controller, "collapsibleServiceSelector") else {
            XCTFail("Could not find collapsibleServiceSelector via Mirror")
            return
        }
        
        XCTAssertFalse(serviceSel.isExpanded)
        
        // Cmd + Ctrl => Service
        let event = NSEvent.keyEvent(with: .flagsChanged,
                                     location: .zero,
                                     modifierFlags: [.command, .control],
                                     timestamp: 0,
                                     windowNumber: controller.window?.windowNumber ?? 0,
                                     context: nil,
                                     characters: "",
                                     charactersIgnoringModifiers: "",
                                     isARepeat: false,
                                     keyCode: 0)!
        
        controller.handleFlagsChanged(event: event)
        XCTAssertTrue(serviceSel.isExpanded, "Service selector should expand on Cmd+Ctrl")
        
        // Release
        let releaseEvent = NSEvent.keyEvent(with: .flagsChanged,
                                            location: .zero,
                                            modifierFlags: [],
                                            timestamp: 0,
                                            windowNumber: controller.window?.windowNumber ?? 0,
                                            context: nil,
                                            characters: "",
                                            charactersIgnoringModifiers: "",
                                            isARepeat: false,
                                            keyCode: 0)!
        
        controller.handleFlagsChanged(event: releaseEvent)
        
        // Wait for collapse (should be immediate now)
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertFalse(serviceSel.isExpanded, "Service selector should collapse immediately on key release")
    }
}
