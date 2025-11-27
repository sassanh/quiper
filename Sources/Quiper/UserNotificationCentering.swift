import UserNotifications

struct NotificationSettingsProxy {
    let authorizationStatus: UNAuthorizationStatus
}

@MainActor
protocol UserNotificationCentering: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func settings() async -> NotificationSettingsProxy
}

extension UNUserNotificationCenter: UserNotificationCentering {
    func settings() async -> NotificationSettingsProxy {
        let settings = await self.notificationSettings()
        return NotificationSettingsProxy(authorizationStatus: settings.authorizationStatus)
    }
}
