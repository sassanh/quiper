import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Backup/restore, local-network sync, content blocking, and the destructive
/// reset actions. Split out of the General tab, which grew too long after the
/// window-behavior rows moved in.
struct DataPrivacySettingsView: View {
    var appController: AppController?
    @ObservedObject private var settings = Settings.shared

    @State private var showClearWebConfirmation = false
    @State private var showEraseEnginesConfirmation = false
    @State private var eraseEnginesHasUnsavedChanges = false
    @State private var showEraseActionsConfirmation = false
    @State private var exportError: String?
    @State private var importError: String?
    @State private var exportSuccessMessage: String?
    @State private var showingSecureExportChoice = false
    @State private var secureExportChoice: SecureExportChoice = .keepLocked
    @State private var secureExportServices: [Service] = []
    @State private var pendingImportData: Data?
    @State private var pendingImportOrphans: [Service] = []
    @State private var pendingImportTotalProtected = 0
    @State private var showingSecureImportChoice = false
    @State private var shouldProceedWithSecureExport = false
    @State private var exportProgressPanel: SecureExportProgressPanel? = nil
    @State private var showingSyncProviderSetup = false
    @State private var showingSyncProviderActive = false
    @State private var syncProviderData: Data?
    @State private var showingSyncBrowser = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection(title: "Privacy", icon: "hand.raised.fill", iconColor: .indigo.settingsResolved) {
                    SettingsRow(
                        title: "Ads & Trackers",
                        message: "Block ads and trackers on every page using the EasyList and EasyPrivacy filter lists, plus AdGuard Extra and AdGuard's YouTube script for ads that rules alone can't stop — including YouTube video ads. Everything ships with Quiper; nothing is downloaded in the background.",
                        icon: "shield.lefthalf.filled",
                        iconColor: .indigo.settingsResolved
                    ) {
                        ContentBlockingPicker()
                    }
                }

                SettingsSection(title: "Config", icon: "square.and.arrow.up.on.square.fill", iconColor: .green) {
                    SettingsRow(
                        title: "Backup & Restore",
                        message: "Export your setup to a backup file, or restore configuration from an existing backup.",
                        icon: "doc.badge.gearshape.fill",
                        iconColor: .green
                    ) {
                        HStack(spacing: 12) {
                            configActionButton("Export", systemImage: "square.and.arrow.up", iconSize: 18) {
                                handleExportTapped()
                            }
                            configActionButton("Import", systemImage: "square.and.arrow.down", iconSize: 18) {
                                handleImportTapped()
                            }
                        }
                        .frame(width: 260, alignment: .trailing)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Sync over Local Network",
                        message: "Temporarily share this config on the local network, or discover nearby devices to pull their config.",
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: .green
                    ) {
                        HStack(spacing: 12) {
                            configActionButton("Share", systemImage: "antenna.radiowaves.left.and.right") {
                                handleSyncShareTapped()
                            }
                            configActionButton("Receive", systemImage: "magnifyingglass") {
                                showingSyncBrowser = true
                            }
                        }
                        .frame(width: 260, alignment: .trailing)
                    }
                }

                SettingsSection(title: "Danger Zone", titleColor: .red, cardBackground: Color.red.opacity(0.05), icon: "exclamationmark.triangle.fill", iconColor: .red) {
                    SettingsRow(
                        title: "Clear All Web Data",
                        message: "Delete cookies, caches, and storage for every engine so all sites behave like fresh logins.",
                        icon: "globe",
                        iconColor: .red
                    ) {
                        destructiveActionButton("Clear Data", systemImage: "trash") {
                            showClearWebConfirmation = true
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Erase All Engines",
                        message: "Remove every configured engine and its stored scripts.",
                        icon: "cpu.fill",
                        iconColor: .red
                    ) {
                        destructiveActionButton("Erase Engines", systemImage: "xmark.bin") {
                            Task {
                                let ids = settings.services.map { $0.id }
                                let blocking = await appController?.unloadInfosNeedingConfirmation(for: ids) ?? []
                                eraseEnginesHasUnsavedChanges = !blocking.isEmpty
                                showEraseEnginesConfirmation = true
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Erase All Actions",
                        message: "Delete every custom action and its scripts across engines.",
                        icon: "terminal.fill",
                        iconColor: .red
                    ) {
                        destructiveActionButton("Erase Actions", systemImage: "play.slash") {
                            showEraseActionsConfirmation = true
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onExitCommand {
            if showingSecureExportChoice { showingSecureExportChoice = false }
            else if showingSecureImportChoice { showingSecureImportChoice = false }
            else if showingSyncProviderSetup { showingSyncProviderSetup = false }
            else if showingSyncProviderActive { showingSyncProviderActive = false }
            else if showingSyncBrowser { showingSyncBrowser = false }
        }
        .alert("Clear saved web data for all engines?", isPresented: $showClearWebConfirmation) {
            Button("Clear All", role: .destructive) {
                clearWebData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes cookies, caches, and storage for every engine.")
        }
        .alert("Erase all engines?", isPresented: $showEraseEnginesConfirmation) {
            Button("Erase", role: .destructive) {
                eraseAllEngines()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(eraseEnginesHasUnsavedChanges
                ? "Deletes every engine and its local scripts." + TabCloseGate.settingsWarningSuffix
                : "Deletes every engine and its local scripts.")
        }
        .alert("Erase all actions?", isPresented: $showEraseActionsConfirmation) {
            Button("Erase", role: .destructive) {
                eraseAllActions()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes every custom action and the scripts stored for them.")
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Export successful", isPresented: Binding(get: { exportSuccessMessage != nil }, set: { if !$0 { exportSuccessMessage = nil } })) {
            Button("OK", role: .cancel) { exportSuccessMessage = nil }
        } message: {
            Text(exportSuccessMessage ?? "")
        }
        .sheet(isPresented: $showingSecureExportChoice, onDismiss: {
            guard shouldProceedWithSecureExport else { return }
            shouldProceedWithSecureExport = false
            switch secureExportChoice {
            case .keepLocked, .exclude:
                ConfigPortManager.showExportPanelWithChoice(in: nil, choice: secureExportChoice) { result in
                    switch result {
                    case .success(let url):
                        exportSuccessMessage = "Config exported to \(url.lastPathComponent)"
                    case .failure(let error):
                        exportError = error.localizedDescription
                    }
                }
            case .decryptForMigration:
                let services = secureExportServices
                let panel = SecureExportProgressPanel(services: services, onComplete: { decrypted in
                    exportProgressPanel = nil
                    ConfigPortManager.showExportPanelWithDecryptedEngines(in: nil, decryptedEngines: decrypted) { result in
                        switch result {
                        case .success(let url):
                            exportSuccessMessage = "Config exported to \(url.lastPathComponent)"
                        case .failure(let error):
                            exportError = error.localizedDescription
                        }
                    }
                }, onCancel: {
                    exportProgressPanel = nil
                })
                exportProgressPanel = panel
                panel.show()
            }
        }) {
            SecureExportChoiceSheet(
                encryptedCount: secureExportServices.count,
                selection: $secureExportChoice,
                onCancel: { showingSecureExportChoice = false },
                onExport: {
                    shouldProceedWithSecureExport = true
                    showingSecureExportChoice = false
                }
            )
        }
        .sheet(isPresented: $showingSecureImportChoice) {
            SecureImportChoiceSheet(
                orphanCount: pendingImportOrphans.count,
                totalProtectedCount: pendingImportTotalProtected,
                onKeep: {
                    showingSecureImportChoice = false
                    guard let data = pendingImportData else { return }
                    do {
                        try ConfigPortManager.importConfig(from: data)
                        pendingImportData = nil
                        appController?.reloadServices()
                    } catch {
                        importError = error.localizedDescription
                    }
                },
                onDrop: {
                    showingSecureImportChoice = false
                    guard let data = pendingImportData else { return }
                    do {
                        try ConfigPortManager.importConfig(from: data, droppingOrphans: true)
                        pendingImportData = nil
                        appController?.reloadServices()
                    } catch {
                        importError = error.localizedDescription
                    }
                },
                onCancel: {
                    showingSecureImportChoice = false
                    pendingImportData = nil
                }
            )
        }
        .sheet(isPresented: $showingSyncProviderSetup) {
            QuiperSyncProviderSetupSheet(
                onCancel: { showingSyncProviderSetup = false },
                onReady: { data in
                    syncProviderData = data
                    showingSyncProviderSetup = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingSyncProviderActive = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingSyncProviderActive) {
            Group {
                if let data = syncProviderData {
                    QuiperSyncProviderSheet(syncData: data) {
                        showingSyncProviderActive = false
                        syncProviderData = nil
                    }
                } else {
                    SyncProviderPreparationFallbackView(onClose: {
                        showingSyncProviderActive = false
                        syncProviderData = nil
                    })
                }
            }
        }
        .sheet(isPresented: $showingSyncBrowser) {
            QuiperSyncBrowserSheet(appController: appController) {
                showingSyncBrowser = false
            }
        }
    }

    // MARK: - Section action buttons

    private func configActionButton(
        _ label: String,
        systemImage: String,
        iconSize: CGFloat = 16,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        .frame(width: 44, height: 36)
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(Color.green.settingsResolved)
                }
                .frame(width: 44, height: 36)
                .padding(8)
                .pickerCardStyle(isSelected: false, accentColor: .green)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func destructiveActionButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(label)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .frame(width: 260, alignment: .trailing)
    }

    // MARK: - Secure export / import

    private func handleExportTapped() {
        guard settings.hasEncryptedServices else {
            ConfigPortManager.showExportPanel(in: NSApp.keyWindow) { result in
                switch result {
                case .success(let url):
                    exportSuccessMessage = "Config exported to \(url.lastPathComponent)"
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
            return
        }
        secureExportServices = settings.services.filter { $0.isEncrypted }
        secureExportChoice = .keepLocked
        showingSecureExportChoice = true
    }

    private func handleSyncShareTapped() {
        if settings.hasEncryptedServices {
            showingSyncProviderSetup = true
        } else {
            Task { @MainActor in
                do {
                    SyncPreparationState.shared.set(.readingEngines, "Reading engines…")
                    let data = try SettingsPersistence.prepareSnapshotForCurrentSettings()
                    SyncPreparationState.shared.set(.startingShare, "Snapshot encoded (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))) — starting share…")
                    syncProviderData = data
                    showingSyncProviderActive = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    SyncPreparationState.shared.clear()
                } catch {
                    SyncPreparationState.shared.clear()
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func handleImportTapped() {
        let panel = NSOpenPanel()
        panel.title = "Import Quiper Config"
        panel.message = "This will overwrite all current settings and action scripts."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.init(filenameExtension: ConfigPortability.fileExtension)!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    let persisted = try ConfigPortability.decode(from: data)
                    let orphans = settings.orphanedServicesForImport(in: persisted)
                    if orphans.isEmpty {
                        try ConfigPortManager.importConfig(from: data)
                        appController?.reloadServices()
                    } else {
                        pendingImportData = data
                        pendingImportOrphans = orphans
                        pendingImportTotalProtected = persisted.minimalEncryptedServices.count
                        showingSecureImportChoice = true
                    }
                } catch {
                    importError = error.localizedDescription
                }
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func clearWebData() {
        appController?.clearWebViewData(nil)
    }

    private func eraseAllEngines() {
        let ids = settings.services.map { $0.id }
        settings.services.removeAll()
        ids.forEach { id in
            ActionScriptStorage.deleteScripts(for: id)
            CustomCSSStorage.deleteCSS(for: id)
            FocusSelectorStorage.deleteSelector(for: id)
        }
        settings.saveSettings()
        appController?.reloadServices()
    }

    private func eraseAllActions() {
        for index in settings.services.indices {
            let serviceID = settings.services[index].id
            settings.services[index].actionScripts.removeAll()
            ActionScriptStorage.deleteScripts(for: serviceID)
        }
        settings.customActions.removeAll()
        settings.saveSettings()
        appController?.reloadServices()
    }
}
