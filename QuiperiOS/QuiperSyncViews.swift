import SwiftUI
import Network

// MARK: - Provider sheet (iOS)

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusCard
                    transfersList
                    info
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        provider.stop()
                        onDone()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { provider.start() }
        .onDisappear { provider.stop() }
    }

    private var transfersList: some View {
        Group {
            if !provider.transfers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Successful Transfers").font(.headline)
                    ForEach(provider.transfers) { transfer in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transfer.peerName).font(.subheadline.weight(.medium))
                                Text(transfer.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Delivered").font(.caption.weight(.medium)).foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.25), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sharing Settings")
                        .font(.title3.bold())
                    Text(provider.isAdvertising ? "Visible on local network" : "Starting…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView().controlSize(.small).opacity(provider.isAdvertising ? 1 : 0.6)
            }
            Text("Keep this screen open while the other device discovers and pulls your config. Your settings on this device do not change.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !provider.isAdvertising && provider.errorMessage == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for local network permission…")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text("If this stays, check Settings → Privacy → Local Network and allow Quiper. The system dialog may be hidden behind this window.")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
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
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On the other device, open Settings → Config → Sync → Receive and select this device.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Provider setup

struct QuiperSyncProviderSetupSheet: View {
    var onCancel: () -> Void
    var onReady: (Data) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: SecureExportChoice = .decryptForMigration
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingDecryptProgress = false

    private var encryptedServices: [Service] {
        environment.services.filter { $0.isEncrypted }
    }

    private var unavailableServices: [Service] {
        encryptedServices.filter { !environment.hasLocalSecureData(for: $0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 24)).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Settings").font(.title3.bold())
                            Text(encryptedServices.isEmpty ? "No protected engines" : "\(encryptedServices.count) protected")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("Choose how protected engines are shared. Receivers pull a snapshot taken now.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    if !encryptedServices.isEmpty {
                        choiceCard(title: "Decrypt for Migration", subtitle: "Use Anywhere", description: "Unlock each protected engine so receivers get full config.", icon: "lock.open.fill", selected: selection == .decryptForMigration) { selection = .decryptForMigration }
                        choiceCard(title: "Exclude Protected", subtitle: "Skip Them", description: "Receivers get only unprotected engines.", icon: "eye.slash.fill", selected: selection == .exclude) { selection = .exclude }
                        if !unavailableServices.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(unavailableServices.count) protected engine\(unavailableServices.count == 1 ? "" : "s") have no local secure data and cannot be decrypted.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                ForEach(unavailableServices, id: \.id) { svc in
                                    Text("• \(svc.name)").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Choose Exclude to skip them.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        }
                    }
                    if isWorking {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Preparing snapshot…").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                            Text("Reading engines and requesting Local Network access. If this stays more than a few seconds, check Settings → Privacy → Local Network and allow Quiper — the system dialog may be hidden behind this window.")
                                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onCancel).disabled(isWorking || showingDecryptProgress) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Sharing") { Task { await prepareAndShare() } }
                        .fontWeight(.semibold).disabled(isWorking || showingDecryptProgress)
                }
            }
        }
        .overlay {
            if showingDecryptProgress {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    SecureExportProgressSheet(
                        services: encryptedServices,
                        onComplete: { decrypted in
                            showingDecryptProgress = false
                            Task {
                                do {
                                    var payload = environment.makePersistedSettingsForExport(secureChoice: .decryptForMigration, decryptedEngines: decrypted)
                                    ConfigPortability.inlineFileScripts(into: &payload)
                                    let data = try ConfigPortability.encode(payload)
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
                    .environmentObject(environment)
                    .frame(maxWidth: 400)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(radius: 20))
                    .padding(24)
                }
            }
        }
    }

    private func choiceCard(title: String, subtitle: String, description: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(selected ? .blue : .secondary).frame(width: 26, height: 26).background(Circle().fill(selected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline).foregroundStyle(Color.primary)
                        Text(subtitle).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.secondary.opacity(0.12))).foregroundStyle(.secondary)
                    }
                    Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(selected ? .blue : .secondary.opacity(0.4))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.blue : Color(.separator), lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private func prepareAndShare() async {
        errorMessage = nil
        if !encryptedServices.isEmpty && selection == .decryptForMigration {
            showingDecryptProgress = true
            return
        }
        isWorking = true
        environment.syncPreparationDetail = "Reading engines…"
        defer {
            isWorking = false
            if errorMessage != nil { environment.syncPreparationDetail = nil }
        }
        do {
            let data: Data
            if encryptedServices.isEmpty {
                environment.syncPreparationDetail = "Inlining scripts…"
                data = try environment.exportConfiguration()
                environment.syncPreparationDetail = "Encoding snapshot…"
            } else {
                environment.syncPreparationDetail = "Inlining scripts…"
                data = try await environment.exportConfiguration(secureChoice: .exclude)
                environment.syncPreparationDetail = "Encoding snapshot…"
            }
            environment.syncPreparationDetail = "Starting local network…"
            onReady(data)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if environment.syncPreparationDetail == "Starting local network…" {
                    environment.syncPreparationDetail = nil
                }
            }
        } catch {
            environment.syncPreparationDetail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Browser

struct QuiperSyncBrowserSheet: View {
    var onClose: () -> Void
    var onSuccess: (() -> Void)? = nil

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var sheetDismiss
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if browser.isBrowsing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Scanning local network…").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") { browser.refresh() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    } else if let error = browser.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if browser.peers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.system(size: 24)).foregroundStyle(.secondary)
                            Text("No devices sharing nearby").font(.callout).foregroundStyle(.secondary)
                            Text("On the other device, open Settings → Config → Sync → Share. Both must be on the same Wi-Fi and have Local Network access allowed.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ForEach(browser.peers) { peer in peerRow(peer) }
                    }

                    if isFetching {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Syncing from \(selectedPeer?.displayName ?? "device")…").font(.caption).foregroundStyle(.secondary)
                            }
                            if let progress = fetchProgress {
                                ProgressView(value: progress).progressViewStyle(.linear)
                            } else {
                                ProgressView().progressViewStyle(.linear)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    }

                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                    if let successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(successMessage).font(.callout.weight(.medium)).foregroundStyle(.green)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(successMessage != nil ? "Done" : "Close") {
                        browser.stop()
                        let wasSuccess = successMessage != nil
                        onClose()
                        if wasSuccess {
                            sheetDismiss()
                            onSuccess?()
                        }
                    }
                }
            }
        }
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
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill").font(.system(size: 28)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive Settings").font(.title3.bold())
                    Text("Choose a nearby sharer").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Select a device that is currently sharing. Sync replaces your settings with theirs after you confirm. The sharing device does not change.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func peerRow(_ peer: DiscoveredSyncPeer) -> some View {
        let isSelected = selectedPeer?.id == peer.id
        let isFetchingThis = isFetching && isSelected
        return HStack(spacing: 12) {
            Image(systemName: "iphone.gen1").font(.system(size: 18)).foregroundStyle(.blue).frame(width: 28, height: 28).background(Circle().fill(Color.blue.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName).font(.headline).lineLimit(1)
                Text(peer.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            .buttonStyle(.borderedProminent).tint(.blue).disabled(isFetching).controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color(.separator), lineWidth: isSelected ? 1.5 : 0.5))
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
            let orphans = environment.orphanedServicesForImport(in: persisted)
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
                try environment.importConfiguration(from: data, droppingOrphans: true)
            } else {
                try environment.importConfiguration(from: data)
            }
            pendingData = nil
            isFetching = false
            let name = targetPeer?.displayName ?? selectedPeer?.displayName ?? "device"
            successMessage = "Sync complete from \(name). Tap Done to return."
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
