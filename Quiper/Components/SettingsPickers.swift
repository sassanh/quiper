import SwiftUI
import AppKit

// MARK: - Bespoke Graphical Controls

// 0. Dock Visibility
struct DockVisibilityPicker: View {
    @Binding var selection: DockVisibility
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Never (Menu bar app)
            Button(action: { selection = .never }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Screen outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(width: 44, height: 36)

                        // Menu bar
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .offset(y: -14)

                        // Center window (no dock)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                            .frame(width: 20, height: 12)
                            .offset(y: -2)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .never, accentColor: .teal)

                    Text(DockVisibility.never.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .never ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // When Visible
            Button(action: { selection = .whenVisible }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Screen outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(width: 44, height: 36)

                        // Menu bar
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .offset(y: -14)

                        // Center window
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                            .frame(width: 20, height: 12)
                            .offset(y: -2)

                        // Dock
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.teal.settingsResolved.opacity(0.6))
                            .frame(width: 20, height: 4)
                            .offset(y: 13)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .whenVisible, accentColor: .teal)

                    Text(DockVisibility.whenVisible.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .whenVisible ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Always
            Button(action: { selection = .always }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Screen outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(width: 44, height: 36)

                        // Menu bar
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .offset(y: -14)

                        // Dock (prominent)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.teal.settingsResolved.opacity(0.8))
                            .frame(width: 20, height: 4)
                            .offset(y: 13)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .always, accentColor: .teal)

                    Text(DockVisibility.always.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .always ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

// 1. Toolbar Visibility
struct ToolbarVisibilityPicker: View {
    @Binding var selection: TopBarVisibility
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Visible option
            Button(action: { selection = .visible }) {
                VStack(spacing: 8) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(height: 36)

                        // Toolbar strip
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.settingsResolved.opacity(0.6))
                            .frame(height: 10)
                            .padding(.top, 1)
                            .padding(.horizontal, 1)
                            .clipShape(Rectangle().offset(y: -2)) // keep top rounded
                    }
                    .frame(width: 56)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .visible, accentColor: .blue)

                    Text(TopBarVisibility.visible.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .visible ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Hidden option
            Button(action: { selection = .hidden }) {
                VStack(spacing: 8) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(height: 36)
                    }
                    .frame(width: 56)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .hidden, accentColor: .blue)

                    Text(TopBarVisibility.hidden.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .hidden ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

// 2. Toolbar Position
struct DragAreaPositionPicker: View {
    @Binding var selection: DragAreaPosition
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Top option
            Button(action: { selection = .top }) {
                VStack(spacing: 8) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(height: 36)

                        // Toolbar strip at top
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.settingsResolved.opacity(0.6))
                            .frame(height: 10)
                            .padding(.top, 1)
                            .padding(.horizontal, 1)
                            .clipShape(Rectangle().offset(y: -2)) // keep top rounded
                    }
                    .frame(width: 56)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .top, accentColor: .blue)

                    Text(DragAreaPosition.top.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .top ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Bottom option
            Button(action: { selection = .bottom }) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                            .frame(height: 36)

                        // Toolbar strip at bottom
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.settingsResolved.opacity(0.6))
                            .frame(height: 10)
                            .padding(.bottom, 1)
                            .padding(.horizontal, 1)
                            .clipShape(Rectangle().offset(y: 2)) // keep bottom rounded
                    }
                    .frame(width: 56)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .bottom, accentColor: .blue)

                    Text(DragAreaPosition.bottom.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .bottom ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

// 3. Selector Display
struct SelectorDisplayPicker: View {
    @Binding var selection: SelectorDisplayMode
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Expanded
            Button(action: { selection = .expanded }) {
                VStack(spacing: 8) {
                    ZStack {
                        // The outline segmented control container
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 40, height: 14)

                        HStack(spacing: 0) {
                            // Selected segment
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.purple.settingsResolved.opacity(0.6))
                                .frame(width: 12, height: 12)

                            Rectangle()
                                .fill(Color(NSColor.separatorColor))
                                .frame(width: 1, height: 8)

                            Color.clear
                                .frame(width: 12, height: 12)

                            Rectangle()
                                .fill(Color(NSColor.separatorColor))
                                .frame(width: 1, height: 8)

                            Color.clear
                                .frame(width: 12, height: 12)
                        }
                        .frame(width: 40, height: 14)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .expanded, accentColor: .purple)

                    Text(SelectorDisplayMode.expanded.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .expanded ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Compact
            Button(action: { selection = .compact }) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.settingsResolved.opacity(0.6)))
                            .frame(width: 18, height: 14)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .compact, accentColor: .purple)

                    Text(SelectorDisplayMode.compact.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .compact ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Auto
            Button(action: { selection = .auto }) {
                VStack(spacing: 8) {
                    HStack(spacing: 3) {
                        // Small Expanded control
                        ZStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                .frame(width: 20, height: 10)
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Color.purple.settingsResolved.opacity(0.6))
                                    .frame(width: 6, height: 8)
                                Rectangle()
                                    .fill(Color(NSColor.separatorColor))
                                    .frame(width: 1, height: 6)
                                Color.clear
                                    .frame(width: 5, height: 8)
                                Rectangle()
                                    .fill(Color(NSColor.separatorColor))
                                    .frame(width: 1, height: 6)
                                Color.clear
                                    .frame(width: 5, height: 8)
                            }
                            .frame(width: 20, height: 10)
                        }

                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.8))

                        // Small Compact control
                        ZStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color.purple.settingsResolved.opacity(0.6)))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .auto, accentColor: .purple)

                    Text(SelectorDisplayMode.auto.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .auto ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

// 4. Color Scheme
struct ColorSchemePicker: View {
    @Binding var selection: AppColorScheme
    var accentColor: Color = .orange
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let resolvedColor = settings.settingsColorStyle == .classic ? Color.secondary : accentColor
        HStack(spacing: 16) {
            // System
            Button(action: { selection = .system }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        // half accentColor
                        Path { path in
                            path.addArc(center: CGPoint(x: 12, y: 12), radius: 12, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
                        }
                        .fill(resolvedColor)
                    }
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .padding(4)
                    .overlay(
                        Circle().stroke(selection == .system ? resolvedColor : Color.clear, lineWidth: 2)
                    )

                    Text(AppColorScheme.system.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .system ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Light
            Button(action: { selection = .light }) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding(4)
                        .overlay(
                            Circle().stroke(selection == .light ? resolvedColor : Color.clear, lineWidth: 2)
                        )

                    Text(AppColorScheme.light.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .light ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Dark
            Button(action: { selection = .dark }) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(resolvedColor)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding(4)
                        .overlay(
                            Circle().stroke(selection == .dark ? resolvedColor : Color.clear, lineWidth: 2)
                        )

                    Text(AppColorScheme.dark.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .dark ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

// 5. Settings Style
struct SettingsStylePicker: View {
    @Binding var selection: SettingsColorStyle
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Colorful
            Button(action: { selection = .colorful }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Card container
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor)))
                            .frame(width: 44, height: 36)

                        // Mini rows with colors (static, always colorful)
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.purple)
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                        }
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .colorful, accentColor: .blue)

                    Text("Colorful")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .colorful ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Classic
            Button(action: { selection = .classic }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Card container
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor)))
                            .frame(width: 44, height: 36)

                        // Mini rows with monochrome gray (static, always classic)
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.gray.opacity(0.8))
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.gray.opacity(0.8))
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.gray.opacity(0.8))
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 20, height: 3)
                            }
                        }
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .classic, accentColor: .secondary)

                    Text("Classic")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .classic ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

struct TabSurvivalPolicyPicker: View {
    @Binding var selection: TabSurvivalPolicy
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Always
            Button(action: { selection = .always }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Window outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Active tabs (filled color boxes)
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange.settingsResolved.opacity(0.8))
                                .frame(width: 8, height: 6)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange.settingsResolved.opacity(0.5))
                                .frame(width: 8, height: 6)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange.settingsResolved.opacity(0.5))
                                .frame(width: 8, height: 6)
                        }
                        .offset(y: -8)

                        // circular reload/restore arrow
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.orange.settingsResolved)
                            .offset(y: 6)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .always, accentColor: .orange)

                    Text("Always")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .always ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Ask on Exit
            Button(action: { selection = .askOnExit }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Window outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Active tabs (filled color boxes)
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange.settingsResolved.opacity(0.8))
                                .frame(width: 8, height: 6)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange.settingsResolved.opacity(0.5))
                                .frame(width: 8, height: 6)
                        }
                        .offset(y: -8)

                        // Question mark alert bubble/box
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.orange.settingsResolved.opacity(0.7))
                                .frame(width: 14, height: 12)
                            Text("?")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(y: 6)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .askOnExit, accentColor: .orange)

                    Text("Ask on Exit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .askOnExit ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Never
            Button(action: { selection = .never }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Window outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // No active tabs / empty outline tabs
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                .frame(width: 8, height: 6)
                            RoundedRectangle(cornerRadius: 1)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                .frame(width: 8, height: 6)
                        }
                        .offset(y: -8)

                        // Slash / X / empty trash icon
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray.opacity(0.8))
                            .offset(y: 6)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: selection == .never, accentColor: .orange)

                    Text("Never")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == .never ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

struct SessionSwitchingPicker: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // Auto-Switch Engine
            Button(action: {
                settings.automaticallySwitchEngineOnLastSessionClose.toggle()
                settings.saveSettings()
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Screen outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Engine 1 (Left) - representing closed engine
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            .frame(width: 10, height: 10)
                            .offset(x: -12)

                        // X mark inside Engine 1 to show it has no sessions / closed
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(x: -12)

                        // Arrow pointing right
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(settings.automaticallySwitchEngineOnLastSessionClose ? Color.blue.settingsResolved : .gray.opacity(0.4))

                        // Engine 2 (Right) - representing target engine
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(settings.automaticallySwitchEngineOnLastSessionClose ? Color.blue.settingsResolved.opacity(0.2) : Color.clear)
                            .stroke(settings.automaticallySwitchEngineOnLastSessionClose ? Color.blue.settingsResolved : Color.gray.opacity(0.4), lineWidth: 1)
                            .frame(width: 10, height: 10)
                            .offset(x: 12)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: settings.automaticallySwitchEngineOnLastSessionClose, accentColor: .blue)

                    Text("Auto-Switch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settings.automaticallySwitchEngineOnLastSessionClose ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // Auto-Create Session
            Button(action: {
                settings.autoCreateSessionOnEmptyEngineActivation.toggle()
                settings.saveSettings()
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Screen outline
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Tab strip on top with a tab + plus
                        ZStack {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(settings.autoCreateSessionOnEmptyEngineActivation ? Color.blue.settingsResolved.opacity(0.2) : Color.clear)
                                .stroke(settings.autoCreateSessionOnEmptyEngineActivation ? Color.blue.settingsResolved : Color.gray.opacity(0.4), lineWidth: 1)
                                .frame(width: 18, height: 8)

                            Image(systemName: "plus")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(settings.autoCreateSessionOnEmptyEngineActivation ? Color.blue.settingsResolved : .gray.opacity(0.6))
                        }
                        .offset(y: -8)

                        // Browser content area
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .frame(width: 28, height: 14)
                            .offset(y: 6)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: settings.autoCreateSessionOnEmptyEngineActivation, accentColor: .blue)

                    Text("Auto-Create")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settings.autoCreateSessionOnEmptyEngineActivation ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

struct PromptHistoryTriggerPicker: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            // 1. On Submit Card
            Button(action: {
                settings.promptHistoryRecordOnSubmit.toggle()
                settings.saveSettings()
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        // Card container outline (handled by pickerCardStyle)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Input field line
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 28, height: 4)
                            .offset(y: -8)

                        // Paperplane sending
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(settings.promptHistoryRecordOnSubmit ? Color.blue.settingsResolved : .gray.opacity(0.4))
                            .offset(y: 4)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: settings.promptHistoryRecordOnSubmit, accentColor: .blue)

                    Text("On Submit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settings.promptHistoryRecordOnSubmit ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // 2. Cmd + Backspace Card
            Button(action: {
                settings.promptHistoryRecordOnCmdBackspace.toggle()
                settings.saveSettings()
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Command symbol & Delete icon
                        HStack(spacing: 3) {
                            Text("⌘")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(settings.promptHistoryRecordOnCmdBackspace ? Color.blue.settingsResolved : .gray.opacity(0.4))
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(settings.promptHistoryRecordOnCmdBackspace ? Color.blue.settingsResolved : .gray.opacity(0.4))
                        }
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: settings.promptHistoryRecordOnCmdBackspace, accentColor: .blue)

                    Text("Cmd+⌫")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settings.promptHistoryRecordOnCmdBackspace ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            // 3. Selection Clear Card
            Button(action: {
                settings.promptHistoryRecordOnSelectionClear.toggle()
                settings.saveSettings()
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            .frame(width: 44, height: 36)

                        // Selected text representation
                        RoundedRectangle(cornerRadius: 1)
                            .fill(settings.promptHistoryRecordOnSelectionClear ? Color.blue.settingsResolved.opacity(0.3) : Color.gray.opacity(0.2))
                            .frame(width: 26, height: 10)
                            .offset(y: -6)

                        // Scissors / Cut icon
                        Image(systemName: "scissors")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(settings.promptHistoryRecordOnSelectionClear ? Color.blue.settingsResolved : .gray.opacity(0.4))
                            .offset(y: 6)
                    }
                    .frame(width: 44, height: 36)
                    .padding(8)
                    .pickerCardStyle(isSelected: settings.promptHistoryRecordOnSelectionClear, accentColor: .blue)

                    Text("Clear / Overwrite")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settings.promptHistoryRecordOnSelectionClear ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .trailing)
    }
}

struct PromptHistoryLimitPicker: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Stepper(value: Binding(
            get: { settings.promptHistoryLimit },
            set: { settings.promptHistoryLimit = Settings.clampedPromptHistoryLimit($0) }
        ), in: Settings.promptHistoryLimitRange) {
            Text("\(settings.promptHistoryLimit)")
                .font(.body.monospacedDigit())
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(width: 260, alignment: .trailing)
    }
}
