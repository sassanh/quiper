import SwiftUI

struct ShortcutButton: View {
    var text: String
    var isPlaceholder: Bool = false
    var onTap: () -> Void
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    var width: CGFloat = 180
    var axIdentifier: String = "ShortcutRecorder" // Default

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: width, height: 30)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .frame(width: width - buttonSpacing, alignment: .center)

            if onClear != nil || onReset != nil {
                HStack(spacing: 4) {
                    Spacer()
                    
                    if let onClear {
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("xmark.circle.fill")
                    }
                    
                    if let onReset {
                        Button {
                            onReset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("arrow.counterclockwise.circle.fill")
                    }
                }
                .padding(.trailing, 6)
                .frame(width: width, height: 30, alignment: .trailing)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onTap()
        }
        .accessibilityElement(children: .contain)
        // .accessibilityAddTraits(.isButton) // Removed to expose children (Clear/Reset buttons)
        .accessibilityIdentifier(axIdentifier)
        .accessibilityValue(text)
    }
    
    private var buttonSpacing: CGFloat {
        var spacing: CGFloat = 0
        if onClear != nil { spacing += 20 }
        if onReset != nil { spacing += 20 }
        return spacing
    }
}

struct LabeledShortcutButton: View {
    var label: String
    var text: String
    var isPlaceholder: Bool
    var onTap: () -> Void
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    var axIdentifier: String? // Optional override

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            ShortcutButton(
                text: text,
                isPlaceholder: isPlaceholder,
                onTap: onTap,
                onClear: onClear,
                onReset: onReset,
                width: 180,
                axIdentifier: axIdentifier ?? "ShortcutRecorder"
            )
        }
    }
}
