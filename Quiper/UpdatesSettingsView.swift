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
                    
                    SettingsDivider()
                    
                    SettingsRow(
                        title: "Update channel",
                        message: settings.updatePreferences.channel.description
                    ) {
                        InclusiveChannelPicker(selection: updateChannelBinding)
                    }
                }
            }
            .padding(16)
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
    
    private var updateChannelBinding: Binding<UpdateChannel> {
        Binding(
            get: { settings.updatePreferences.channel },
            set: { newValue in
                settings.updatePreferences.channel = newValue
                settings.saveSettings()
            }
        )
    }
}

struct InclusiveChannelPicker: View {
    @Binding var selection: UpdateChannel
    private let channels = UpdateChannel.allCases
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background track
            Capsule()
                .fill(Color(NSColor.quaternaryLabelColor))
                .frame(height: 24)
            
            // Highlight track (Selected from left)
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let segmentWidth = totalWidth / CGFloat(channels.count)
                let selectedIndex = CGFloat(channels.firstIndex(of: selection) ?? 0)
                let highlightWidth = (selectedIndex + 1) * segmentWidth
                
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: highlightWidth, height: 24)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
            }
            .frame(height: 24)
            
            // Buttons
            HStack(spacing: 0) {
                ForEach(channels) { channel in
                    Button(action: { selection = channel }) {
                        Text(channel.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isHighlighted(channel) ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 210)
    }
    
    private func isHighlighted(_ channel: UpdateChannel) -> Bool {
        let selectedIdx = channels.firstIndex(of: selection) ?? 0
        let channelIdx = channels.firstIndex(of: channel) ?? 0
        return channelIdx <= selectedIdx
    }
}
