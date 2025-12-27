import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    // Local state for color/opacity to avoid SwiftUI publishing conflicts - separate for each theme
    @State private var localLightColor: Color = Color(red: 0.95, green: 0.95, blue: 0.95)
    @State private var localLightOpacity: Double = 0.85
    @State private var localLightBlurRadius: Double = 1.0
    @State private var localDarkColor: Color = Color(red: 0.26, green: 0.21, blue: 0.25)
    @State private var localDarkOpacity: Double = 0.51
    @State private var localDarkBlurRadius: Double = 1.0
    
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
            
            // Opacity and Blur Radius rows - only if either theme is using solid color mode
            if settings.windowAppearance.light.mode == WindowBackgroundMode.solidColor || settings.windowAppearance.dark.mode == WindowBackgroundMode.solidColor {
                SettingsDivider()
                dualThemeOpacityRow()
                
                SettingsDivider()
                dualThemeBlurRadiusRow()
            }
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
                message: "Choose the background color."
            ) {
                ColorPicker("", selection: colorBinding(for: .light), supportsOpacity: false)
                    .labelsHidden()
            } darkContent: {
                ColorPicker("", selection: colorBinding(for: .dark), supportsOpacity: false)
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
                    ColorPicker("", selection: colorBinding(for: .light), supportsOpacity: false)
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
                    ColorPicker("", selection: colorBinding(for: .dark), supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }
    
    @ViewBuilder
    private func dualThemeOpacityRow() -> some View {
        let lightMode = settings.windowAppearance.light.mode
        let darkMode = settings.windowAppearance.dark.mode
        
        DualThemeRow(
            title: "Opacity",
            message: "Adjust background transparency (0% = fully transparent)."
        ) {
            if lightMode == WindowBackgroundMode.solidColor {
                HStack(spacing: 4) {
                    Slider(value: opacityBinding(for: .light), in: 0...1)
                        .frame(maxWidth: 100)
                    Text("\(Int(localLightOpacity * 100))%")
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        } darkContent: {
            if darkMode == WindowBackgroundMode.solidColor {
                HStack(spacing: 4) {
                    Slider(value: opacityBinding(for: .dark), in: 0...1)
                        .frame(maxWidth: 100)
                    Text("\(Int(localDarkOpacity * 100))%")
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
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
        localLightColor = Color(red: light.red, green: light.green, blue: light.blue)
        localLightOpacity = light.alpha
        localLightBlurRadius = settings.windowAppearance.light.blurRadius
        
        let dark = settings.windowAppearance.dark.backgroundColor
        localDarkColor = Color(red: dark.red, green: dark.green, blue: dark.blue)
        localDarkOpacity = dark.alpha
        localDarkBlurRadius = settings.windowAppearance.dark.blurRadius
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
    
    private func opacityBinding(for theme: ThemeVariant) -> Binding<Double> {
        Binding(
            get: {
                theme == .light ? localLightOpacity : localDarkOpacity
            },
            set: { newOpacity in
                if theme == .light {
                    localLightOpacity = newOpacity
                } else {
                    localDarkOpacity = newOpacity
                }
                applyOpacityChange(newOpacity, for: theme)
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
        NSLog("[Quiper] SettingsView received color change: \(nsColor)")
        DispatchQueue.main.async {
            let currentAlpha = theme == .light
                ? settings.windowAppearance.light.backgroundColor.alpha
                : settings.windowAppearance.dark.backgroundColor.alpha
            
            let newColorValue = CodableColor(nsColor: nsColor.withAlphaComponent(currentAlpha))
            
            if theme == .light {
                settings.windowAppearance.light.backgroundColor = newColorValue
            } else {
                settings.windowAppearance.dark.backgroundColor = newColorValue
            }
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    private func applyOpacityChange(_ newOpacity: Double, for theme: ThemeVariant) {
        DispatchQueue.main.async {
            if theme == .light {
                settings.windowAppearance.light.backgroundColor.alpha = newOpacity
            } else {
                settings.windowAppearance.dark.backgroundColor.alpha = newOpacity
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
}

enum ThemeVariant {
    case light
    case dark
}
