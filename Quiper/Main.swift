import AppKit

@main
struct MainApp {
    static func main() {
        let app = NSApplication.shared
        // Set accessory policy immediately to prevent a dock icon from ever appearing during launch.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
