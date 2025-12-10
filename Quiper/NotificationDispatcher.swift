import AppKit
import Foundation
import UserNotifications
import Combine

final class NotificationDispatcher: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationDispatcher()

    private let notificationCenter: UserNotificationCentering
    private let urlOpener: URLOpening
    private var initialAuthorizationRequested = false
    private weak var delegate: NotificationDispatcherDelegate?
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined {
        didSet {
            NotificationCenter.default.post(name: .notificationPermissionChanged, object: nil)
        }
    }

    init(notificationCenter: UserNotificationCentering = UNUserNotificationCenter.current(),
         urlOpener: URLOpening = NSWorkspace.shared) {
        self.notificationCenter = notificationCenter
        self.urlOpener = urlOpener
        super.init()
        Task { await refreshNotificationStatus() }
    }


    @MainActor
    func configure(delegate: NotificationDispatcherDelegate?) {
        self.delegate = delegate
        if notificationCenter.delegate !== self {
            notificationCenter.delegate = self
        }
        Task { @MainActor [weak self] in
            await self?.ensureInitialAuthorization()
        }
    }

    @MainActor
    func refreshNotificationStatus() async {
        let settings = await notificationCenter.settings()
        self.authorizationStatus = settings.authorizationStatus
    }

    @MainActor
    func ensureInitialAuthorization() async {
        await refreshNotificationStatus()
        
        guard authorizationStatus == .notDetermined else { return }
        guard !initialAuthorizationRequested else { return }
        initialAuthorizationRequested = true

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationStatus()
            if !granted {
                openSystemNotificationSettings()
            }
        } catch {
            NSLog("[Quiper] Failed to request notification authorization: \(error.localizedDescription)")
            await refreshNotificationStatus()
        }
    }

    @MainActor
    func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper"
        // Try specific deep link first
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)") {
            _ = urlOpener.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            _ = urlOpener.open(url)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let serviceURL = userInfo[NotificationMetadata.serviceURLKey] as? String
        let sessionIndex = userInfo[NotificationMetadata.sessionIndexKey] as? Int
        Task { @MainActor [weak self, serviceURL, sessionIndex] in
            guard let self else { return }
            self.delegate?.notificationDispatcher(self,
                                                  didActivateNotificationForServiceURL: serviceURL,
                                                  sessionIndex: sessionIndex)
        }
        completionHandler()
    }
}

extension NotificationDispatcher: @unchecked Sendable {}

@MainActor
protocol NotificationDispatcherDelegate: AnyObject {
    func notificationDispatcher(_ dispatcher: NotificationDispatcher,
                                didActivateNotificationForServiceURL serviceURL: String?,
                                sessionIndex: Int?)
}
