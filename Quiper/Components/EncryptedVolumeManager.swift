import Foundation

enum SparseBundleFormat: Equatable {
    case legacyHdiutil
    case modernDiskutil
}

@MainActor
final class EncryptedVolumeManager {
    static let shared = EncryptedVolumeManager()
    
    private init() {}
    
    // Mount/unmount operations can be re-entered while awaiting Process completion.
    // Keep one in-flight task per service so duplicate unlock events cannot race.
    private var activeVolumeOperations: [UUID: Task<Void, Error>] = [:]
    
    private let baseStorageDir: URL = {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        
        let baseDir: URL
        if isRunningTests || isUITesting {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            baseDir = tempDir.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(Constants.APP_FOLDER_NAME)
        }
        
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
        return baseDir
    }()
    
    /// Path to the sparsebundle store on host disk
    func getBundleURL(for serviceID: UUID) -> URL {
        return baseStorageDir.appendingPathComponent("EncryptedStores").appendingPathComponent("\(serviceID.uuidString).sparsebundle")
    }
    
    func legacyBackupBundleURL(for serviceID: UUID) -> URL {
        getBundleURL(for: serviceID).appendingPathExtension("hdiutil-backup")
    }
    
    /// Path where the sparsebundle is mounted
    func getMountPointURL(for serviceID: UUID) -> URL {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let bundleID = Constants.BUNDLE_ID
        
        return libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")
            .appendingPathComponent(serviceID.uuidString)
    }
    
    /// Checks if the sparsebundle is physically present on disk
    func bundleExists(for serviceID: UUID) -> Bool {
        let bundlePath = getBundleURL(for: serviceID).path
        return FileManager.default.fileExists(atPath: bundlePath)
    }
    
    /// Detects whether an on-disk sparsebundle should be mounted with diskutil or legacy hdiutil.
    func bundleFormat(for serviceID: UUID) -> SparseBundleFormat? {
        guard bundleExists(for: serviceID) else { return nil }
        
        if Settings.shared.services.first(where: { $0.id == serviceID })?.usesDiskutilSparseBundle == true {
            return .modernDiskutil
        }
        
        return .legacyHdiutil
    }
    
    func hasAnyLegacyBundles(in services: [Service]) -> Bool {
        services.contains { service in
            service.isEncrypted && bundleExists(for: service.id) && !service.usesDiskutilSparseBundle
        }
    }
    
    func markUsesDiskutilSparseBundle(_ serviceID: UUID) {
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == serviceID }) else { return }
        guard !Settings.shared.services[index].usesDiskutilSparseBundle else { return }
        Settings.shared.services[index].usesDiskutilSparseBundle = true
        Settings.shared.saveSettings()
        NSLog("[VolumeManager] Marked service %@ as using diskutil sparsebundle format", serviceID.uuidString)
    }
    
    private var unlockedServiceIDs: Set<UUID> = []
    
    func isUnlocked(for serviceID: UUID) -> Bool {
        return unlockedServiceIDs.contains(serviceID)
    }
    
    func markUnlocked(_ serviceID: UUID) {
        unlockedServiceIDs.insert(serviceID)
    }
    
    func markLocked(_ serviceID: UUID) {
        unlockedServiceIDs.remove(serviceID)
    }
    
    /// Checks if the volume is currently mounted
    func isMounted(for serviceID: UUID) -> Bool {
        let mountPoint = getMountPointURL(for: serviceID).path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mountPoint, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        
        do {
            let url = URL(fileURLWithPath: mountPoint)
            let values = try url.resourceValues(forKeys: [.isVolumeKey])
            return values.isVolume ?? false
        } catch {
            return false
        }
    }
    
    private func volumeName(for serviceID: UUID) -> String {
        Constants.IS_DEV ? "QuiperDevEngine-\(serviceID.uuidString)" : "QuiperEngine-\(serviceID.uuidString)"
    }
    
    /// Creates an encrypted APFS sparsebundle using diskutil.
    func createVolume(for serviceID: UUID, passphrase: String) async throws {
        let bundleURL = getBundleURL(for: serviceID)
        let parentDir = bundleURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
        
        try await runProcessWithStdinPassphrase(
            executable: "/usr/sbin/diskutil",
            arguments: [
                "image", "create", "blank",
                "-size", "5g",
                "--encrypt",
                "--stdinpassphrase",
                "--volumeName", volumeName(for: serviceID),
                "--fs", "APFS",
                bundleURL.path
            ],
            passphrase: passphrase,
            failureLabel: "diskutil image create"
        )
        
        markUsesDiskutilSparseBundle(serviceID)
    }
    
    /// Mounts the encrypted sparsebundle using the passphrase.
    func mountVolume(for serviceID: UUID, passphrase: String) async throws {
        if let activeOperation = activeVolumeOperations[serviceID] {
            try await activeOperation.value
            if isMounted(for: serviceID) {
                markUnlocked(serviceID)
                return
            }
        }
        
        let operation = Task { @MainActor [weak self] in
            guard let self = self else { return }
            try await self.performMountVolume(for: serviceID, passphrase: passphrase)
        }
        activeVolumeOperations[serviceID] = operation
        defer { activeVolumeOperations[serviceID] = nil }
        
        try await operation.value
    }
    
    private func performMountVolume(for serviceID: UUID, passphrase: String) async throws {
        let bundleURL = getBundleURL(for: serviceID)
        let mountPointURL = getMountPointURL(for: serviceID)
        let fileManager = FileManager.default
        
        if isMounted(for: serviceID) {
            markUnlocked(serviceID)
            return
        }
        
        var shouldMigrate = false
        let tempBackupURL = baseStorageDir.appendingPathComponent("MigrationBackup").appendingPathComponent(serviceID.uuidString)
        
        var statInfo = stat()
        if lstat(mountPointURL.path, &statInfo) == 0 {
            let isSymlink = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
            let isDir = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
            
            if isSymlink {
                try? fileManager.removeItem(at: mountPointURL)
            } else if isDir {
                let contents = (try? fileManager.contentsOfDirectory(atPath: mountPointURL.path)) ?? []
                let realContents = contents.filter { $0 != ".DS_Store" && $0 != ".fseventsd" }
                if !realContents.isEmpty {
                    shouldMigrate = true
                    try? fileManager.removeItem(at: tempBackupURL)
                    try? fileManager.createDirectory(at: tempBackupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: mountPointURL, to: tempBackupURL)
                } else {
                    try? fileManager.removeItem(at: mountPointURL)
                }
            } else {
                try? fileManager.removeItem(at: mountPointURL)
            }
        }
        
        try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
        
        let format = bundleFormat(for: serviceID) ?? .legacyHdiutil
        
        do {
            try await attachVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase, format: format)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("resource busy") {
                NSLog("[VolumeManager] Attach reported busy mount point for service %@. Forcing cleanup and retrying once.", serviceID.uuidString)
                try? await ejectVolume(at: mountPointURL)
                try? fileManager.removeItem(at: mountPointURL)
                try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
                try await Task.sleep(nanoseconds: 300_000_000)
                try await attachVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase, format: format)
            } else {
                throw error
            }
        }
        
        if shouldMigrate {
            NSLog("[VolumeManager] Migrating unencrypted data into secure volume for service %@", serviceID.uuidString)
            let items = (try? fileManager.contentsOfDirectory(at: tempBackupURL, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                let destItemURL = mountPointURL.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: destItemURL.path) {
                    try? fileManager.removeItem(at: destItemURL)
                }
                try? fileManager.moveItem(at: item, to: destItemURL)
            }
            try? fileManager.removeItem(at: tempBackupURL)
        }
        
        markUnlocked(serviceID)
    }
    
    /// Unmounts the volume
    func unmountVolume(for serviceID: UUID) async throws {
        if let activeOperation = activeVolumeOperations[serviceID] {
            try await activeOperation.value
            if !isMounted(for: serviceID) {
                markLocked(serviceID)
                return
            }
        }
        
        let operation = Task { @MainActor [weak self] in
            guard let self = self else { return }
            try await self.performUnmountVolume(for: serviceID)
        }
        activeVolumeOperations[serviceID] = operation
        defer { activeVolumeOperations[serviceID] = nil }
        
        try await operation.value
    }
    
    private func performUnmountVolume(for serviceID: UUID) async throws {
        let mountPointURL = getMountPointURL(for: serviceID)
        
        guard isMounted(for: serviceID) else {
            markLocked(serviceID)
            return
        }
        
        try await ejectVolume(at: mountPointURL)
        
        try? FileManager.default.removeItem(at: mountPointURL)
        markLocked(serviceID)
    }
    
    /// Securely removes the sparsebundle storage from disk when encryption is disabled or service is deleted
    func deleteVolume(for serviceID: UUID) {
        markLocked(serviceID)
        let bundleURL = getBundleURL(for: serviceID)
        try? FileManager.default.removeItem(at: bundleURL)
        try? FileManager.default.removeItem(at: legacyBackupBundleURL(for: serviceID))
        
        let mountPointURL = getMountPointURL(for: serviceID)
        try? FileManager.default.removeItem(at: mountPointURL)
    }
    
    private func attachVolume(
        bundleURL: URL,
        mountPointURL: URL,
        passphrase: String,
        format: SparseBundleFormat
    ) async throws {
        switch format {
        case .legacyHdiutil:
            try await attachLegacyVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
        case .modernDiskutil:
            do {
                try await attachModernVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("incorrect passphrase") {
                    NSLog("[VolumeManager] diskutil attach reported incorrect passphrase; retrying with legacy hdiutil attach")
                    try await attachLegacyVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
                } else {
                    throw error
                }
            }
        }
    }
    
    private func attachLegacyVolume(bundleURL: URL, mountPointURL: URL, passphrase: String) async throws {
        try await runProcessWithStdinPassphrase(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                "-nobrowse",
                "-mountpoint", mountPointURL.path,
                "-stdinpass",
                bundleURL.path
            ],
            passphrase: passphrase,
            failureLabel: "hdiutil attach"
        )
    }
    
    private func attachModernVolume(bundleURL: URL, mountPointURL: URL, passphrase: String) async throws {
        try await runProcessWithStdinPassphrase(
            executable: "/usr/sbin/diskutil",
            arguments: [
                "image", "attach",
                "--stdinpassphrase",
                "--mountPoint", mountPointURL.path,
                "--nobrowse",
                bundleURL.path
            ],
            passphrase: passphrase,
            failureLabel: "diskutil image attach"
        )
    }
    
    private func ejectVolume(at mountPointURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = [
                "eject",
                "force",
                mountPointURL.path
            ]
            
            let errPipe = Pipe()
            process.standardError = errPipe
            
            try process.run()
            process.waitUntilExit()
            
            let errData: Data
            if process.terminationStatus != 0 {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            } else {
                errData = Data()
            }
            
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            
            guard process.terminationStatus == 0 else {
                NSLog("[VolumeManager] diskutil eject failed with status: %d, stderr: %@", process.terminationStatus, errStr)
                throw NSError(domain: "EncryptedVolumeManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to unmount SparseBundle at \(mountPointURL.path)"])
            }
        }.value
    }
    
    private func runProcessWithStdinPassphrase(
        executable: String,
        arguments: [String],
        passphrase: String,
        failureLabel: String
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardInput = pipe
            process.standardError = errPipe
            
            try process.run()
            
            if let data = (passphrase + "\n").data(using: .utf8) {
                try pipe.fileHandleForWriting.write(contentsOf: data)
                try pipe.fileHandleForWriting.close()
            }
            
            process.waitUntilExit()
            
            let errData: Data
            if process.terminationStatus != 0 {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            } else {
                errData = Data()
            }
            
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            
            guard process.terminationStatus == 0 else {
                NSLog("[VolumeManager] %@ failed with status: %d, stderr: %@", failureLabel, process.terminationStatus, errStr)
                throw NSError(
                    domain: "EncryptedVolumeManager",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to \(failureLabel): \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"]
                )
            }
        }.value
    }
}