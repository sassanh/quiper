import Combine
import SwiftUI
import UserNotifications

@main
struct QuiperiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment = AppEnvironment()
    @StateObject private var notificationDelegate = IOSNotificationDelegate()

    var body: some Scene {
        WindowGroup {
            EngineBrowserView()
                .environmentObject(environment)
                .preferredColorScheme(environment.colorScheme.colorScheme)
                .task {
                    notificationDelegate.configure(environment: environment)
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

private final class IOSNotificationDelegate: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private weak var environment: AppEnvironment?

    @MainActor
    func configure(environment: AppEnvironment) {
        self.environment = environment
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let destination = NotificationDestination(userInfo: userInfo)

        Task { @MainActor [weak self, destination] in
            self?.environment?.activateNotification(
                serviceID: destination.serviceID,
                serviceURL: destination.serviceURL,
                sessionIndex: destination.sessionIndex
            )
        }
        completionHandler()
    }
}

extension IOSNotificationDelegate: @unchecked Sendable {}
