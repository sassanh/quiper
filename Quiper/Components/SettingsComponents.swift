import SwiftUI
import AppKit

extension Color {
    var settingsResolved: Color {
        if self == .red { return .red }
        return Settings.shared.settingsColorStyle == .classic ? .secondary : self
    }
}

public final class InteractionShieldView: NSView {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { self }
    public override func mouseDown(with event: NSEvent) {}
    public override func rightMouseDown(with event: NSEvent) {}
    public override func otherMouseDown(with event: NSEvent) {}
}

struct ColoredFrameGroupBoxStyle: GroupBoxStyle {
    var frameColor: Color
    var lineWidth: CGFloat = 1.0

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.headline)
            
            configuration.content
                .padding(.top, 4)
        }
        .padding()
        // 2. Apply the custom border (frame) and background
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(frameColor, lineWidth: lineWidth)
                .background(Color(NSColor.windowBackgroundColor).cornerRadius(8)) // Keeps standard background
        )
    }
}

struct SettingsSection<Content: View>: View {
    @ObservedObject private var settings = Settings.shared
    var title: String
    var titleColor: Color
    var cardBackground: Color
    var icon: String?
    var iconColor: Color
    var content: () -> Content
    
    init(
        title: String,
        titleColor: Color = .primary,
        cardBackground: Color = Color(NSColor.controlBackgroundColor),
        icon: String? = nil,
        iconColor: Color = .blue,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleColor = titleColor
        self.cardBackground = cardBackground
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }
    
    var body: some View {
        let isClassic = settings.settingsColorStyle == .classic && iconColor != .red
        let resolvedTitleColor = isClassic ? .primary : titleColor
        let resolvedCardBackground = isClassic ? (cardBackground == Color(NSColor.controlBackgroundColor) ? cardBackground : Color.secondary.opacity(0.05)) : cardBackground
        let resolvedIconColor = isClassic ? .secondary : iconColor

        GroupBox {
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .background(resolvedCardBackground)
        } label: {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(resolvedIconColor)
                        )
                }
                Text(title)
                    .font(.headline)
                    .foregroundColor(resolvedTitleColor)
            }
            .padding(.bottom, 4)
        }
        .groupBoxStyle(ColoredFrameGroupBoxStyle(frameColor: Color(NSColor.separatorColor)))
    }
}

struct SettingsRow<Content: View>: View {
    @ObservedObject private var settings = Settings.shared
    var title: String
    var message: String?
    var icon: String?
    var iconColor: Color?
    var content: () -> Content
    
    init(
        title: String,
        message: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }
    
    var body: some View {
        let resolvedIconColor = (settings.settingsColorStyle == .classic && iconColor != .red) ? Color.secondary : (iconColor ?? .secondary)
        HStack(alignment: .center, spacing: 16) {
            // Leading Icon / Placeholder
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(resolvedIconColor)
                } else {
                    Spacer()
                }
            }
            .frame(width: 20, height: 20, alignment: .center)
            
        // Text Column: Title + Description
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 150, maxWidth: 280, alignment: .leading)
        
        Spacer(minLength: 16)
                
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Bespoke Graphical Controls

struct PickerCardStyle: ViewModifier {
    @ObservedObject private var settings = Settings.shared
    let isSelected: Bool
    var accentColor: Color = .blue
    
    func body(content: Content) -> some View {
        let resolvedColor = settings.settingsColorStyle == .classic ? Color.secondary : accentColor
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? resolvedColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? resolvedColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func pickerCardStyle(isSelected: Bool, accentColor: Color = .blue) -> some View {
        self.modifier(PickerCardStyle(isSelected: isSelected, accentColor: accentColor))
    }
}


struct SettingsToggleRow: View {
    var title: String
    var message: String?
    var icon: String?
    var iconColor: Color?
    @Binding var isOn: Bool
    
    @ObservedObject private var settings = Settings.shared
    
    init(
        title: String,
        message: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self._isOn = isOn
    }
    
    var body: some View {
        let resolvedColor = (settings.settingsColorStyle == .classic && iconColor != .red) ? Color.secondary : (iconColor ?? .blue)
        SettingsRow(title: title, message: message, icon: icon, iconColor: resolvedColor) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(resolvedColor)
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
    var icon: String?
    var iconColor: Color?
    var lightContent: () -> LightContent
    var darkContent: () -> DarkContent
    private let controlColumnWidth: CGFloat = 150
    
    init(
        title: String,
        message: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        @ViewBuilder lightContent: @escaping () -> LightContent,
        @ViewBuilder darkContent: @escaping () -> DarkContent
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.lightContent = lightContent
        self.darkContent = darkContent
    }
    
    @ObservedObject private var settings = Settings.shared
    
    var body: some View {
        let resolvedColor = (settings.settingsColorStyle == .classic && iconColor != .red) ? Color.secondary : (iconColor ?? .blue)
        SettingsRow(title: title, message: message, icon: icon, iconColor: resolvedColor) {
            // Light column - fixed width for alignment
            VStack(alignment: .center, spacing: 4) {
                Text("Light")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                lightContent()
            }
            .frame(width: controlColumnWidth)
            .tint(resolvedColor)
            .accentColor(resolvedColor)
            
            // Dark column - fixed width for alignment
            VStack(alignment: .center, spacing: 4) {
                Text("Dark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                darkContent()
            }
            .frame(width: controlColumnWidth)
            .tint(resolvedColor)
            .accentColor(resolvedColor)
        }
    }
}

struct ColoredCheckboxToggleStyle: ToggleStyle {
    var accentColor: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? (configuration.isOn ? accentColor : .secondary) : .secondary.opacity(0.4))
                    .padding(.top, 1)
                
                configuration.label
                    .foregroundColor(isEnabled ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == ColoredCheckboxToggleStyle {
    static func coloredCheckbox(_ color: Color) -> ColoredCheckboxToggleStyle {
        ColoredCheckboxToggleStyle(accentColor: color)
    }
}
