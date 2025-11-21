import XCTest
@testable import Quiper
import Carbon

final class ShortcutValidatorTests: XCTestCase {
    func testAllowsRejectsWhenNoPrimaryModifier() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_A),
            modifierFlags: 0
        )
        XCTAssertFalse(ShortcutValidator.allows(configuration: config))
    }

    func testAllowsRejectsReservedDigitShortcut() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_1),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertFalse(ShortcutValidator.allows(configuration: config))
    }

    func testAllowsAcceptsNonReservedCombo() {
        let config = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_B),
            modifierFlags: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        XCTAssertTrue(ShortcutValidator.allows(configuration: config))
    }

    func testReservedInspectorRequiresOption() {
        // cmd+option+I is reserved
        XCTAssertTrue(ShortcutValidator.isReservedActionShortcut(
            modifiers: [.command, .option],
            keyCode: UInt16(kVK_ANSI_I)
        ))

        // cmd+I alone is not reserved
        XCTAssertFalse(ShortcutValidator.isReservedActionShortcut(
            modifiers: [.command],
            keyCode: UInt16(kVK_ANSI_I)
        ))
    }

    func testReservedKeypadDigitIsDetected() {
        XCTAssertTrue(ShortcutValidator.isReservedActionShortcut(
            modifiers: [.command],
            keyCode: UInt16(kVK_ANSI_Keypad5)
        ))
    }
}
