import XCTest
import Carbon
@testable import Quiper

@MainActor
final class AppShortcutBindingsTests: XCTestCase {
    func testDefaultConfigurationsExposeExpectedKeyCodes() {
        let bindings = AppShortcutBindings.defaults

        XCTAssertEqual(bindings.configuration(for: .nextSession).keyCode, UInt32(kVK_RightArrow))
        XCTAssertEqual(bindings.configuration(for: .previousService).modifierFlags, NSEvent.ModifierFlags([.command, .control]).rawValue)
        XCTAssertEqual(bindings.alternateConfiguration(for: .nextSession)?.keyCode, UInt32(kVK_ANSI_L))
    }

    func testAlternateConfigurationsCanBeCleared() {
        var bindings = AppShortcutBindings.defaults
        bindings.setAlternateConfiguration(nil, for: .nextSession)

        XCTAssertNil(bindings.alternateConfiguration(for: .nextSession))
    }

    func testSettingConfigurationOverridesExisting() {
        var bindings = AppShortcutBindings.defaults
        let replacement = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )

        bindings.setConfiguration(replacement, for: .previousService)

        XCTAssertEqual(bindings.configuration(for: .previousService), replacement)
        XCTAssertEqual(bindings.defaultConfiguration(for: .previousService), AppShortcutBindings.defaults.previousService)
    }
}
