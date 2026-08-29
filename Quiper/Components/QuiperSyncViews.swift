import SwiftUI
import Network
#if os(macOS)
import AppKit
#endif

// MARK: - Provider sheet

struct QuiperSyncProviderSheet: View {
    let syncData: Data
    var onDone: () -> Void

    @StateObject private var provider: QuiperSyncProvider
    @Environment(\.dismiss) private var dismiss

    init(syncData: Data, onDone: @escaping () -> Void) {
        self.syncData = syncData
        self.onDone = onDone
        _provider = StateObject(wrappedValue: QuiperSyncProvider(data: syncData))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed top: header + status
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
            }
            .padding(24)

            Divider()

            // Scrollable middle: only the transfers list scrolls
            ScrollView {
                transfersList
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .frame(maxHeight: .infinity)

            // Fixed bottom: info stays pinned above the Done bar
            VStack(alignment: .leading, spacing: 8) {
                info
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    provider.stop()
                    onDone()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.blue.settingsResolved)
            }
            .padding(16)
        }
        .frame(width: 520, height: 504)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            provider.start()
        }
        .onDisappear {
            provider.stop()
        }
    }

    private var transfersList: some View {
        Group {
            if !provider.transfers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Successful Transfers")
                        .font(.headline)
                    ForEach(provider.transfers) { transfer in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transfer.peerName)
                                    .font(.subheadline.weight(.medium))
                                Text(transfer.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Delivered")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25), lineWidth: 1))
                    }
                }
            } else if provider.servedCount == 0 {
                // No transfers yet, show placeholder
                EmptyView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.blue.settingsResolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sharing Settings")
                        .font(.title3.bold())
                    Text(provider.isAdvertising ? "Visible on local network" : "Starting…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .opacity(provider.isAdvertising ? 1 : 0.6)
            }
            Text("Keep this window open while the other Quiper discovers and pulls your config. Your settings on this Mac do not change.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !provider.isAdvertising && provider.errorMessage == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for local network permission…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("If this stays, check System Settings → Privacy & Security → Local Network and allow Quiper. The system dialog may be hidden behind this window.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25), lineWidth: 1))
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: provider.isAdvertising ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(provider.isAdvertising ? .green : .secondary)
                Text(provider.advertisedName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(provider.isAdvertising ? "Sharing" : "Preparing")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(provider.isAdvertising ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12)))
                    .foregroundStyle(provider.isAdvertising ? .green : .secondary)
            }
            Divider()
            HStack {
                Label("Config size", systemImage: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(syncData.count), countStyle: .file))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Served", systemImage: "arrow.down.doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(provider.servedCount) receiver\(provider.servedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = provider.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On the other Mac, open Settings → Config → Sync → Receive and select this device.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("The share stops when you close this sheet or click Stop Sharing. Nothing is written to disk on this Mac.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Provider setup (choice + optional decrypt progress)

struct QuiperSyncProviderSetupSheet: View {
    var onCancel: () -> Void
    var onReady: (Data) -> Void

    @ObservedObject private var settings = Settings.shared
    @State private var selection: SecureExportChoice = .decryptForMigration
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var decryptedEngines: [Settings.DecryptedEngineForExport] = []
    @State private var activeProgressPanel: SecureExportProgressPanel?
    @State private var showingDecryptProgress = false

    private var encryptedServices: [Service] {
        settings.services.filter { $0.isEncrypted }
    }

    private var unavailableServices: [Service] {
        encryptedServices.filter { !settings.hasLocalSecureData(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.blue.settingsResolved)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Settings on Local Network")
                                .font(.title3.bold())
                            Text(encryptedServices.isEmpty ? "No protected engines" : "\(encryptedServices.count) protected engine\(encryptedServices.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Choose how protected engines are shared. You will stay the provider until you close the sharing window; receivers pull a snapshot taken now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !encryptedServices.isEmpty {
                        choiceCard(
                            title: "Decrypt for Migration",
                            subtitle: "Use Anywhere",
                            description: "Unlock each protected engine so receivers get full config. You authenticate for each locked engine.",
                            icon: "lock.open.fill",
                            selected: selection == .decryptForMigration
                        ) { selection = .decryptForMigration }

                        choiceCard(
                            title: "Exclude Protected",
                            subtitle: "Skip Them",
                            description: "Receivers get only unprotected engines.",
                            icon: "eye.slash.fill",
                            selected: selection == .exclude
                        ) { selection = .exclude }

                        if !unavailableServices.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(unavailableServices.count) protected engine\(unavailableServices.count == 1 ? "" : "s") have no local secure data and cannot be decrypted.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(unavailableServices, id: \.id) { svc in
                                    Text("• \(svc.name)").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Choose Exclude to skip them, or unlock and repair them before sharing.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        }
                    } else {
                        Text("Your config will be shared as shown — no protected engines to choose for.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isWorking {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Preparing snapshot…")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Reading engines and requesting Local Network access. If this stays more than a few seconds, check System Settings → Privacy & Security → Local Network and allow Quiper — the system dialog may be hidden behind this window.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking || showingDecryptProgress)
                Spacer()
                Button("Start Sharing") {
                    Task { await prepareAndShare() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.blue.settingsResolved)
                .disabled(isWorking || showingDecryptProgress)
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay {
            if showingDecryptProgress {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                    VStack(spacing: 0) {
                        SecureExportProgressSheet(
                            services: encryptedServices,
                            onComplete: { decrypted in
                                showingDecryptProgress = false
                                Task { @MainActor in
                                    do {
                                        let data = try SettingsPersistence.prepareSnapshot(secureChoice: .decryptForMigration, decryptedEngines: decrypted)
                                        onReady(data)
                                    } catch {
                                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                    }
                                }
                            },
                            onCancel: {
                                showingDecryptProgress = false
                            }
                        )
                        .frame(width: 460, height: 320)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 20))
                    }
                    .padding(24)
                }
            }
        }
    }

    private func choiceCard(title: String, subtitle: String, description: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.blue.settingsResolved : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(selected ? Color.blue.settingsResolved.opacity(0.12) : Color.secondary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline).foregroundStyle(Color.primary)
                        Text(subtitle).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.secondary.opacity(0.12))).foregroundStyle(.secondary)
                    }
                    Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.blue.settingsResolved : Color.secondary.opacity(0.4))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.blue.settingsResolved : Color(NSColor.separatorColor), lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private func prepareAndShare() async {
        errorMessage = nil
        // For Decrypt, reuse the same per-engine progress sheet as file export (no duplicated logic).
        // Use an inline overlay (not a separate NSPanel) so the Touch ID prompt is not hidden behind a modal sheet.
        if selection == .decryptForMigration && !encryptedServices.isEmpty {
            // If any engine has no local bundle we already warn; still allow but it will fail per-engine with a clear message.
            showingDecryptProgress = true
            return
        }

        isWorking = true
        SyncPreparationState.shared.detail = "Reading engines…"
        settings.syncPreparationDetail = SyncPreparationState.shared.detail
        defer {
            isWorking = false
            if errorMessage != nil {
                SyncPreparationState.shared.detail = nil
                settings.syncPreparationDetail = nil
            }
        }
        do {
            let data: Data
            if encryptedServices.isEmpty {
                SyncPreparationState.shared.detail = "Packaging snapshot — preparing \(settings.services.count) engines…"
                settings.syncPreparationDetail = SyncPreparationState.shared.detail
                data = try SettingsPersistence.prepareSnapshotForCurrentSettings()
            } else {
                // Only Exclude remains (Keep Locked treated as Exclude)
                SyncPreparationState.shared.detail = "Packaging snapshot — preparing \(settings.services.filter { !$0.isEncrypted }.count) engines…"
                settings.syncPreparationDetail = SyncPreparationState.shared.detail
                data = try SettingsPersistence.prepareSnapshot(secureChoice: .exclude, decryptedEngines: [])
            }
            SyncPreparationState.shared.detail = "Starting local network…"
            settings.syncPreparationDetail = SyncPreparationState.shared.detail
            onReady(data)
            // Clear after handoff; provider sheet will show its own status
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if SyncPreparationState.shared.detail == "Starting local network…" {
                    SyncPreparationState.shared.detail = nil
                    settings.syncPreparationDetail = nil
                }
            }
        } catch {
            SyncPreparationState.shared.detail = nil
            settings.syncPreparationDetail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Browser sheet

struct QuiperSyncBrowserSheet: View {
    var appController: AppController?
    var onClose: () -> Void

    @StateObject private var browser = QuiperSyncBrowser()
    @State private var selectedPeer: DiscoveredSyncPeer?
    @State private var isFetching = false
    @State private var fetchProgress: Double?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var pendingData: Data?
    @State private var pendingOrphans: [Service] = []
    @State private var pendingTotalProtected = 0
    @State private var showingImportChoice = false

    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if browser.isBrowsing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning local network…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") { browser.refresh() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else if let error = browser.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if browser.peers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("No devices sharing nearby")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("On the other Mac, open Settings → Config → Sync → Share. Both Macs must be on the same Wi-Fi or wired network and have Local Network access allowed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(browser.peers) { peer in
                            peerRow(peer)
                        }
                    }

                    if isFetching {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing from \(selectedPeer?.displayName ?? "device")…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let progress = fetchProgress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(successMessage)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button(successMessage != nil ? "Done" : "Close") {
                    browser.stop()
                    let wasSuccess = successMessage != nil
                    onClose()
                    if wasSuccess {
                        dismiss()
                        #if os(macOS)
                        DispatchQueue.main.async {
                            AppDelegate.sharedSettingsWindow.close()
                            NSApp.keyWindow?.close()
                        }
                        #endif
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.blue.settingsResolved)
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
        .sheet(isPresented: $showingImportChoice) {
            SecureImportChoiceSheet(
                orphanCount: pendingOrphans.count,
                totalProtectedCount: pendingTotalProtected,
                onKeep: {
                    showingImportChoice = false
                    guard let data = pendingData else { return }
                    Task { await apply(data: data, droppingOrphans: false) }
                },
                onDrop: {
                    showingImportChoice = false
                    guard let data = pendingData else { return }
                    Task { await apply(data: data, droppingOrphans: true) }
                },
                onCancel: {
                    showingImportChoice = false
                    pendingData = nil
                    errorMessage = "Sync cancelled."
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.blue.settingsResolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive Settings")
                        .font(.title3.bold())
                    Text("Choose a nearby sharer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Select a device that is currently sharing. Sync replaces your settings with theirs after you confirm. The sharing Mac does not change.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func peerRow(_ peer: DiscoveredSyncPeer) -> some View {
        let isSelected = selectedPeer?.id == peer.id
        let isFetchingThis = isFetching && isSelected
        return HStack(spacing: 12) {
            Image(systemName: "macbook")
                .font(.system(size: 18))
                .foregroundStyle(Color.blue.settingsResolved)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue.settingsResolved.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(peer.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let ver = peer.quipVersion {
                        Text("v\(ver)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                Task { await sync(from: peer) }
            } label: {
                HStack(spacing: 4) {
                    if isFetchingThis { ProgressView().controlSize(.small) }
                    Text(isFetchingThis ? "Syncing…" : "Sync")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue.settingsResolved)
            .disabled(isFetching)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.blue.settingsResolved : Color(NSColor.separatorColor), lineWidth: isSelected ? 1.5 : 0.5))
    }

    private func sync(from peer: DiscoveredSyncPeer) async {
        isFetching = true
        fetchProgress = nil
        errorMessage = nil
        successMessage = nil
        selectedPeer = peer
        do {
            let data = try await QuiperSyncClient.fetch(from: peer.endpoint)
            let persisted = try ConfigPortability.decode(from: data)
            let orphans = settings.orphanedServicesForImport(in: persisted)
            if !orphans.isEmpty {
                pendingData = data
                pendingOrphans = orphans
                pendingTotalProtected = persisted.minimalEncryptedServices.count
                isFetching = false
                showingImportChoice = true
                return
            }
            await apply(data: data, droppingOrphans: false, peer: peer)
        } catch {
            isFetching = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(data: Data, droppingOrphans: Bool, peer: DiscoveredSyncPeer? = nil) async {
        let targetPeer = peer ?? selectedPeer
        do {
            if droppingOrphans {
                try ConfigPortManager.importConfig(from: data, droppingOrphans: true)
            } else {
                try ConfigPortManager.importConfig(from: data)
            }
            pendingData = nil
            isFetching = false
            let name = targetPeer?.displayName ?? selectedPeer?.displayName ?? "device"
            successMessage = "Sync complete from \(name). Tap Done to return."
            appController?.reloadServices()
            browser.stop()
            if let targetPeer {
                await QuiperSyncClient.sendAck(to: targetPeer.endpoint)
            } else if let selectedPeer {
                await QuiperSyncClient.sendAck(to: selectedPeer.endpoint)
            }
        } catch {
            isFetching = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
