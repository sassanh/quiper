import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    // Local state for color/opacity to avoid SwiftUI publishing conflicts - separate for each theme
    @State private var localLightColor: Color = Color(red: 0.95, green: 0.95, blue: 0.95, opacity: 0.85)
    @State private var localLightBlurRadius: Double = 1.0
    @State private var localDarkColor: Color = Color(red: 0.26, green: 0.21, blue: 0.25, opacity: 0.51)
    @State private var localDarkBlurRadius: Double = 1.0
    
    @State private var localLightOutlineColor: Color = Color(red: 0.0, green: 0.0, blue: 0.0)
    @State private var localDarkOutlineColor: Color = Color(red: 1.0, green: 1.0, blue: 1.0)
    @State private var localLightOutlineWidth: Double = 1.0
    @State private var localDarkOutlineWidth: Double = 1.0
    
    private let labelWidth: CGFloat = 230
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection(title: "Dock") {
                    SettingsRow(
                        title: "Dock Icon Visibility",
                        message: "Controls when the app appears in the Dock. Note: Native menus are only available when the Dock icon is visible."
                    ) {
                        Picker("", selection: $settings.dockVisibility) {
                            ForEach(DockVisibility.allCases) { visibility in
                                Text(visibility.rawValue).tag(visibility)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                    .onChange(of: settings.dockVisibility) { _, newValue in
                        settings.saveSettings()
                        
                        // Apply activation policy immediately
                        switch newValue {
                        case .never:
                            NSApp.setActivationPolicy(.accessory)
                        case .whenVisible:
                            // Only set to .regular if window or settings are visible
                            if NSApp.windows.contains(where: { $0.isVisible && $0.identifier != nil }) {
                                NSApp.setActivationPolicy(.regular)
                            } else {
                                NSApp.setActivationPolicy(.accessory)
                            }
                        case .always:
                            NSApp.setActivationPolicy(.regular)
                        }
                    }
                }
                SettingsSection(title: "Top Bar") {
                    SettingsRow(
                        title: "Header Visibility",
                        message: "Controls whether the top header is always visible or only shown when needed."
                    ) {
                        Picker("", selection: $settings.topBarVisibility) {
                            ForEach(TopBarVisibility.allCases) { visibility in
                                Text(visibility.rawValue).tag(visibility)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    .onChange(of: settings.topBarVisibility) { _, _ in
                        settings.saveSettings()
                    }
                    
                    SettingsDivider()
                    SettingsRow(
                        title: "Drag Area Position",
                        message: "Controls whether the window drag area is at the top or bottom edge."
                    ) {
                        Picker("", selection: $settings.dragAreaPosition) {
                            ForEach(DragAreaPosition.allCases) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    .onChange(of: settings.dragAreaPosition) { _, _ in
                        settings.saveSettings()
                    }
                    
                    if settings.topBarVisibility == .hidden {
                        SettingsDivider()
                        SettingsRow(
                            title: "Show on Modifier Keys",
                            message: "Show the hidden bar while holding tab/engine shortcut modifiers."
                        ) {
                            Toggle("", isOn: $settings.showHiddenBarOnModifiers)
                                .toggleStyle(.switch)
                                .onChange(of: settings.showHiddenBarOnModifiers) { _, _ in
                                    settings.saveSettings()
                                }
                        }
                    }
                }
                
                SettingsSection(title: "Selectors") {
                    SettingsRow(
                        title: "Selector Display",
                        message: "Controls how engine and session selectors appear. Auto switches based on window width."
                    ) {
                        Picker("", selection: $settings.selectorDisplayMode) {
                            ForEach(SelectorDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    .onChange(of: settings.selectorDisplayMode) { _, _ in
                        settings.saveSettings()
                    }
                }
                
                SettingsSection(title: "Color Scheme") {
                    SettingsRow(
                        title: "Appearance",
                        message: "Force light or dark mode, or follow the system setting."
                    ) {
                        Picker("", selection: colorSchemeBinding) {
                            ForEach(AppColorScheme.allCases) { scheme in
                                Text(scheme.rawValue).tag(scheme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                }
                
                // Always show 3-column layout with Light and Dark controls side by side
                dualThemeWindowSection()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            syncLocalState()
        }
        .onChange(of: settings.windowAppearance) { _, _ in
            syncLocalState()
        }
    }
    
    // MARK: - Dual Theme Section (3-column layout for System mode)
    
    @ViewBuilder
    private func dualThemeWindowSection() -> some View {
        SettingsSection(title: "Window") {
            // Background Style row with Light and Dark pickers
            DualThemeRow(
                title: "Background Style",
                message: "Use macOS system materials or a solid color."
            ) {
                Picker("", selection: modeBinding(for: .light)) {
                    ForEach(WindowBackgroundMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } darkContent: {
                Picker("", selection: modeBinding(for: .dark)) {
                    ForEach(WindowBackgroundMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            
            SettingsDivider()
            
            // Material/Color row - show appropriate controls based on each theme's mode
            dualThemeMaterialOrColorRow()
            
            // Blur Radius row - only if either theme is using solid color mode
            if settings.windowAppearance.light.mode == WindowBackgroundMode.solidColor || settings.windowAppearance.dark.mode == WindowBackgroundMode.solidColor {
                SettingsDivider()
                dualThemeBlurRadiusRow()
            }
            
            SettingsDivider()
            dualThemeOutlineWidthRow()
            SettingsDivider()
            dualThemeOutlineColorRow()
        }
    }
    
    @ViewBuilder
    private func dualThemeMaterialOrColorRow() -> some View {
        let lightMode = settings.windowAppearance.light.mode
        let darkMode = settings.windowAppearance.dark.mode
        
        // If both use macOS effects, show material pickers
        if lightMode == WindowBackgroundMode.macOSEffects && darkMode == WindowBackgroundMode.macOSEffects {
            DualThemeRow(
                title: "Material",
                message: "Select the system material style."
            ) {
                Picker("", selection: materialBinding(for: .light)) {
                    ForEach(WindowMaterial.allCases) { material in
                        Text(material.rawValue).tag(material)
                    }
                }
                .pickerStyle(.menu)
            } darkContent: {
                Picker("", selection: materialBinding(for: .dark)) {
                    ForEach(WindowMaterial.allCases) { material in
                        Text(material.rawValue).tag(material)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        // If both use solid, show color pickers
        else if lightMode == WindowBackgroundMode.solidColor && darkMode == WindowBackgroundMode.solidColor {
            DualThemeRow(
                title: "Color",
                message: "Choose the background color and opacity."
            ) {
                ColorPicker("", selection: colorBinding(for: .light), supportsOpacity: true)
                    .labelsHidden()
            } darkContent: {
                ColorPicker("", selection: colorBinding(for: .dark), supportsOpacity: true)
                    .labelsHidden()
            }
        }
        // Mixed: one macOS effects, one solid - show appropriate control for each
        else {
            DualThemeRow(
                title: lightMode == WindowBackgroundMode.macOSEffects ? "Material / Color" : "Color / Material",
                message: "Configure appearance for each theme."
            ) {
                if lightMode == WindowBackgroundMode.macOSEffects {
                    Picker("", selection: materialBinding(for: .light)) {
                        ForEach(WindowMaterial.allCases) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                } else {
                    ColorPicker("", selection: colorBinding(for: .light), supportsOpacity: true)
                        .labelsHidden()
                }
            } darkContent: {
                if darkMode == WindowBackgroundMode.macOSEffects {
                    Picker("", selection: materialBinding(for: .dark)) {
                        ForEach(WindowMaterial.allCases) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                } else {
                    ColorPicker("", selection: colorBinding(for: .dark), supportsOpacity: true)
                        .labelsHidden()
                }
            }
        }
    }
    

    
    @ViewBuilder
    private func dualThemeBlurRadiusRow() -> some View {
        let lightMode = settings.windowAppearance.light.mode
        let darkMode = settings.windowAppearance.dark.mode
        
        DualThemeRow(
            title: "Blur Radius",
            message: "Apply background blur (1 = no blur, higher = more blur)."
        ) {
            if lightMode == WindowBackgroundMode.solidColor {
                HStack(spacing: 4) {
                    Slider(value: blurRadiusBinding(for: .light), in: 1...50)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.0f", localLightBlurRadius))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 24)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        } darkContent: {
            if darkMode == WindowBackgroundMode.solidColor {
                HStack(spacing: 4) {
                    Slider(value: blurRadiusBinding(for: .dark), in: 1...50)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.0f", localDarkBlurRadius))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 24)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func syncLocalState() {
        let light = settings.windowAppearance.light.backgroundColor
        localLightColor = Color(red: light.red, green: light.green, blue: light.blue, opacity: light.alpha)
        localLightBlurRadius = settings.windowAppearance.light.blurRadius
        
        let dark = settings.windowAppearance.dark.backgroundColor
        localDarkColor = Color(red: dark.red, green: dark.green, blue: dark.blue, opacity: dark.alpha)
        localDarkBlurRadius = settings.windowAppearance.dark.blurRadius
        
        let lightOutline = settings.windowAppearance.light.outlineColor
        localLightOutlineColor = Color(red: lightOutline.red, green: lightOutline.green, blue: lightOutline.blue, opacity: lightOutline.alpha)
        localLightOutlineWidth = settings.windowAppearance.light.outlineWidth
        
        let darkOutline = settings.windowAppearance.dark.outlineColor
        localDarkOutlineColor = Color(red: darkOutline.red, green: darkOutline.green, blue: darkOutline.blue, opacity: darkOutline.alpha)
        localDarkOutlineWidth = settings.windowAppearance.dark.outlineWidth
    }
    
    private func modeBinding(for theme: ThemeVariant) -> Binding<WindowBackgroundMode> {
        Binding(
            get: {
                theme == .light ? settings.windowAppearance.light.mode : settings.windowAppearance.dark.mode
            },
            set: { newMode in
                DispatchQueue.main.async {
                    if theme == .light {
                        settings.windowAppearance.light.mode = newMode
                    } else {
                        settings.windowAppearance.dark.mode = newMode
                    }
                    settings.saveSettings()
                    NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
                }
            }
        )
    }
    
    private func materialBinding(for theme: ThemeVariant) -> Binding<WindowMaterial> {
        Binding(
            get: {
                theme == .light ? settings.windowAppearance.light.material : settings.windowAppearance.dark.material
            },
            set: { newMaterial in
                DispatchQueue.main.async {
                    if theme == .light {
                        settings.windowAppearance.light.material = newMaterial
                    } else {
                        settings.windowAppearance.dark.material = newMaterial
                    }
                    settings.saveSettings()
                    NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
                }
            }
        )
    }
    
    private func colorBinding(for theme: ThemeVariant) -> Binding<Color> {
        Binding(
            get: {
                theme == .light ? localLightColor : localDarkColor
            },
            set: { newColor in
                if theme == .light {
                    localLightColor = newColor
                } else {
                    localDarkColor = newColor
                }
                applyColorChange(newColor, for: theme)
            }
        )
    }
    

    
    private func blurRadiusBinding(for theme: ThemeVariant) -> Binding<Double> {
        Binding(
            get: {
                theme == .light ? localLightBlurRadius : localDarkBlurRadius
            },
            set: { newRadius in
                if theme == .light {
                    localLightBlurRadius = newRadius
                } else {
                    localDarkBlurRadius = newRadius
                }
                applyBlurRadiusChange(newRadius, for: theme)
            }
        )
    }
    
    private func outlineWidthBinding(for theme: ThemeVariant) -> Binding<Double> {
        Binding(
            get: { theme == .light ? localLightOutlineWidth : localDarkOutlineWidth },
            set: { newWidth in
                if theme == .light {
                    localLightOutlineWidth = newWidth
                } else {
                    localDarkOutlineWidth = newWidth
                }
                applyOutlineWidthChange(newWidth, for: theme)
            }
        )
    }
    
    private func outlineColorBinding(for theme: ThemeVariant) -> Binding<Color> {
        Binding(
            get: { theme == .light ? localLightOutlineColor : localDarkOutlineColor },
            set: { newColor in
                if theme == .light {
                    localLightOutlineColor = newColor
                } else {
                    localDarkOutlineColor = newColor
                }
                applyOutlineColorChange(newColor, for: theme)
            }
        )
    }
    
    private var colorSchemeBinding: Binding<AppColorScheme> {
        Binding(
            get: { settings.colorScheme },
            set: { newScheme in
                DispatchQueue.main.async {
                    settings.colorScheme = newScheme
                    settings.saveSettings()
                }
            }
        )
    }
    
    private func applyColorChange(_ newColor: Color, for theme: ThemeVariant) {
        let nsColor = NSColor(newColor)
        DispatchQueue.main.async {
            let newColorValue = CodableColor(nsColor: nsColor)
            
            if theme == .light {
                settings.windowAppearance.light.backgroundColor = newColorValue
            } else {
                settings.windowAppearance.dark.backgroundColor = newColorValue
            }
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    private func applyBlurRadiusChange(_ newRadius: Double, for theme: ThemeVariant) {
        DispatchQueue.main.async {
            if theme == .light {
                settings.windowAppearance.light.blurRadius = newRadius
            } else {
                settings.windowAppearance.dark.blurRadius = newRadius
            }
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    private func applyOutlineWidthChange(_ newWidth: Double, for theme: ThemeVariant) {
        DispatchQueue.main.async {
            if theme == .light {
                settings.windowAppearance.light.outlineWidth = newWidth
            } else {
                settings.windowAppearance.dark.outlineWidth = newWidth
            }
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    private func applyOutlineColorChange(_ newColor: Color, for theme: ThemeVariant) {
        let nsColor = NSColor(newColor)
        DispatchQueue.main.async {
            let newColorValue = CodableColor(nsColor: nsColor)
            if theme == .light {
                settings.windowAppearance.light.outlineColor = newColorValue
            } else {
                settings.windowAppearance.dark.outlineColor = newColorValue
            }
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    @ViewBuilder
    private func dualThemeOutlineWidthRow() -> some View {
        DualThemeRow(
            title: "Border Width",
            message: "Thickness of the window edge border."
        ) {
            HStack(spacing: 4) {
                Slider(value: outlineWidthBinding(for: .light), in: 0...4, step: 0.5)
                    .frame(maxWidth: 100)
                Text(String(format: "%.1f", localLightOutlineWidth))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24)
            }
        } darkContent: {
            HStack(spacing: 4) {
                Slider(value: outlineWidthBinding(for: .dark), in: 0...4, step: 0.5)
                    .frame(maxWidth: 100)
                Text(String(format: "%.1f", localDarkOutlineWidth))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24)
            }
        }
    }
    
    @ViewBuilder
    private func dualThemeOutlineColorRow() -> some View {
        DualThemeRow(
            title: "Border Color",
            message: "Color of the window edge border."
        ) {
            ColorPicker("", selection: outlineColorBinding(for: .light), supportsOpacity: true)
                .labelsHidden()
        } darkContent: {
            ColorPicker("", selection: outlineColorBinding(for: .dark), supportsOpacity: true)
                .labelsHidden()
        }
    }
}

enum ThemeVariant {
    case light
    case dark
}
