import SwiftUI
import LocalAuthentication

// MARK: - Export Choice

struct SecureExportChoiceSheet: View {
    let encryptedCount: Int
    @Binding var selection: SecureExportChoice
    var onCancel: () -> Void
    var onExport: () -> Void

    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    options
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export", action: onExport)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.settingsResolved)
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.blue.settingsResolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protected Engines in Export")
                        .font(.title3.bold())
                    Text(encryptedCount == 1
                         ? "One engine uses Secure Storage"
                         : "\(encryptedCount) engines use Secure Storage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Secure Storage keeps engine details encrypted on this Mac and tied to its secure bundle. Choose how to include them — your engines on this Mac stay exactly as they are.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var options: some View {
        VStack(spacing: 10) {
            choiceCard(
                title: "Keep Locked",
                subtitle: "This Mac Only",
                description: "Export protected engines as locked placeholders. They restore perfectly here while their bundles remain, but on another Mac they’ll appear locked and empty.",
                icon: "lock.fill",
                isSelected: selection == .keepLocked
            ) { selection = .keepLocked }

            choiceCard(
                title: "Decrypt for Migration",
                subtitle: "Use Anywhere",
                description: "Unlock each protected engine so its full configuration is included unprotected. You’ll authenticate for each locked engine. The file can then be imported anywhere as regular engines.",
                icon: "lock.open.fill",
                isSelected: selection == .decryptForMigration
            ) { selection = .decryptForMigration }

            choiceCard(
                title: "Exclude Protected",
                subtitle: "Skip Them",
                description: "Don’t include protected engines at all. Only unprotected engines will be in the export.",
                icon: "eye.slash.fill",
                isSelected: selection == .exclude
            ) { selection = .exclude }
        }
    }

    private func choiceCard(title: String, subtitle: String, description: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.blue.settingsResolved : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isSelected ? Color.blue.settingsResolved.opacity(0.12) : Color.secondary.opacity(0.08)))
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
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.blue.settingsResolved : Color.secondary.opacity(0.4))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.blue.settingsResolved : Color(NSColor.separatorColor), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Export Progress Panel (separate window, not a sheet, to avoid sheet-on-sheet conflict)

@MainActor
final class SecureExportProgressPanel {
    private let panel: NSPanel
    private var hostingView: NSHostingView<SecureExportProgressSheet>?

    init(services: [Service], onComplete: @escaping ([Settings.DecryptedEngineForExport]) -> Void, onCancel: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Decrypting for Export"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.center()

        let view = SecureExportProgressSheet(services: services, onComplete: { decrypted in
            self.close()
            onComplete(decrypted)
        }, onCancel: {
            self.close()
            onCancel()
        })
        hostingView = NSHostingView(rootView: view)
        hostingView?.frame = panel.contentView?.bounds ?? .zero
        hostingView?.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }
}

// MARK: - Export Progress

struct SecureExportProgressSheet: View {
    let services: [Service]
    var onComplete: ([Settings.DecryptedEngineForExport]) -> Void
    var onCancel: () -> Void

    @State private var items: [SecureExportProgressItem]
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var hasStarted = false

    init(services: [Service], onComplete: @escaping ([Settings.DecryptedEngineForExport]) -> Void, onCancel: @escaping () -> Void) {
        self.services = services
        self.onComplete = onComplete
        self.onCancel = onCancel
        _items = State(initialValue: services.map { SecureExportProgressItem(id: $0.id, name: $0.name) })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.display")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.blue.settingsResolved)
                            Text("Decrypting for Export")
                                .font(.headline)
                        }
                        Text("You’ll be asked to authenticate for each locked engine. Engines already unlocked are included automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach($items) { $item in
                        HStack(spacing: 10) {
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
                            .frame(width: 22, height: 22)
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(statusText(for: item.status))
                                .font(.caption)
                                .foregroundStyle(statusColor(for: item.status))
                        }
                        .padding(.vertical, 2)
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
        .frame(width: 460, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
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
        case .pending, .unlocking, .skipped: return .secondary
        case .done: return .green
        case .failed: return .red
        }
    }

    private func run() async {
        isWorking = true
        var decrypted: [Settings.DecryptedEngineForExport] = []
        for index in items.indices {
            let id = items[index].id
            let service = services[index]
            guard service.isEncrypted else {
                items[index].status = .skipped
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }
            let isLocked = !(EncryptedVolumeManager.shared.isUnlocked(for: id))
            let needsAuth = service.hasMigratedMetadata && isLocked
            if needsAuth {
                items[index].status = .unlocking
            } else {
                // Already unlocked – still show unlocking briefly for consistency if we need to read tabs
                items[index].status = .unlocking
            }
            do {
                let engine = try await Settings.shared.decryptedServiceForExport(serviceID: id)
                decrypted.append(engine)
                items[index].status = .done
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if msg.lowercased().contains("cancel") {
                    items[index].status = .failed("Cancelled")
                    errorMessage = "Export cancelled. No file was created."
                    isWorking = false
                    return
                }
                items[index].status = .failed("Failed")
                errorMessage = "Couldn’t decrypt \(items[index].name): \(msg)"
                isWorking = false
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        isWorking = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        onComplete(decrypted)
    }
}

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

// MARK: - Import Choice

struct SecureImportChoiceSheet: View {
    let orphanCount: Int
    let totalProtectedCount: Int
    var onKeep: () -> Void
    var onDrop: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Protected Engines in Import")
                                    .font(.title3.bold())
                                Text(orphanCount == 1 ? "1 locked engine has no bundle here" : "\(orphanCount) locked engines have no bundle here")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(orphanCount == 1
                             ? "This backup contains a protected engine that was exported as a locked placeholder. It has no secure storage on this Mac and would appear locked and empty."
                             : "This backup contains \(orphanCount) protected engines that were exported as locked placeholders. They have no secure storage on this Mac and would appear locked and empty.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("How would you like to proceed? Your current engines stay untouched until you choose.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        Button(action: onKeep) {
                            importRow(title: "Import Anyway", description: orphanCount == 1 ? "Keep the locked engine. It will stay in your library but remain unusable here." : "Keep \(orphanCount) locked placeholders. They’ll stay in your library but remain unusable here.", icon: "lock.fill", accent: Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDrop) {
                            importRow(title: "Skip Protected Engines", description: orphanCount == totalProtectedCount ? "Import everything except the protected engines." : "Import everything except the \(orphanCount) unusable protected \(orphanCount == 1 ? "engine" : "engines").", icon: "eye.slash.fill", accent: Color.blue.settingsResolved)
                        }
                        .buttonStyle(.plain)

                        Button(role: .cancel, action: onCancel) {
                            importRow(title: "Cancel Import", description: "Leave your current engines and settings exactly as they are.", icon: "xmark.circle.fill", accent: Color.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func importRow(title: String, description: String, icon: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}
