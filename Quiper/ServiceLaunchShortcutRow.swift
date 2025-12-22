import SwiftUI

struct ServiceLaunchShortcutRow: View {
    var title: String
    var shortcut: HotkeyManager.Configuration?
    var statusMessage: String
    var onTap: () -> Void
    var onClear: () -> Void
    var axIdentifier: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                ShortcutButton(
                    text: shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                    isPlaceholder: shortcut == nil,
                    onTap: onTap,
                    onClear: shortcut != nil ? onClear : nil,
                    onReset: nil,
                    width: 200,
                    axIdentifier: axIdentifier
                )
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
