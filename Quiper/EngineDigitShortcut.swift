import AppKit
import Carbon

enum EngineDigitShortcut {
    static let maximumEngineCount = 10

    static func configuration(
        forEngineAt index: Int,
        modifiers rawModifiers: UInt
    ) -> HotkeyManager.Configuration? {
        guard (0..<maximumEngineCount).contains(index) else { return nil }

        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else { return nil }

        let keyCodes: [Int] = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0
        ]
        return HotkeyManager.Configuration(
            keyCode: UInt32(keyCodes[index]),
            modifierFlags: modifiers.rawValue
        )
    }
}
