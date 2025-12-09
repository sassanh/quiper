import AppKit
import Carbon

enum ShortcutFormatter {
    static func string(for configuration: HotkeyManager.Configuration) -> String {
        if configuration.isDisabled {
            return "Disabled"
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags)
        return string(for: modifiers, keyCode: UInt16(configuration.keyCode), characters: nil)
    }

    static func string(for modifiers: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> String {
        var components: [String] = []
        let modifierString = modifierSymbols(modifiers)
        if !modifierString.isEmpty {
            components.append(modifierString.trimmingCharacters(in: .whitespaces))
        }
        components.append(keyName(for: keyCode, fallback: characters))
        return components.joined(separator: " ")
    }

    private static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var string = ""
        if modifiers.contains(.control) { string += "⌃ " }
        if modifiers.contains(.option) { string += "⌥ " }
        if modifiers.contains(.shift) { string += "⇧ " }
        if modifiers.contains(.command) { string += "⌘ " }
        return string
    }

    private static func keyName(for keyCode: UInt16, fallback: String?) -> String {
        if let fallback, let scalar = fallback.uppercased().first, scalar.isLetter || scalar.isNumber {
            return String(scalar)
        }
        if let mapped = keyCodeToCharacter[keyCode] {
            return mapped
        }
        return "Key \(keyCode)"
    }

    private static let keyCodeToCharacter: [UInt16: String] = {
        var keys: [UInt16: String] = [:]
        keys[UInt16(kVK_Space)] = "Space"
        keys[UInt16(kVK_Return)] = "󰌑"
        keys[UInt16(kVK_Escape)] = "⎋"
        keys[UInt16(kVK_Delete)] = "Delete"
        keys[UInt16(kVK_Tab)] = "Tab"
        keys[UInt16(kVK_ANSI_KeypadEnter)] = "Enter"
        keys[UInt16(kVK_UpArrow)] = "↑"
        keys[UInt16(kVK_DownArrow)] = "↓"
        keys[UInt16(kVK_LeftArrow)] = "←"
        keys[UInt16(kVK_RightArrow)] = "→"
        keys[UInt16(kVK_Home)] = "Home"
        keys[UInt16(kVK_End)] = "End"
        keys[UInt16(kVK_PageUp)] = "Page Up"
        keys[UInt16(kVK_PageDown)] = "Page Down"
        keys[UInt16(kVK_F1)] = "F1"
        keys[UInt16(kVK_F2)] = "F2"
        keys[UInt16(kVK_F3)] = "F3"
        keys[UInt16(kVK_F4)] = "F4"
        keys[UInt16(kVK_F5)] = "F5"
        keys[UInt16(kVK_F6)] = "F6"
        keys[UInt16(kVK_F7)] = "F7"
        keys[UInt16(kVK_F8)] = "F8"
        keys[UInt16(kVK_F9)] = "F9"
        keys[UInt16(kVK_F10)] = "F10"
        keys[UInt16(kVK_F11)] = "F11"
        keys[UInt16(kVK_F12)] = "F12"
        keys[UInt16(kVK_F13)] = "F13"
        keys[UInt16(kVK_F14)] = "F14"
        keys[UInt16(kVK_F15)] = "F15"
        keys[UInt16(kVK_F16)] = "F16"
        keys[UInt16(kVK_F17)] = "F17"
        keys[UInt16(kVK_F18)] = "F18"
        keys[UInt16(kVK_F19)] = "F19"
        keys[UInt16(kVK_F20)] = "F20"
        keys[UInt16(kVK_ANSI_Comma)] = ","
        keys[UInt16(kVK_ANSI_Period)] = "."
        keys[UInt16(kVK_ANSI_Slash)] = "/"
        keys[UInt16(kVK_ANSI_Semicolon)] = ";"
        keys[UInt16(kVK_ANSI_Quote)] = "'"
        keys[UInt16(kVK_ANSI_LeftBracket)] = "["
        keys[UInt16(kVK_ANSI_RightBracket)] = "]"
        keys[UInt16(kVK_ANSI_Backslash)] = "\\"
        keys[UInt16(kVK_ANSI_Minus)] = "-"
        keys[UInt16(kVK_ANSI_Equal)] = "="
        keys[UInt16(kVK_ANSI_Grave)] = "`"
        keys[UInt16(kVK_ANSI_KeypadDecimal)] = "."
        keys[UInt16(kVK_ANSI_KeypadMultiply)] = "*"
        keys[UInt16(kVK_ANSI_KeypadPlus)] = "+"
        keys[UInt16(kVK_ANSI_KeypadClear)] = "Clear"
        keys[UInt16(kVK_ANSI_KeypadDivide)] = "/"
        keys[UInt16(kVK_ANSI_KeypadMinus)] = "-"
        keys[UInt16(kVK_ANSI_KeypadEquals)] = "="
        keys[UInt16(kVK_ANSI_Keypad0)] = "0"
        keys[UInt16(kVK_ANSI_Keypad1)] = "1"
        keys[UInt16(kVK_ANSI_Keypad2)] = "2"
        keys[UInt16(kVK_ANSI_Keypad3)] = "3"
        keys[UInt16(kVK_ANSI_Keypad4)] = "4"
        keys[UInt16(kVK_ANSI_Keypad5)] = "5"
        keys[UInt16(kVK_ANSI_Keypad6)] = "6"
        keys[UInt16(kVK_ANSI_Keypad7)] = "7"
        keys[UInt16(kVK_ANSI_Keypad8)] = "8"
        keys[UInt16(kVK_ANSI_Keypad9)] = "9"
        keys[UInt16(kVK_ANSI_A)] = "A"
        keys[UInt16(kVK_ANSI_B)] = "B"
        keys[UInt16(kVK_ANSI_C)] = "C"
        keys[UInt16(kVK_ANSI_D)] = "D"
        keys[UInt16(kVK_ANSI_E)] = "E"
        keys[UInt16(kVK_ANSI_F)] = "F"
        keys[UInt16(kVK_ANSI_G)] = "G"
        keys[UInt16(kVK_ANSI_H)] = "H"
        keys[UInt16(kVK_ANSI_I)] = "I"
        keys[UInt16(kVK_ANSI_J)] = "J"
        keys[UInt16(kVK_ANSI_K)] = "K"
        keys[UInt16(kVK_ANSI_L)] = "L"
        keys[UInt16(kVK_ANSI_M)] = "M"
        keys[UInt16(kVK_ANSI_N)] = "N"
        keys[UInt16(kVK_ANSI_O)] = "O"
        keys[UInt16(kVK_ANSI_P)] = "P"
        keys[UInt16(kVK_ANSI_Q)] = "Q"
        keys[UInt16(kVK_ANSI_R)] = "R"
        keys[UInt16(kVK_ANSI_S)] = "S"
        keys[UInt16(kVK_ANSI_T)] = "T"
        keys[UInt16(kVK_ANSI_U)] = "U"
        keys[UInt16(kVK_ANSI_V)] = "V"
        keys[UInt16(kVK_ANSI_W)] = "W"
        keys[UInt16(kVK_ANSI_X)] = "X"
        keys[UInt16(kVK_ANSI_Y)] = "Y"
        keys[UInt16(kVK_ANSI_Z)] = "Z"
        keys[UInt16(kVK_ANSI_0)] = "0"
        keys[UInt16(kVK_ANSI_1)] = "1"
        keys[UInt16(kVK_ANSI_2)] = "2"
        keys[UInt16(kVK_ANSI_3)] = "3"
        keys[UInt16(kVK_ANSI_4)] = "4"
        keys[UInt16(kVK_ANSI_5)] = "5"
        keys[UInt16(kVK_ANSI_6)] = "6"
        keys[UInt16(kVK_ANSI_7)] = "7"
        keys[UInt16(kVK_ANSI_8)] = "8"
        keys[UInt16(kVK_ANSI_9)] = "9"
        return keys
    }()
}
