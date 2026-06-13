import SwiftUI

struct UpdatesSettingsView: View {
    private let versionDescription = Bundle.main.versionDisplayString
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = UpdateManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection(title: "Version", icon: "info.circle.fill", iconColor: .blue) {
                    SettingsRow(
                        title: "Current Version",
                        message: updater.statusDescription,
                        icon: "info.circle",
                        iconColor: .blue
                    ) {
                        Text(versionDescription)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 260, alignment: .trailing)
                    }
                    
                    SettingsDivider()
                    
                    SettingsRow(
                        title: "Manual Check",
                        message: "Immediately trigger an update check from GitHub releases.",
                        icon: "arrow.clockwise.circle",
                        iconColor: .blue
                    ) {
                        Button(action: { updater.checkForUpdates(userInitiated: true) }) {
                            Text(updater.isChecking ? "Checking…" : "Check for Updates")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.settingsColorStyle == .classic ? nil : .blue)
                        .disabled(updater.isChecking)
                        .frame(width: 260, alignment: .trailing)
                    }
                }
                
                SettingsSection(title: "Automatic Updates", icon: "arrow.down.circle.fill", iconColor: .green) {
                    SettingsRow(
                        title: "Automatic Updates",
                        message: "Poll in the background and fetch new builds automatically.",
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .green
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Automatically check for updates", isOn: autoCheckBinding)
                            Toggle("Automatically download updates", isOn: autoDownloadBinding)
                                .disabled(!settings.updatePreferences.automaticallyChecksForUpdates)
                        }
                        .toggleStyle(.coloredCheckbox(Color.green.settingsResolved))
                        .frame(width: 260, alignment: .leading)
                    }
                    
                    SettingsDivider()
                    
                    SettingsRow(
                        title: "Update Channel",
                        message: settings.updatePreferences.channel.description,
                        icon: "point.3.connected.trianglepath.dotted",
                        iconColor: .green
                    ) {
                        HStack {
                            Spacer()
                            InclusiveChannelPicker(selection: updateChannelBinding, accentColor: .green)
                        }
                        .frame(width: 260)
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
    var accentColor: Color = .green
    @ObservedObject private var settings = Settings.shared
    private let channels = UpdateChannel.allCases
    
    var body: some View {
        let resolvedColor = settings.settingsColorStyle == .classic ? Color.secondary : accentColor
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
                    .fill(resolvedColor)
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
