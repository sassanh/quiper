import AppKit

@main
struct MainApp {
    static func main() {
        migrateApplicationSupportDirectoryIfNeeded()
        
        let app = NSApplication.shared
        // Set accessory policy immediately to prevent a dock icon from ever appearing during launch.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    private static func migrateApplicationSupportDirectoryIfNeeded() {
        let fileManager = FileManager.default
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
        let newDir = supportDir.appendingPathComponent(bundleID, isDirectory: true)
        
        // The old directory was named QuiperDev in Debug, or Quiper in Release.
        let oldDirName = bundleID.hasSuffix("Dev") ? "QuiperDev" : "Quiper"
        let oldDir = supportDir.appendingPathComponent(oldDirName, isDirectory: true)
        
        // Migrate only if the old directory exists and the new directory does not exist yet.
        if fileManager.fileExists(atPath: oldDir.path) && !fileManager.fileExists(atPath: newDir.path) {
            do {
                try fileManager.moveItem(at: oldDir, to: newDir)
            } catch {
                print("[Migration] Failed to migrate Application Support directory: \(error)")
            }
        }
    }
}
