import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
