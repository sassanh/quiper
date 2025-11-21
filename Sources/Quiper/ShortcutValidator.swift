import AppKit
import Carbon

enum ShortcutValidator {
    static func allows(configuration: HotkeyManager.Configuration) -> Bool {
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags)
        let primary = modifiers.intersection([.command, .option, .control, .shift])
        guard !primary.isEmpty else { return false }
        return !isReservedActionShortcut(modifiers: primary, keyCode: UInt16(configuration.keyCode))
    }

    static func isReservedActionShortcut(modifiers rawModifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        let modifiers = rawModifiers.intersection([.command, .option, .control, .shift])
        guard modifiers.contains(.command) else { return false }

        if isDigitKey(keyCode) {
            return true
        }
        if keyCode == UInt16(kVK_ANSI_Comma) { // Settings
            return true
        }
        if keyCode == UInt16(kVK_ANSI_I) && modifiers.contains(.option) { // Inspector
            return true
        }
        if keyCode == UInt16(kVK_ANSI_Slash) && modifiers.contains(.shift) { // Shortcut help
            return true
        }
        if keyCode == UInt16(kVK_ANSI_M) && modifiers.contains(.option) { // minimize overlay e.g.
            return true
        }
        if keyCode == UInt16(kVK_ANSI_Q) && modifiers.contains(.control) { // quit
            return true
        }
        if keyCode == UInt16(kVK_ANSI_Equal) || keyCode == UInt16(kVK_ANSI_KeypadPlus) { // Zoom in
            return true
        }
        if keyCode == UInt16(kVK_ANSI_Minus) || keyCode == UInt16(kVK_ANSI_KeypadMinus) { // Zoom out
            return true
        }
        return false
    }

    private static func isDigitKey(_ keyCode: UInt16) -> Bool {
        return topRowDigits.contains(keyCode) || keypadDigits.contains(keyCode)
    }

    private static let topRowDigits: Set<UInt16> = [
        UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
    ]

    private static let keypadDigits: Set<UInt16> = [
        UInt16(kVK_ANSI_Keypad0), UInt16(kVK_ANSI_Keypad1), UInt16(kVK_ANSI_Keypad2), UInt16(kVK_ANSI_Keypad3),
        UInt16(kVK_ANSI_Keypad4), UInt16(kVK_ANSI_Keypad5), UInt16(kVK_ANSI_Keypad6), UInt16(kVK_ANSI_Keypad7),
        UInt16(kVK_ANSI_Keypad8), UInt16(kVK_ANSI_Keypad9)
    ]
}
