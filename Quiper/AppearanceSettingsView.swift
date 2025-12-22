import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    // Local state for color/opacity to avoid SwiftUI publishing conflicts
    @State private var localColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1)
    @State private var localOpacity: Double = 0.8
    
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
                
                SettingsSection(title: "Window") {
                    SettingsRow(
                        title: "Background Style",
                        message: "Choose between system blur effect or a solid color."
                    ) {
                        Picker("", selection: modeBinding) {
                            ForEach(WindowBackgroundMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    if settings.windowAppearance.mode == .blur {
                        SettingsDivider()
                        
                        SettingsRow(
                            title: "Material",
                            message: "Select the blur material style."
                        ) {
                            Picker("", selection: materialBinding) {
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
                            ColorPicker("", selection: $localColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: localColor) { _, newColor in
                                    applyColorChange(newColor)
                                }
                        }
                        
                        SettingsDivider()
                        
                        SettingsRow(
                            title: "Opacity",
                            message: "Adjust background transparency (0% = fully transparent)."
                        ) {
                            HStack {
                                Slider(value: $localOpacity, in: 0...1)
                                    .frame(width: 150)
                                    .onChange(of: localOpacity) { _, newOpacity in
                                        applyOpacityChange(newOpacity)
                                    }
                                Text("\(Int(localOpacity * 100))%")
                                    .frame(width: 40, alignment: .trailing)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
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
    
    private func syncLocalState() {
        let c = settings.windowAppearance.backgroundColor
        localColor = Color(red: c.red, green: c.green, blue: c.blue)
        localOpacity = c.alpha
    }
    
    private var modeBinding: Binding<WindowBackgroundMode> {
        Binding(
            get: { settings.windowAppearance.mode },
            set: { newMode in
                DispatchQueue.main.async {
                    settings.windowAppearance.mode = newMode
                    settings.saveSettings()
                    NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
                }
            }
        )
    }
    
    private var materialBinding: Binding<WindowMaterial> {
        Binding(
            get: { settings.windowAppearance.material },
            set: { newMaterial in
                DispatchQueue.main.async {
                    settings.windowAppearance.material = newMaterial
                    settings.saveSettings()
                    NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
                }
            }
        )
    }
    
    private func applyColorChange(_ newColor: Color) {
        let nsColor = NSColor(newColor)
        DispatchQueue.main.async {
            settings.windowAppearance.backgroundColor = CodableColor(
                red: Double(nsColor.redComponent),
                green: Double(nsColor.greenComponent),
                blue: Double(nsColor.blueComponent),
                alpha: settings.windowAppearance.backgroundColor.alpha
            )
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
    
    private func applyOpacityChange(_ newOpacity: Double) {
        DispatchQueue.main.async {
            settings.windowAppearance.backgroundColor.alpha = newOpacity
            settings.saveSettings()
            NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        }
    }
}
