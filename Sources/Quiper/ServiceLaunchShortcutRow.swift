import SwiftUI

struct ServiceLaunchShortcutRow: View {
    var shortcut: HotkeyManager.Configuration?
    var statusMessage: String
    var onTap: () -> Void
    var onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch Shortcut")
                .font(.headline)
            Text("Sets a global keybinding that opens Quiper directly to this engine.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                ShortcutButton(
                    text: shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                    isPlaceholder: shortcut == nil,
                    onTap: onTap,
                    onClear: shortcut != nil ? onClear : nil,
                    onReset: nil,
                    width: 200
                )
                Spacer()
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
