import Foundation

/// Fixed session-slot model shared by the macOS and iOS engines.
///
/// Every engine owns exactly 10 session slots, rendered as 1-10 with slot 9
/// displayed as "0" (matching the macOS selector). Slots are created on
/// selection and closed individually; there is no "add" button.
enum SessionSlots {
    static let count = 10
    static let range = 0..<count

    /// Display label for a slot index: 0-8 map to "1"-"9", slot 9 maps to "0".
    static func label(for slot: Int) -> String {
        "\(slot == count - 1 ? 0 : slot + 1)"
    }

    /// Fallback tooltip / accessibility title for a slot.
    static func tooltipTitle(for slot: Int) -> String {
        "Session \(slot == count - 1 ? 0 : slot + 1)"
    }
}
