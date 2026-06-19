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
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let bundleID = Constants.BUNDLE_ID
        
        SettingsDirectoryMigrator.migrateIfNeeded(fileManager: .default, bundleID: bundleID, supportDir: supportDir)
    }
}
