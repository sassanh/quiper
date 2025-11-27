import Foundation

@MainActor
protocol NotificationDispatching: AnyObject {
    func openSystemNotificationSettings()
    func configure(delegate: NotificationDispatcherDelegate?)
}

extension NotificationDispatcher: NotificationDispatching {}
