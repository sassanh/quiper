import XCTest
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class MainWindowControllerShortcutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure tests are not affected by any persisted shortcut customizations.
        Settings.shared.appShortcutBindings = .defaults
    }

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

    func testDigitShortcutSelectsSession() {
        let controller = makeController()
        controller.switchSession(to: 0)

        let handled = controller.handleCommandShortcut(event: digitEvent(number: 3, modifiers: [.command]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 2)
    }

    func testDigitShortcutSelectsService() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: digitEvent(number: 2, modifiers: [.command, .control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeServiceURL, "https://beta.test")
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

    private func digitEvent(number: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let digitKeyCode: UInt16
        switch number {
        case 1: digitKeyCode = UInt16(kVK_ANSI_1)
        case 2: digitKeyCode = UInt16(kVK_ANSI_2)
        case 3: digitKeyCode = UInt16(kVK_ANSI_3)
        case 4: digitKeyCode = UInt16(kVK_ANSI_4)
        case 5: digitKeyCode = UInt16(kVK_ANSI_5)
        case 6: digitKeyCode = UInt16(kVK_ANSI_6)
        case 7: digitKeyCode = UInt16(kVK_ANSI_7)
        case 8: digitKeyCode = UInt16(kVK_ANSI_8)
        case 9: digitKeyCode = UInt16(kVK_ANSI_9)
        case 0: digitKeyCode = UInt16(kVK_ANSI_0)
        default: fatalError("Unsupported digit \(number)")
        }

        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\(number)",
            charactersIgnoringModifiers: "\(number)",
            isARepeat: false,
            keyCode: digitKeyCode
        )!
    }
}
