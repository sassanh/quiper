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
        self.isOpaque = false
        self.backgroundColor = .clear
        self.title = "Welcome to Quiper"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
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
            || ProcessInfo.processInfo.arguments.contains("--uitesting")
    }
    
    @MainActor
    public static var needsOnboarding: Bool {
        if isTesting { return false }
        
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
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
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
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
    @State private var selectedMigrationServices: Set<UUID> = []
    @State private var selectedSecureServices: Set<UUID> = []
    @State private var isProcessing: Bool = false
    @State private var statusText: String = ""
    
    @ObservedObject private var settings = Settings.shared
    
    init(hasLegacyData: Bool, window: NSWindow?, completion: @escaping () -> Void) {
        self.hasLegacyData = hasLegacyData
        self.window = window
        self.completion = completion
        
        // Default select all configured services for migration
        let services = Settings.shared.services
        _selectedMigrationServices = State(initialValue: Set(services.map { $0.id }))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isProcessing {
                processingView
            } else {
                switch currentStep {
                case 0:
                    if hasLegacyData {
                        migrationStepView
                    } else {
                        secureSetupStepView
                    }
                case 1:
                    secureSetupStepView
                default:
                    EmptyView()
                }
            }
        }
        .frame(width: 560, height: 420)
        .preferredColorScheme(.dark)
    }
    
    private var migrationStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Migrate Your Sessions")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Quiper 4.0 Onboarding")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 24)
            
            Text("Quiper 4.0 introduces strict per-engine privacy isolation. We detected shared logins and cookies from your previous version of Quiper. Select which engines should inherit these active sessions so you don't have to sign in again:")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(settings.services) { service in
                        HStack {
                            Text(service.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { selectedMigrationServices.contains(service.id) },
                                set: { selected in
                                    if selected {
                                        selectedMigrationServices.insert(service.id)
                                    } else {
                                        selectedMigrationServices.remove(service.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 180)
            
            Spacer()
            
            HStack {
                Button("Skip Migration") {
                    selectedMigrationServices.removeAll()
                    currentStep = 1
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Migrate & Next") {
                    currentStep = 1
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }
    
    private var secureSetupStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Secure Your Engines")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Biometric APFS Sandboxing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 24)
            
            Text("Would you like to lock any sensitive engines behind TouchID? Quiper will encrypt their sessions inside isolated, AES-256 APFS virtual disks that auto-lock when inactive.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(settings.services) { service in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Isolate in secure encrypted sandbox")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
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
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 180)
            
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
            let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
            
            let legacyWebDir = libraryURL
                .appendingPathComponent("WebKit")
                .appendingPathComponent(bundleID)
                .appendingPathComponent("WebsiteData")
            
            let dataStoreDir = libraryURL
                .appendingPathComponent("WebKit")
                .appendingPathComponent(bundleID)
                .appendingPathComponent("WebsiteDataStore")
            
            // 1. Create Data Store directory
            try? fileManager.createDirectory(at: dataStoreDir, withIntermediateDirectories: true, attributes: nil)
            
            // 2. Perform legacy migration if selected
            if hasLegacyData && !selectedMigrationServices.isEmpty {
                for serviceID in selectedMigrationServices {
                    if let service = settings.services.first(where: { $0.id == serviceID }) {
                        statusText = "Migrating sessions to \(service.name)..."
                        let destDir = dataStoreDir.appendingPathComponent(serviceID.uuidString.lowercased())
                        try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                        
                        copyDirectory(from: legacyWebDir, to: destDir)
                    }
                }
            }
            
            // 3. Configure encryption for chosen engines
            for serviceID in selectedSecureServices {
                if let idx = settings.services.firstIndex(where: { $0.id == serviceID }) {
                    let serviceName = settings.services[idx].name
                    statusText = "Securing \(serviceName)..."
                    
                    let randomKey = SecureStorageManager.shared.generateRandomKey()
                    _ = SecureStorageManager.shared.saveKeyToKeychain(randomKey, for: serviceID)
                    
                    do {
                        try await EncryptedVolumeManager.shared.createVolume(for: serviceID, passphrase: randomKey)
                        settings.services[idx].isEncrypted = true
                    } catch {
                        NSLog("[Onboarding] Failed to secure volume for \(serviceName): \(error)")
                    }
                }
            }
            
            // 4. Clean up legacy data directory to free up disk space and enforce security
            if hasLegacyData {
                statusText = "Cleaning up legacy storage..."
                try? fileManager.removeItem(at: legacyWebDir)
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
    
    private func copyDirectory(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
        
        for url in contents {
            let destUrl = destination.appendingPathComponent(url.lastPathComponent)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    try? fileManager.createDirectory(at: destUrl, withIntermediateDirectories: true, attributes: nil)
                    copyDirectory(from: url, to: destUrl)
                } else {
                    if fileManager.fileExists(atPath: destUrl.path) {
                        try? fileManager.removeItem(at: destUrl)
                    }
                    // Use try? to prevent a single locked cache file from aborting the entire session migration
                    try? fileManager.copyItem(at: url, to: destUrl)
                }
            }
        }
    }
}
