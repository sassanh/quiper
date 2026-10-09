#if os(macOS)
import AppKit

/// The payload of a keyboard shortcut — the key with its modifiers — as it
/// travels through settings. The listener machinery that registers it with
/// macOS lives in the app's `HotkeyManager`, which exposes this type under
/// its historical name `HotkeyManager.Configuration`.
struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt

    var cocoaFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var isDisabled: Bool {
        keyCode == 0 && modifierFlags == 0
    }

    init(keyCode: UInt32, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? 0
        modifierFlags = try container.decodeIfPresent(UInt.self, forKey: .modifierFlags) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifierFlags
    }
}
#endif
