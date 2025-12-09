import Foundation
import UserNotifications
import WebKit

@MainActor
final class WebNotificationBridge: NSObject {
    private static let handlerName = "quiperNotification"

    private weak var webView: WKWebView?
    private let handlerProxy = WeakScriptMessageHandler()
    private let serviceURL: String
    private let serviceName: String
    private let sessionIndex: Int

    init(webView: WKWebView, serviceURL: String, serviceName: String, sessionIndex: Int) {
        self.webView = webView
        self.serviceURL = serviceURL
        self.serviceName = serviceName
        self.sessionIndex = sessionIndex
        super.init()
        handlerProxy.delegate = self
        installBridge()
    }

    func invalidate() {
        guard let controller = webView?.configuration.userContentController else { return }
        controller.removeScriptMessageHandler(forName: Self.handlerName)
    }

    private func installBridge() {
        guard let controller = webView?.configuration.userContentController else { return }
        controller.addUserScript(Self.makeUserScript())
        controller.add(handlerProxy, name: Self.handlerName)
        guard !Self.isRunningTests else { return }
        syncInitialPermissionState()
    }

    private func syncInitialPermissionState() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                let permission = Self.permissionString(from: status)
                self.pushPermissionState(permission, requestId: nil)
            }
        }
    }

    private func requestPermission(requestId: Int) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state: String
                if let errorDescription {
                    NSLog("[Quiper] Notification permission request failed: \(errorDescription)")
                    state = "denied"
                } else {
                    state = granted ? "granted" : "denied"
                }
                self.pushPermissionState(state, requestId: requestId)
            }
        }
    }

    private func scheduleNotification(title: String, options: [String: Any]) {
        guard !Self.isRunningTests else { return }
        let payload = NotificationPayload(options: options)
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard Self.isAuthorized(status: status) else {
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = title
                if let body = payload.body {
                    content.body = body
                }
                if let subtitle = payload.subtitle {
                    content.subtitle = subtitle
                }
                if let badge = payload.badge {
                    content.badge = badge
                }
                if let tag = payload.tag {
                    content.threadIdentifier = tag
                }
                content.sound = payload.silent ? nil : .default
            var userInfo = payload.userInfo ?? [:]
            userInfo[NotificationMetadata.serviceURLKey] = serviceURL
            userInfo[NotificationMetadata.serviceNameKey] = serviceName
            userInfo[NotificationMetadata.sessionIndexKey] = sessionIndex
            content.userInfo = userInfo

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            Task {
                    do {
                        try await UNUserNotificationCenter.current().add(request)
                    } catch {
                        NSLog("[Quiper] Failed to deliver notification: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil
    }

    private func pushPermissionState(_ state: String, requestId: Int?) {
        guard let webView else { return }
        let escaped = Self.escapeForJavaScript(state)
        let script: String
        if let requestId {
            script = "window.__quiperNotificationBridge && window.__quiperNotificationBridge.resolve(\(requestId), '\(escaped)');"
        } else {
            script = "window.__quiperNotificationBridge && window.__quiperNotificationBridge.setPermission('\(escaped)');"
        }
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    static func permissionString(from status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional:
            return "granted"
        case .denied:
            return "denied"
        default:
            return "default"
        }
    }

    static func isAuthorized(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    static func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func makeUserScript() -> WKUserScript {
        WKUserScript(source: scriptSource,
                     injectionTime: .atDocumentStart,
                     forMainFrameOnly: false)
    }

    private struct NotificationPayload: @unchecked Sendable {
        let body: String?
        let subtitle: String?
        let badge: NSNumber?
        let tag: String?
        let silent: Bool
        let userInfo: [AnyHashable: Any]?

        init(options: [String: Any]) {
            body = options["body"] as? String
            subtitle = (options["subtitle"] as? String) ?? (options["subTitle"] as? String)
            if let badgeNumber = options["badge"] as? NSNumber {
                badge = badgeNumber
            } else if let badgeInt = options["badge"] as? Int {
                badge = NSNumber(value: badgeInt)
            } else {
                badge = nil
            }
            tag = options["tag"] as? String
            silent = options["silent"] as? Bool ?? false
            if let userInfoDict = options["data"] as? [String: Any] {
                userInfo = userInfoDict
            } else {
                userInfo = nil
            }
        }
    }

    private static var scriptSource: String {
        """
        (function() {
            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(handlerName)) {
                return;
            }
            if (window.Notification && window.Notification.__quiperBridgeInstalled) {
                return;
            }

            const handler = window.webkit.messageHandlers.\(handlerName);
            const pending = new Map();
            const changeListeners = new Set();
            let permissionState = 'default';
            let nextId = 0;

            const permissionStatus = {
                get state() {
                    return permissionState;
                },
                set state(value) {
                    permissionState = value;
                },
                onchange: null,
                addEventListener(type, handler) {
                    if (type === 'change' && typeof handler === 'function') {
                        changeListeners.add(handler);
                    }
                },
                removeEventListener(type, handler) {
                    if (type === 'change') {
                        changeListeners.delete(handler);
                    }
                },
                dispatchChange() {
                    const event = new Event('change');
                    if (typeof this.onchange === 'function') {
                        try { this.onchange(event); } catch (_) {}
                    }
                    changeListeners.forEach(listener => {
                        try { listener(event); } catch (_) {}
                    });
                }
            };

            function normalize(options) {
                try {
                    return JSON.parse(JSON.stringify(options || {}));
                } catch (err) {
                    return {};
                }
            }

            function send(message) {
                handler.postMessage(message);
            }

            window.__quiperNotificationBridge = {
                setPermission(state) {
                    if (typeof state === 'string') {
                        permissionState = state;
                        permissionStatus.dispatchChange();
                    }
                },
                resolve(id, state) {
                    const entry = pending.get(id);
                    if (!entry) { return; }
                    if (typeof state === 'string') {
                        permissionState = state;
                        permissionStatus.dispatchChange();
                    }
                    entry.resolve(permissionState);
                    pending.delete(id);
                },
                reject(id, reason) {
                    const entry = pending.get(id);
                    if (!entry) { return; }
                    pending.delete(id);
                    entry.reject(reason || new Error('Notification request failed'));
                }
            };

            class NativeNotification {
                constructor(title, options) {
                    if (permissionState !== 'granted') {
                        throw new Error('Notification permission has not been granted');
                    }
                    const normalizedOptions = normalize(options);
                    const normalizedTitle = (title === undefined || title === null) ? '' : title;
                    send({
                        type: 'showNotification',
                        title: String(normalizedTitle),
                        options: normalizedOptions
                    });
                    this.title = String(normalizedTitle);
                }

                static requestPermission(callback) {
                    const id = ++nextId;
                    const promise = new Promise((resolve, reject) => {
                        pending.set(id, {
                            resolve(value) {
                                resolve(value);
                                if (typeof callback === 'function') {
                                    callback(value);
                                }
                            },
                            reject(error) {
                                reject(error);
                                if (typeof callback === 'function') {
                                    callback(permissionState);
                                }
                            }
                        });
                    });
                    send({ type: 'requestPermission', id });
                    return promise;
                }

                static get permission() {
                    return permissionState;
                }
            }

            NativeNotification.__quiperBridgeInstalled = true;
            NativeNotification.prototype.close = function() {};
            window.Notification = NativeNotification;

            if (navigator.permissions && typeof navigator.permissions.query === 'function') {
                const originalQuery = navigator.permissions.query.bind(navigator.permissions);
                navigator.permissions.query = function(parameters) {
                    if (parameters && parameters.name === 'notifications') {
                        return Promise.resolve(permissionStatus);
                    }
                    return originalQuery(parameters);
                };
            }
        })();
        """
    }
}

extension WebNotificationBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName,
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "requestPermission":
            guard let requestId = payload["id"] as? Int else { return }
            requestPermission(requestId: requestId)
        case "showNotification":
            guard let title = payload["title"] as? String else { return }
            let options = payload["options"] as? [String: Any] ?? [:]
            scheduleNotification(title: title, options: options)
        default:
            break
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
