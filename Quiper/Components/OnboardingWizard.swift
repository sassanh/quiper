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
    @State private var isProcessing: Bool = false
    @State private var statusText: String = ""
    
    @ObservedObject private var settings = Settings.shared
    
    init(hasLegacyData: Bool, window: NSWindow?, completion: @escaping () -> Void) {
        self.hasLegacyData = hasLegacyData
        self.window = window
        self.completion = completion
        // Every bundled engine starts selected; the first step lets the user
        // drop the ones they never want added at all.
        self._selectedEngines = State(initialValue: Set(Settings.shared.services.map { $0.id }))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isProcessing {
                processingView
            } else {
                switch currentStep {
                case 0:
                    if hasLegacyData {
                        legacyDataStepView
                    } else {
                        engineSetupStepView
                    }
                case 1:
                    engineSetupStepView
                default:
                    EmptyView()
                }
            }
        }
        .frame(width: 560, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var engineSetupStepView: some View {
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

            Text("Tick the engines you want to add — unticked ones are skipped and can be added later from Settings → Engines. The lock switch isolates that engine's sessions in secure encrypted storage.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AlwaysVisibleScrollView(width: 480, minHeight: 200) {
                VStack(spacing: 8) {
                    ForEach(orderedServices) { service in
                        let isIncluded = selectedEngines.contains(service.id)
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { isIncluded },
                                set: { selected in
                                    if selected {
                                        selectedEngines.insert(service.id)
                                    } else {
                                        selectedEngines.remove(service.id)
                                        selectedSecureServices.remove(service.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(service.url)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isIncluded {
                                    selectedEngines.remove(service.id)
                                    selectedSecureServices.remove(service.id)
                                } else {
                                    selectedEngines.insert(service.id)
                                }
                            }
                            Spacer()
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
                            .disabled(!isIncluded)
                            .help("Isolate in secure encrypted sandbox")
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
                    }
                }
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

                Button("Complete Setup") {
                    runSetup()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
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

            // 2. Drop the engines the user did not select.
            settings.services.removeAll { !selectedEngines.contains($0.id) }

            // 3. Configure encryption for chosen engines
            for serviceID in selectedSecureServices {
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
