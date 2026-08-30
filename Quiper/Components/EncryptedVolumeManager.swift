import Foundation

@MainActor
final class EncryptedVolumeManager {
    static let shared = EncryptedVolumeManager()
    
    private init() {}
    
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
    
    func getBundleURL(for serviceID: UUID) -> URL {
        return baseStorageDir.appendingPathComponent("EncryptedStores").appendingPathComponent("\(serviceID.uuidString).sparsebundle")
    }
    
    func legacyBackupBundleURL(for serviceID: UUID) -> URL {
        getBundleURL(for: serviceID).appendingPathExtension("hdiutil-backup")
    }
    
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
    
    func bundleExists(for serviceID: UUID) -> Bool {
        let bundlePath = getBundleURL(for: serviceID).path
        return FileManager.default.fileExists(atPath: bundlePath)
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
        EngineMetadataMigrationManager.shared.clearCachedMetadata(for: serviceID)
    }
    
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

        ensureSpotlightExclusion(for: serviceID, includeMountPoint: false)
    }
    
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
        
        do {
            try await attachVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("resource busy") {
                NSLog("[VolumeManager] Attach reported busy mount point for service %@: Forcing cleanup and retrying once.", serviceID.uuidString)
                try? await ejectVolume(at: mountPointURL)
                try? fileManager.removeItem(at: mountPointURL)
                try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
                try await Task.sleep(nanoseconds: 300_000_000)
                try await attachVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
            } else if message.localizedCaseInsensitiveContains("incorrect passphrase") || message.localizedCaseInsensitiveContains("authentication") || message.localizedCaseInsensitiveContains("no such file") {
                // Legacy hdiutil bundles fail with diskutil. Surface a clear migration message.
                throw NSError(domain: "EncryptedVolumeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: legacyBundleMessage(for: serviceID)])
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
        
        ensureSpotlightExclusion(for: serviceID, includeMountPoint: true)
        markUnlocked(serviceID)
    }

    private func legacyBundleMessage(for serviceID: UUID) -> String {
        let name = Settings.shared.services.first(where: { $0.id == serviceID })?.name ?? "This engine"
        return "\(name) uses an older secure storage format that this version of Quiper no longer supports. Please download Quiper 5.0.0, open it once so it can migrate your protected engines, then update to this version again. You can find 5.0.0 on the releases page."
    }

    func applySpotlightExclusionToAllSecuredEngines() {
        for service in Settings.shared.services where service.isEncrypted {
            ensureSpotlightExclusion(for: service.id, includeMountPoint: isMounted(for: service.id))
        }
    }

    private func ensureSpotlightExclusion(for serviceID: UUID, includeMountPoint: Bool) {
        let bundleURL = getBundleURL(for: serviceID)
        SpotlightExclusion.ensureExcluded(at: bundleURL.deletingLastPathComponent())

        if bundleExists(for: serviceID) {
            SpotlightExclusion.ensureExcluded(at: bundleURL)
        }

        guard includeMountPoint else { return }

        let mountPointURL = getMountPointURL(for: serviceID)
        SpotlightExclusion.ensureExcluded(at: mountPointURL)
    }
    
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
    
    func deleteVolume(for serviceID: UUID) {
        markLocked(serviceID)
        let bundleURL = getBundleURL(for: serviceID)
        try? FileManager.default.removeItem(at: bundleURL)
        try? FileManager.default.removeItem(at: legacyBackupBundleURL(for: serviceID))
        
        let mountPointURL = getMountPointURL(for: serviceID)
        try? FileManager.default.removeItem(at: mountPointURL)
    }
    
    private func attachVolume(bundleURL: URL, mountPointURL: URL, passphrase: String) async throws {
        try await attachModernVolume(bundleURL: bundleURL, mountPointURL: mountPointURL, passphrase: passphrase)
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
    
    private func runProcessWithStdinPassphrase(executable: String, arguments: [String], passphrase: String, failureLabel: String) async throws {
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
                throw NSError(domain: "EncryptedVolumeManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to \(failureLabel): \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"])
            }
        }.value
    }
}
