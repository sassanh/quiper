import Foundation

@MainActor
final class EncryptedVolumeManager {
    static let shared = EncryptedVolumeManager()
    
    private init() {}
    
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
    
    /// Path where the sparsebundle is mounted
    func getMountPointURL(for serviceID: UUID) -> URL {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
        
        return libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")
            .appendingPathComponent(serviceID.uuidString.lowercased())
    }
    
    /// Checks if the sparsebundle is physically present on disk
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
    
    /// Creates an encrypted APFS sparsebundle
    func createVolume(for serviceID: UUID, passphrase: String) async throws {
        let bundleURL = getBundleURL(for: serviceID)
        let parentDir = bundleURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Remove existing bundle if any to start fresh
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
        
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = [
                "create",
                "-size", "5g",
                "-fs", "APFS",
                "-encryption", "AES-256",
                "-volname", "QuiperEngine-\(serviceID.uuidString)",
                "-type", "SPARSEBUNDLE",
                "-stdinpass",
                bundleURL.path
            ]
            
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
                NSLog("[VolumeManager] hdiutil create failed with status: %d, stderr: %@", process.terminationStatus, errStr)
                throw NSError(domain: "EncryptedVolumeManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to create encrypted SparseBundle using hdiutil: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"])
            }
        }.value
    }
    
    /// Mounts the encrypted sparsebundle using the passphrase
    func mountVolume(for serviceID: UUID, passphrase: String) async throws {
        let bundleURL = getBundleURL(for: serviceID)
        let mountPointURL = getMountPointURL(for: serviceID)
        let fileManager = FileManager.default
        
        // If already mounted, do nothing
        if isMounted(for: serviceID) {
            markUnlocked(serviceID)
            return
        }
        
        // Check for existing unencrypted data to migrate
        var shouldMigrate = false
        let tempBackupURL = baseStorageDir.appendingPathComponent("MigrationBackup").appendingPathComponent(serviceID.uuidString)
        
        var statInfo = stat()
        if lstat(mountPointURL.path, &statInfo) == 0 {
            let isSymlink = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
            let isDir = (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
            
            if isSymlink {
                // If it's a symbolic link (broken or active), delete it directly
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
                    // If it's an empty real directory, delete it first to ensure hdiutil mounts cleanly
                    try? fileManager.removeItem(at: mountPointURL)
                }
            } else {
                // Regular file or other entity, remove it
                try? fileManager.removeItem(at: mountPointURL)
            }
        }
        
        try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
        
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = [
                "attach",
                "-nobrowse",
                "-mountpoint", mountPointURL.path,
                "-stdinpass",
                bundleURL.path
            ]
            
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
                NSLog("[VolumeManager] hdiutil attach failed with status: %d, stderr: %@", process.terminationStatus, errStr)
                throw NSError(domain: "EncryptedVolumeManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to mount encrypted SparseBundle: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"])
            }
        }.value
        
        // Migrate unencrypted data into newly mounted volume if needed
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
        let mountPointURL = getMountPointURL(for: serviceID)
        
        guard isMounted(for: serviceID) else {
            markLocked(serviceID)
            return
        }
        
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = [
                "detach",
                "-force",
                mountPointURL.path
            ]
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "EncryptedVolumeManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to unmount SparseBundle at \(mountPointURL.path)"])
            }
        }.value
        
        // Clean up the mountpoint directory
        try? FileManager.default.removeItem(at: mountPointURL)
        markLocked(serviceID)
    }
    
    /// Securely removes the sparsebundle storage from disk when encryption is disabled or service is deleted
    func deleteVolume(for serviceID: UUID) {
        markLocked(serviceID)
        let bundleURL = getBundleURL(for: serviceID)
        try? FileManager.default.removeItem(at: bundleURL)
        
        let mountPointURL = getMountPointURL(for: serviceID)
        try? FileManager.default.removeItem(at: mountPointURL)
    }
}
