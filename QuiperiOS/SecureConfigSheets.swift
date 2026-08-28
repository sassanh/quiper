import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Choice

struct SecureExportChoiceSheet: View {
    let encryptedCount: Int
    @Binding var selection: SecureExportChoice
    var onCancel: () -> Void
    var onExport: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    options
                }
                .padding(24)
            }
            .navigationTitle("Protected Engines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export", action: onExport)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Export Includes Protected Engines")
                .font(.title2.bold())
            Text(encryptedCount == 1
                 ? "One of your engines uses Secure Storage. Its data is encrypted on this device and tied to its secure bundle."
                 : "\(encryptedCount) of your engines use Secure Storage. Their data is encrypted on this device and tied to their secure bundles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose how to handle them. This choice only affects the exported file — your engines on this device stay exactly as they are.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var options: some View {
        VStack(spacing: 12) {
            choiceCard(
                title: "Keep Locked",
                subtitle: "This Device Only",
                description: "Protected engines stay as locked placeholders. The file restores perfectly here while their bundles remain, but on another device they’ll appear locked and empty.",
                systemImage: "lock.fill",
                isSelected: selection == .keepLocked
            ) {
                selection = .keepLocked
            }
            choiceCard(
                title: "Decrypt for Migration",
                subtitle: "Use Anywhere",
                description: "Unlock each protected engine so its full configuration is included unprotected. You’ll authenticate for each locked engine. The file will then import anywhere as regular engines.",
                systemImage: "lock.open.fill",
                isSelected: selection == .decryptForMigration
            ) {
                selection = .decryptForMigration
            }
            choiceCard(
                title: "Exclude Protected",
                subtitle: "Skip Them",
                description: "Don’t include protected engines at all. Only unprotected engines will be in the export.",
                systemImage: "eye.slash.fill",
                isSelected: selection == .exclude
            ) {
                selection = .exclude
            }
        }
    }

    private func choiceCard(title: String, subtitle: String, description: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.8 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title) \(subtitle)")
    }
}

// MARK: - Export Progress

enum SecureExportProgressStatus {
    case pending
    case unlocking
    case done
    case skipped
    case failed(String)
}

struct SecureExportProgressItem: Identifiable {
    let id: UUID
    let name: String
    var status: SecureExportProgressStatus = .pending
}

struct SecureExportProgressSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    let items: [Service]
    var onComplete: ([AppEnvironment.DecryptedEngineForExport]) -> Void
    var onCancel: () -> Void

    @State private var progressItems: [SecureExportProgressItem]
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var hasStarted = false

    init(services: [Service], onComplete: @escaping ([AppEnvironment.DecryptedEngineForExport]) -> Void, onCancel: @escaping () -> Void) {
        self.items = services
        self.onComplete = onComplete
        self.onCancel = onCancel
        _progressItems = State(initialValue: services.map { SecureExportProgressItem(id: $0.id, name: $0.name) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        ForEach($progressItems) { $item in
                            progressRow(item: item)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 8)
                        }
                    }
                    .padding(24)
                }
                Divider()
                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .disabled(isWorking)
                    Spacer()
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Decrypting for Export")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isWorking)
            .task {
                guard !hasStarted else { return }
                hasStarted = true
                await runDecryption()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lock.open.display")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
            Text("Unlocking Protected Engines")
                .font(.headline)
            Text("You’ll be asked to authenticate for each locked engine. Engines already unlocked are included automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressRow(item: SecureExportProgressItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                switch item.status {
                case .pending:
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                case .unlocking:
                    ProgressView()
                        .controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .skipped:
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 24, height: 24)

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(statusText(for: item.status))
                .font(.caption)
                .foregroundStyle(statusColor(for: item.status))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func statusText(for status: SecureExportProgressStatus) -> String {
        switch status {
        case .pending: return "Waiting"
        case .unlocking: return "Unlocking…"
        case .done: return "Included"
        case .skipped: return "Skipped"
        case .failed(let msg): return msg
        }
    }

    private func statusColor(for status: SecureExportProgressStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .unlocking: return .secondary
        case .done: return .green
        case .skipped: return .secondary
        case .failed: return .red
        }
    }

    private func runDecryption() async {
        isWorking = true
        var decrypted: [AppEnvironment.DecryptedEngineForExport] = []
        for index in progressItems.indices {
            let serviceID = progressItems[index].id
            // Check current lock state at iteration time (may have timed out)
            if environment.isServiceLocked(serviceID) {
                progressItems[index].status = .unlocking
                do {
                    let engine = try await environment.decryptedServiceForExport(serviceID: serviceID)
                    decrypted.append(engine)
                    progressItems[index].status = .done
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    if message.lowercased().contains("cancel") {
                        progressItems[index].status = .failed("Cancelled")
                        errorMessage = "Export cancelled. No file was created."
                        isWorking = false
                        return
                    }
                    progressItems[index].status = .failed("Failed")
                    errorMessage = "Couldn’t decrypt \(progressItems[index].name): \(message)"
                    isWorking = false
                    return
                }
            } else {
                // Already unlocked – just take decrypted copy with current tab state
                if let service = environment.services.first(where: { $0.id == serviceID }) {
                    let tabState = IOSSecuredTabState(serviceID: serviceID, state: environment.persistedTabState)
                    let hasTabs = !(environment.persistedTabState.openTabs[serviceID]?.isEmpty ?? true)
                    let engine = AppEnvironment.DecryptedEngineForExport(
                        service: service.decryptedForExport,
                        tabState: hasTabs ? tabState : nil
                    )
                    decrypted.append(engine)
                    progressItems[index].status = .done
                } else {
                    progressItems[index].status = .skipped
                }
            }
            // Small delay to let UI update and to respect system auth sheet dismissal
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        isWorking = false
        // Brief success pause so user sees completion
        try? await Task.sleep(nanoseconds: 400_000_000)
        onComplete(decrypted)
    }
}

// MARK: - Import Choice

struct SecureImportChoiceSheet: View {
    let orphanCount: Int
    let totalProtectedCount: Int
    var onKeep: () -> Void
    var onDrop: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    options
                    note
                }
                .padding(24)
            }
            .navigationTitle("Protected Engines in Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("This Backup Contains Locked Engines")
                .font(.title2.bold())
            Text(orphanCount == 1
                 ? "One protected engine in this file has no secure storage on this device. It was exported as a locked placeholder."
                 : "\(orphanCount) protected engines in this file have no secure storage on this device. They were exported as locked placeholders.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("They would appear locked and empty, and you’d need their original bundles to use them. How would you like to proceed?")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var options: some View {
        VStack(spacing: 12) {
            Button(action: onKeep) {
                importOptionRow(
                    title: "Import Anyway",
                    description: orphanCount == 1
                        ? "Keep the locked engine. It will stay in your library but remain unusable here."
                        : "Keep \(orphanCount) locked placeholders. They’ll stay in your library but remain unusable here.",
                    icon: "lock.fill",
                    accent: Color.secondary
                )
            }
            .buttonStyle(.plain)

            Button(action: onDrop) {
                importOptionRow(
                    title: "Skip Protected Engines",
                    description: orphanCount == totalProtectedCount
                        ? "Import everything except the protected engines."
                        : "Import everything except the \(orphanCount) unusable protected \(orphanCount == 1 ? "engine" : "engines").",
                    icon: "eye.slash.fill",
                    accent: Color.accentColor
                )
            }
            .buttonStyle(.plain)

            Button(role: .cancel, action: onCancel) {
                importOptionRow(
                    title: "Cancel Import",
                    description: "Leave your current engines and settings exactly as they are.",
                    icon: "xmark.circle.fill",
                    accent: Color.red
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var note: some View {
        Text("You can always re-import the file later and choose a different option. Your current configuration won’t be changed until you confirm.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func importOptionRow(title: String, description: String, icon: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
