import Testing
import UserNotifications
@testable import Quiper

@MainActor
struct WebNotificationBridgeTests {
    
    @Test func escapeForJavaScript() {
        #expect(WebNotificationBridge.escapeForJavaScript("Hello") == "Hello")
        #expect(WebNotificationBridge.escapeForJavaScript("It's me") == "It\\'s me")
        #expect(WebNotificationBridge.escapeForJavaScript("Line\nBreak") == "Line\\nBreak")
        #expect(WebNotificationBridge.escapeForJavaScript("Back\\Slash") == "Back\\\\Slash")
    }
    
    @Test func permissionString() {
        #expect(WebNotificationBridge.permissionString(from: .authorized) == "granted")
        #expect(WebNotificationBridge.permissionString(from: .provisional) == "granted")
        #expect(WebNotificationBridge.permissionString(from: .denied) == "denied")
        #expect(WebNotificationBridge.permissionString(from: .notDetermined) == "default")
    }
    
    @Test func isAuthorized() {
        #expect(WebNotificationBridge.isAuthorized(status: .authorized))
        #expect(WebNotificationBridge.isAuthorized(status: .provisional))
        #expect(!WebNotificationBridge.isAuthorized(status: .denied))
        #expect(!WebNotificationBridge.isAuthorized(status: .notDetermined))
    }
}
