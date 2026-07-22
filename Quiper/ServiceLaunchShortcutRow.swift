import SwiftUI

struct ServiceLaunchShortcutRow: View {
    var title: String
    var shortcut: HotkeyManager.Configuration?
    var globalDigitShortcut: HotkeyManager.Configuration?
    var statusMessage: String
    var onTap: () -> Void
    var onClear: () -> Void
    var axIdentifier: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 8) {
                    ShortcutButton(
                        text: shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                        isPlaceholder: shortcut == nil,
                        onTap: onTap,
                        onClear: shortcut != nil ? onClear : nil,
                        onReset: nil,
                        width: globalDigitShortcut == nil ? 200 : 160,
                        axIdentifier: axIdentifier
                    )
                    if let globalDigitShortcut {
                        ShortcutButton(
                            text: ShortcutFormatter.string(for: globalDigitShortcut),
                            onTap: {},
                            onClear: nil,
                            onReset: nil,
                            width: 160,
                            axIdentifier: "global_\(axIdentifier)"
                        )
                        .disabled(true)
                        .help("Global Go to engine shortcut")
                    }
                }
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
