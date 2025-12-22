import SwiftUI

struct UpdatesSettingsView: View {
    private let versionDescription = Bundle.main.versionDisplayString
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = UpdateManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection(title: "Version") {
                    SettingsRow(
                        title: "Current version",
                        message: updater.statusDescription
                    ) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(versionDescription)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    SettingsDivider()
                    
                    SettingsRow(
                        title: "Manual check",
                        message: "Immediately trigger an update check from GitHub releases."
                    ) {
                        Button(action: { updater.checkForUpdates(userInitiated: true) }) {
                            Text(updater.isChecking ? "Checking…" : "Check for Updates")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isChecking)
                    }
                }
                
                SettingsSection(title: "Automatic Updates") {
                    SettingsToggleRow(
                        title: "Automatically check for updates",
                        message: "Poll in the background and notify you when a new build ships.",
                        isOn: autoCheckBinding
                    )
                    
                    SettingsDivider()
                    
                    SettingsToggleRow(
                        title: "Automatically download updates",
                        message: "Fetch new builds as soon as they're found so installs are instant.",
                        isOn: autoDownloadBinding
                    )
                    .disabled(!settings.updatePreferences.automaticallyChecksForUpdates)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { settings.updatePreferences.automaticallyChecksForUpdates },
            set: { newValue in
                settings.updatePreferences.automaticallyChecksForUpdates = newValue
                if !newValue && settings.updatePreferences.automaticallyDownloadsUpdates {
                    settings.updatePreferences.automaticallyDownloadsUpdates = false
                }
                settings.saveSettings()
            }
        )
    }
    
    private var autoDownloadBinding: Binding<Bool> {
        Binding(
            get: { settings.updatePreferences.automaticallyDownloadsUpdates },
            set: { newValue in
                settings.updatePreferences.automaticallyDownloadsUpdates = newValue
                settings.saveSettings()
            }
        )
    }
}
