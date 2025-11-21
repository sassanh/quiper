import XCTest
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class MainWindowControllerShortcutTests: XCTestCase {
    func testCommandArrowAdvancesSession() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .shift]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 1)
    }

    func testCommandArrowWrapsSessionLeft() {
        let controller = makeController()
        controller.switchSession(to: 0)

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_LeftArrow), modifiers: [.command, .shift]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 9)
    }

    func testCommandControlArrowChangesService() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeServiceURL, "https://beta.test")
    }

    func testCommandOptionArrowIsIgnored() {
        let controller = makeController()
        controller.switchSession(to: 3)

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .option]))

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.activeSessionIndex, 3)
    }

    // MARK: - Helpers

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        return controller
    }

    private func arrowEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
