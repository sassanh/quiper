import XCTest
import Carbon
@testable import Quiper

@MainActor
final class ShortcutFormatterTests: XCTestCase {
    func testFormatsCommandShiftLetter() {
        let modifiers = NSEvent.ModifierFlags([.command, .shift])
        let string = ShortcutFormatter.string(for: modifiers, keyCode: UInt16(kVK_ANSI_A), characters: "a")

        XCTAssertEqual(string, "⇧ ⌘ A")
    }

    func testFormatsArrowKeyWithoutModifiers() {
        let string = ShortcutFormatter.string(for: [], keyCode: UInt16(kVK_UpArrow), characters: nil)

        XCTAssertEqual(string, "↑")
    }

    func testUsesFallbackCharactersWhenUnknownKeycode() {
        let string = ShortcutFormatter.string(for: [.option], keyCode: 255, characters: "g")

        XCTAssertEqual(string, "⌥ G")
    }

    func testMapsReturnKeyToGlyph() {
        let string = ShortcutFormatter.string(for: [.command], keyCode: UInt16(kVK_Return), characters: nil)

        XCTAssertEqual(string, "⌘ 󰌑")
    }
}
