import Testing
import UserNotifications
import AppKit
@testable import Quiper

class MockUserNotificationCenter: UserNotificationCentering {
    var delegate: UNUserNotificationCenterDelegate?
    var requestAuthorizationCalled = false
    var notificationSettingsCalled = false
    var authorizationGranted = true
    var authorizationStatusToReturn: UNAuthorizationStatus = .notDetermined

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCalled = true
        return authorizationGranted
    }

    func settings() async -> NotificationSettingsProxy {
        notificationSettingsCalled = true
        return NotificationSettingsProxy(authorizationStatus: authorizationStatusToReturn)
    }
}

class MockNotificationDispatcherDelegate: NotificationDispatcherDelegate {
    var didActivateNotificationForServiceURLCalled = false
    var serviceURL: String?
    var sessionIndex: Int?

    func notificationDispatcher(_ dispatcher: NotificationDispatcher, didActivateNotificationForServiceURL serviceURL: String?, sessionIndex: Int?) {
        didActivateNotificationForServiceURLCalled = true
        self.serviceURL = serviceURL
        self.sessionIndex = sessionIndex
    }
}

class MockURLOpener: URLOpening {
    var openCalled = false
    var openedURL: URL?

    func open(_ url: URL) -> Bool {
        openCalled = true
        openedURL = url
        return true
    }
}

@MainActor
struct NotificationDispatcherTests {

    @Test func configure_WhenNotDetermined_RequestsAuthorization() async {
        // Given
        let mockNotificationCenter = MockUserNotificationCenter()
        let mockDelegate = MockNotificationDispatcherDelegate()
        let mockURLOpener = MockURLOpener()
        let dispatcher = NotificationDispatcher(notificationCenter: mockNotificationCenter, urlOpener: mockURLOpener)
        
        mockNotificationCenter.authorizationStatusToReturn = UNAuthorizationStatus.notDetermined
        
        // When
        dispatcher.configure(delegate: mockDelegate)
        await dispatcher.ensureInitialAuthorization()

        // Then
        #expect(mockNotificationCenter.delegate === dispatcher)
        #expect(mockNotificationCenter.notificationSettingsCalled)
        #expect(mockNotificationCenter.requestAuthorizationCalled)
    }
    
    @Test func configure_WhenDenied_DoesNotRequestAuthorization() async {
        // Given
        let mockNotificationCenter = MockUserNotificationCenter()
        let mockDelegate = MockNotificationDispatcherDelegate()
        let mockURLOpener = MockURLOpener()
        let dispatcher = NotificationDispatcher(notificationCenter: mockNotificationCenter, urlOpener: mockURLOpener)
        
        mockNotificationCenter.authorizationStatusToReturn = UNAuthorizationStatus.denied
        
        // When
        dispatcher.configure(delegate: mockDelegate)
        await dispatcher.ensureInitialAuthorization()

        // Then
        #expect(mockNotificationCenter.delegate === dispatcher)
        #expect(mockNotificationCenter.notificationSettingsCalled)
        #expect(!mockNotificationCenter.requestAuthorizationCalled)
    }

    @Test func openSystemNotificationSettings() {
        let mockNotificationCenter = MockUserNotificationCenter()
        let mockURLOpener = MockURLOpener()
        let dispatcher = NotificationDispatcher(notificationCenter: mockNotificationCenter, urlOpener: mockURLOpener)
        
        dispatcher.openSystemNotificationSettings()
        
        #expect(mockURLOpener.openCalled)
        #expect(mockURLOpener.openedURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.notifications")
    }
}

