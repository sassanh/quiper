import SwiftUI

struct ServiceLaunchShortcutRow: View {
    var title: String
    var shortcut: HotkeyManager.Configuration?
    var onTap: () -> Void
    var onClear: () -> Void
    var axIdentifier: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            ShortcutButton(
                text: shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                isPlaceholder: shortcut == nil,
                onTap: onTap,
                onClear: shortcut != nil ? onClear : nil,
                onReset: nil,
                width: 160,
                axIdentifier: axIdentifier
            )
        }
    }
}
