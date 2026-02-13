import SwiftUI
import AppKit

public final class InteractionShieldView: NSView {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { self }
    public override func mouseDown(with event: NSEvent) {}
    public override func rightMouseDown(with event: NSEvent) {}
    public override func otherMouseDown(with event: NSEvent) {}
}

struct SettingsSection<Content: View>: View {
    var title: String
    var titleColor: Color
    var cardBackground: Color
    var content: () -> Content
    
    init(title: String, titleColor: Color = .primary, cardBackground: Color = Color(NSColor.controlBackgroundColor), @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.titleColor = titleColor
        self.cardBackground = cardBackground
        self.content = content
    }
    
    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .background(cardBackground)
        } label: {
            Text(title)
                .font(.headline)
                .foregroundColor(titleColor)
        }
        .groupBoxStyle(DefaultGroupBoxStyle())
    }
}

struct SettingsRow<Content: View>: View {
    var title: String
    var message: String?
    var content: () -> Content
    private let labelWidth: CGFloat = 230
    
    init(title: String, message: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.message = message
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .fontWeight(.semibold)
                    .frame(width: labelWidth, alignment: .leading)
                
                Spacer(minLength: 16)
                
                content()
            }
            
            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}

struct SettingsToggleRow: View {
    var title: String
    var message: String?
    @Binding var isOn: Bool
    
    init(title: String, message: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.message = message
        self._isOn = isOn
    }
    
    var body: some View {
        SettingsRow(title: title, message: message) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

/// A 3-column settings row with Light and Dark controls side by side.
/// Follows the same pattern as AppShortcutRow with Primary/Alternate.
struct DualThemeRow<LightContent: View, DarkContent: View>: View {
    var title: String
    var message: String?
    var lightContent: () -> LightContent
    var darkContent: () -> DarkContent
    private let labelWidth: CGFloat = 230
    private let controlColumnWidth: CGFloat = 150
    
    init(
        title: String,
        message: String? = nil,
        @ViewBuilder lightContent: @escaping () -> LightContent,
        @ViewBuilder darkContent: @escaping () -> DarkContent
    ) {
        self.title = title
        self.message = message
        self.lightContent = lightContent
        self.darkContent = darkContent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                }
                .frame(width: labelWidth, alignment: .leading)
                
                Spacer(minLength: 8)
                
                // Light column - fixed width for alignment
                VStack(alignment: .center, spacing: 4) {
                    Text("Light")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    lightContent()
                }
                .frame(width: controlColumnWidth)
                
                // Dark column - fixed width for alignment
                VStack(alignment: .center, spacing: 4) {
                    Text("Dark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    darkContent()
                }
                .frame(width: controlColumnWidth)
            }
            
            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}
