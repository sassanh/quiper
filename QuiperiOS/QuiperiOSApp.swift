import SwiftUI
import UserNotifications

@main
struct QuiperiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            EngineBrowserView()
                .environmentObject(environment)
                .preferredColorScheme(environment.colorScheme.colorScheme)
                .task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .badge, .sound]
                    )
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        environment.save()
                    }
                }
        }
    }
}
