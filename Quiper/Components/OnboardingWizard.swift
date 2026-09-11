import AppKit
import SwiftUI
import WebKit

@MainActor
class OnboardingWizardWindow: NSWindow {
    private var hostingController: NSHostingController<OnboardingWizardView>?
    private var completion: () -> Void
    
    init(hasLegacyData: Bool, completion: @escaping () -> Void) {
        self.completion = completion
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.collectionBehavior = [.moveToActiveSpace, .stationary]
        self.title = "Welcome to Quiper"
        self.center()
        
        let rootView = OnboardingWizardView(hasLegacyData: hasLegacyData, window: self, completion: completion)
        let hc = NSHostingController(rootView: rootView)
        self.hostingController = hc
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        let effectView = NSVisualEffectView(frame: contentView.bounds)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        contentView.addSubview(effectView)
        
        hc.view.frame = contentView.bounds
        hc.view.autoresizingMask = [.width, .height]
        contentView.addSubview(hc.view)
        
        self.contentView = contentView
    }
}

public struct OnboardingWizard {
    @MainActor private static var activeWindow: OnboardingWizardWindow?
    
    private static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Constants.LaunchMode.shouldSuppressInterferenceUI
    }
    
    @MainActor
    public static var needsOnboarding: Bool {
        if isTesting { return false }
        
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        let bundleID = Constants.BUNDLE_ID
        let newStoreURL = libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")
        
        return !FileManager.default.fileExists(atPath: newStoreURL.path)
    }
    
    @MainActor
    public static var hasLegacyData: Bool {
        if isTesting { return false }
        
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        let bundleID = Constants.BUNDLE_ID
        let oldStoreURL = libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteData")
        
        return FileManager.default.fileExists(atPath: oldStoreURL.path)
    }
    
    @MainActor
    public static func show(completion: @escaping () -> Void) {
        let window = OnboardingWizardWindow(hasLegacyData: hasLegacyData, completion: completion)
        activeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    fileprivate static func dismiss() {
        activeWindow?.close()
        activeWindow = nil
    }
}

struct OnboardingWizardView: View {
    let hasLegacyData: Bool
    weak var window: NSWindow?
    let completion: () -> Void
    
    @State private var currentStep: Int = 0
    @State private var deleteLegacyData: Bool = true
    @State private var selectedEngines: Set<UUID>
    @State private var selectedSecureServices: Set<UUID> = []
    @State private var launchShortcuts: [UUID: HotkeyManager.Configuration]
    @StateObject private var shortcutRecorder = ShortcutRecordingState()
    @State private var isProcessing: Bool = false
    @State private var statusText: String = ""
    
    @ObservedObject private var settings = Settings.shared
    
    init(hasLegacyData: Bool, window: NSWindow?, completion: @escaping () -> Void) {
        self.hasLegacyData = hasLegacyData
        self.window = window
        self.completion = completion
        // Every engine starts unselected; the first step lets the user
        // pick the ones they want added at all.
        self._selectedEngines = State(initialValue: [])
        // Seed editable shortcuts from the bundled defaults so the second
        // page shows each engine's global shortcut up front.
        var shortcuts: [UUID: HotkeyManager.Configuration] = [:]
        for service in Settings.shared.services {
            if let shortcut = service.activationShortcut {
                shortcuts[service.id] = shortcut
            }
        }
        self._launchShortcuts = State(initialValue: shortcuts)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if isProcessing {
                    processingView
                } else {
                    switch currentStep {
                    case 0:
                        if hasLegacyData {
                            legacyDataStepView
                        } else {
                            engineSelectionStepView
                        }
                    case 1:
                        if hasLegacyData {
                            engineSelectionStepView
                        } else {
                            engineShortcutsStepView
                        }
                    default:
                        engineShortcutsStepView
                    }
                }
            }
            .frame(width: 560, height: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            ShortcutRecordingOverlay(state: shortcutRecorder)
        }
        .frame(width: 560, height: 420)
    }
    
    private var legacyDataStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Legacy Data Detected")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Quiper 4.0 Architecture Upgrade")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 24)
            
            Text("To support multiple accounts and enhanced encryption, Quiper has upgraded to a new isolated engine architecture. Unfortunately, this means your previous sessions and logins could not be automatically migrated, and you will need to sign back in to your services.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Securely delete old application data (Recommended)", isOn: $deleteLegacyData)
                    .font(.body)
                    .toggleStyle(.checkbox)
                
                Text("If you disable this, we will leave your old data on disk so you can access it by downloading an older version of Quiper.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
                
                Button("Show Legacy Data in Finder") {
                    if let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                        let bundleID = Constants.BUNDLE_ID
                        let oldStoreURL = libraryURL
                            .appendingPathComponent("WebKit")
                            .appendingPathComponent(bundleID)
                            .appendingPathComponent("WebsiteData")
                        NSWorkspace.shared.selectFile(oldStoreURL.path, inFileViewerRootedAtPath: oldStoreURL.deletingLastPathComponent().path)
                    }
                }
                .buttonStyle(.link)
                .padding(.leading, 24)
                .padding(.top, 4)
            }
            .padding()
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Acknowledge & Continue") {
                    currentStep = 1
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }
    
    /// Display order for the setup list. Fresh installs happen to seed this
    /// order already, but the wizard must not depend on stored ordering.
    private var orderedServices: [Service] {
        settings.services.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Shows only the host (plus port) so tracking queries never appear.
    private func displayHost(for urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty else { return "" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    private var engineSelectionStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Your Engines")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(selectedEngines.count) of \(settings.services.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("All") {
                    selectedEngines = Set(settings.services.map { $0.id })
                }
                .buttonStyle(.link)
                Button("None") {
                    selectedEngines = []
                    selectedSecureServices = []
                }
                .buttonStyle(.link)
            }
            .padding(.top, 24)

            Text("Tick the engines you want to add — unticked ones are skipped and can be added later from Settings → Engines.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AlwaysVisibleScrollView(width: 480, minHeight: 200) {
                VStack(spacing: 8) {
                    ForEach(orderedServices) { service in
                        let isIncluded = selectedEngines.contains(service.id)
                        HStack {
                            Toggle("", isOn: .constant(isIncluded))
                                .toggleStyle(.checkbox)
                                .allowsHitTesting(false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                let host = displayHost(for: service.url)
                                if !host.isEmpty {
                                    Text(host)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isIncluded ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isIncluded ? Color.accentColor : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isIncluded {
                                selectedEngines.remove(service.id)
                                selectedSecureServices.remove(service.id)
                            } else {
                                selectedEngines.insert(service.id)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                    Spacer(minLength: 0)
                }
                .padding(2)
            }
            .frame(maxHeight: 200)

            Spacer()

            HStack {
                if hasLegacyData {
                    Button("Back") {
                        currentStep = 0
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Continue") {
                    advanceFromSelection()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }

    private var selectedServices: [Service] {
        orderedServices.filter { selectedEngines.contains($0.id) }
    }

    private var engineShortcutsStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcuts & Privacy")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(selectedEngines.count) engines • shortcuts work everywhere in macOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.top, 24)

            Text("Each engine gets a global shortcut. Click one to change it, or clear it to leave the engine without a shortcut. The lock switch isolates that engine in secure encrypted storage.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AlwaysVisibleScrollView(width: 480, minHeight: 200) {
                VStack(spacing: 8) {
                    if selectedServices.isEmpty {
                        Text("No engines selected. Go back to pick at least one, or complete setup with none.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    ForEach(selectedServices) { service in
                        HStack {
                            Text(service.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            ShortcutButton(
                                text: launchShortcuts[service.id].map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                                isPlaceholder: launchShortcuts[service.id] == nil,
                                onTap: { startShortcutCapture(for: service.id) },
                                onClear: launchShortcuts[service.id] != nil ? { clearShortcut(for: service.id) } : nil,
                                onReset: nil,
                                width: 140,
                                axIdentifier: "onboarding_shortcut_\(service.name)"
                            )
                            Toggle("Secure", isOn: Binding(
                                get: { selectedSecureServices.contains(service.id) },
                                set: { selected in
                                    if selected {
                                        selectedSecureServices.insert(service.id)
                                    } else {
                                        selectedSecureServices.remove(service.id)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .help("Isolate in secure encrypted sandbox")
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: 200)

            Spacer()

            HStack {
                Button("Back") {
                    retreatToSelection()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Complete Setup") {
                    runSetup()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }

    private func advanceFromSelection() {
        if hasLegacyData {
            currentStep = 2
        } else {
            currentStep = 1
        }
    }

    private func retreatToSelection() {
        if hasLegacyData {
            currentStep = 1
        } else {
            currentStep = 0
        }
    }

    private func startShortcutCapture(for serviceID: UUID) {
        let serviceName = settings.services.first(where: { $0.id == serviceID })?.name ?? "Service"
        let session = StandardShortcutSession(onUpdate: { update in
            shortcutRecorder.updateMessage(update)
        }, onFinish: {
            shortcutRecorder.cancel()
        }, reservedActionCheck: { configuration in
            MainActor.assumeIsolated {
                reservedShortcutName(configuration, excluding: serviceID)
            }
        }, completion: { configuration in
            if let configuration {
                launchShortcuts[serviceID] = configuration
            }
        })
        shortcutRecorder.start(session: session, title: "Launch \(serviceName)")
    }

    private func clearShortcut(for serviceID: UUID) {
        launchShortcuts.removeValue(forKey: serviceID)
    }

    /// Validates a candidate against the wizard's pending shortcuts plus the
    /// app-wide bindings. Engine clashes use the pending values (not the
    /// still-unwritten Settings) so cleared or reassigned defaults free up.
    private func reservedShortcutName(
        _ configuration: HotkeyManager.Configuration,
        excluding serviceID: UUID
    ) -> String? {
        if launchShortcuts[serviceID] == configuration { return nil }
        for other in selectedServices where other.id != serviceID {
            if launchShortcuts[other.id] == configuration {
                let name = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Activate \(name.isEmpty ? "Service" : name)"
            }
        }
        if configuration == Settings.shared.hotkeyConfiguration { return "Global Shortcut" }
        guard let reserved = ShortcutValidator.reservedActionName(
            modifiers: NSEvent.ModifierFlags(rawValue: configuration.modifierFlags),
            keyCode: UInt16(configuration.keyCode)
        ) else { return nil }
        if reserved.hasPrefix("Activate ") { return nil }
        return reserved
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(statusText)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Quiper is preparing your isolated engines. This will take a moment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func runSetup() {
        isProcessing = true
        statusText = "Initializing storage layout..."
        
        Task {
            let fileManager = FileManager.default
            let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let bundleID = Constants.BUNDLE_ID
            
            let legacyWebDir = libraryURL
                .appendingPathComponent("WebKit")
                .appendingPathComponent(bundleID)
                .appendingPathComponent("WebsiteData")
                
            let dataStoreDir = libraryURL
                .appendingPathComponent("WebKit")
                .appendingPathComponent(bundleID)
                .appendingPathComponent("WebsiteDataStore")
            
            // 1. Create Data Store directory (marks onboarding as complete)
            try? fileManager.createDirectory(at: dataStoreDir, withIntermediateDirectories: true, attributes: nil)

            // 2. Apply the shortcuts reviewed on the second page. A missing
            // entry means the user cleared that engine's shortcut.
            let reviewedShortcuts = launchShortcuts
            let reviewedSecure = selectedSecureServices
            for index in settings.services.indices {
                let id = settings.services[index].id
                guard selectedEngines.contains(id) else { continue }
                settings.services[index].activationShortcut = reviewedShortcuts[id]
            }

            // 3. Drop the engines the user did not select.
            settings.services.removeAll { !selectedEngines.contains($0.id) }

            // 4. Configure encryption for chosen engines
            for serviceID in reviewedSecure {
                if let idx = settings.services.firstIndex(where: { $0.id == serviceID }) {
                    let serviceName = settings.services[idx].name
                    statusText = "Securing \(serviceName)..."

                    do {
                        try await EncryptedVolumeManager.shared.provisionSecureStorage(for: serviceID)
                        settings.services[idx].isEncrypted = true
                        // New engines start migrated: metadata lives in the
                        // bundle from birth, so the legacy-migration prompt
                        // never fires for them. A write failure leaves the
                        // engine legacy and the prompt remains a real fallback.
                        try await EngineMetadataMigrationManager.shared.writeMetadata(
                            SecuredEngineMetadata(from: settings.services[idx]),
                            for: serviceID
                        )
                        settings.services[idx].hasMigratedMetadata = true
                    } catch {
                        NSLog("[Onboarding] Failed to secure volume for \(serviceName): \(error)")
                    }
                }
            }
            
            // 4. Clean up legacy default store data
            if hasLegacyData && deleteLegacyData {
                statusText = "Cleaning up legacy storage..."
                let defaultStore = WKWebsiteDataStore.default()
                let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                await defaultStore.removeData(ofTypes: allTypes, modifiedSince: .distantPast)
                try? fileManager.removeItem(at: legacyWebDir)
                NSLog("[Onboarding] Deleted legacy WebsiteData directory")
            } else if hasLegacyData {
                NSLog("[Onboarding] User opted to keep legacy WebsiteData directory")
            }
            
            // Save settings in single transaction
            settings.saveSettings()
            
            // Setup complete, dismiss onboarding and trigger callback
            statusText = "Setup complete!"
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            OnboardingWizard.dismiss()
            completion()
        }
    }
}
