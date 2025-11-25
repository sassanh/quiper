import XCTest
@testable import Quiper
import Carbon

@MainActor
final class ShortcutValidatorTests: XCTestCase {
    func testRejectsDigitWithoutModifiers() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_1),
            modifierFlags: 0
        )
        XCTAssertFalse(ShortcutValidator.allows(configuration: config))
    }

    func testRejectsCommandDigit() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_1),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertFalse(ShortcutValidator.allows(configuration: config))
    }

    func testAllowsCommandOptionLetter() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_A),
            modifierFlags: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        XCTAssertTrue(ShortcutValidator.allows(configuration: config))
    }

    func testReservedInspectorRequiresOption() {
        // cmd+option+I is reserved
        XCTAssertNotNil(ShortcutValidator.reservedActionName(
            modifiers: [.command, .option],
            keyCode: UInt16(kVK_ANSI_I)
        ))

        // cmd+I alone is not reserved
        XCTAssertNil(ShortcutValidator.reservedActionName(
            modifiers: [.command],
            keyCode: UInt16(kVK_ANSI_I)
        ))
    }

    func testReservedKeypadDigitIsDetected() {
        XCTAssertNotNil(ShortcutValidator.reservedActionName(
            modifiers: [.command],
            keyCode: UInt16(kVK_ANSI_Keypad5)
        ))
    }

    func testAllowsFunctionKeyWithoutModifiers() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_F5),
            modifierFlags: 0
        )
        XCTAssertTrue(ShortcutValidator.allows(configuration: config))
    }

    func testRejectsUnmodifiedLetter() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_Q),
            modifierFlags: 0
        )
        XCTAssertFalse(ShortcutValidator.allows(configuration: config))
    }
}
