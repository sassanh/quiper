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
