import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    // Local state for color/opacity to avoid SwiftUI publishing conflicts - separate for each theme
    @State private var localLightColor: Color = Color(red: 0.95, green: 0.95, blue: 0.95)
    @State private var localLightOpacity: Double = 0.85
    @State private var localDarkColor: Color = Color(red: 0.26, green: 0.21, blue: 0.25)
    @State private var localDarkOpacity: Double = 0.51
    
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
                
                // Show window settings based on color scheme selection
                switch settings.colorScheme {
                case .system:
                    // Show both light and dark settings
                    themeWindowSection(theme: .light, title: "Window (Light Theme)")
                    themeWindowSection(theme: .dark, title: "Window (Dark Theme)")
                case .light:
                    themeWindowSection(theme: .light, title: "Window")
                case .dark:
                    themeWindowSection(theme: .dark, title: "Window")
                }
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
    
    @ViewBuilder
    private func themeWindowSection(theme: ThemeVariant, title: String) -> some View {
        let themeSettings = theme == .light ? settings.windowAppearance.light : settings.windowAppearance.dark
        
        SettingsSection(title: title) {
            SettingsRow(
                title: "Background Style",
                message: "Choose between system blur effect or a solid color."
            ) {
                Picker("", selection: modeBinding(for: theme)) {
                    ForEach(WindowBackgroundMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            if themeSettings.mode == .blur {
                SettingsDivider()
                
                SettingsRow(
                    title: "Material",
                    message: "Select the blur material style."
                ) {
                    Picker("", selection: materialBinding(for: theme)) {
                        ForEach(WindowMaterial.allCases) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            } else {
                SettingsDivider()
                
                SettingsRow(
                    title: "Color",
                    message: "Choose the background color."
                ) {
                    ColorPicker("", selection: colorBinding(for: theme), supportsOpacity: false)
                        .labelsHidden()
                }
                
                SettingsDivider()
                
                SettingsRow(
                    title: "Opacity",
                    message: "Adjust background transparency (0% = fully transparent)."
                ) {
                    HStack {
                        Slider(value: opacityBinding(for: theme), in: 0...1)
                            .frame(width: 150)
                        Text("\(Int((theme == .light ? localLightOpacity : localDarkOpacity) * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }
    
    private func syncLocalState() {
        let light = settings.windowAppearance.light.backgroundColor
        localLightColor = Color(red: light.red, green: light.green, blue: light.blue)
        localLightOpacity = light.alpha
        
        let dark = settings.windowAppearance.dark.backgroundColor
        localDarkColor = Color(red: dark.red, green: dark.green, blue: dark.blue)
        localDarkOpacity = dark.alpha
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
}

enum ThemeVariant {
    case light
    case dark
}
