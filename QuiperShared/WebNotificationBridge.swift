import Foundation
import UserNotifications
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class WebNotificationBridge: NSObject {
    private static let handlerName = "quiperNotification"

    private weak var webView: WKWebView?
    private let handlerProxy = WeakScriptMessageHandler()
    private let serviceID: UUID
    private var serviceName: String
    private let sessionIndex: Int
    private var redactsContent: Bool
    /// Resolves the engine's icon on demand so favicons that arrive after the
    /// bridge is attached are still picked up. Supplied by the platform, which
    /// owns settings access the shared target must not reach into.
    private let iconProvider: (() -> Data?)?

    init(
        webView: WKWebView,
        serviceID: UUID,
        serviceName: String,
        sessionIndex: Int,
        redactsContent: Bool = false,
        iconProvider: (() -> Data?)? = nil
    ) {
        self.webView = webView
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.sessionIndex = sessionIndex
        self.redactsContent = redactsContent
        self.iconProvider = iconProvider
        super.init()
        handlerProxy.delegate = self
        installBridge()
        
        #if os(macOS)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        #else
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func invalidate() {
        guard let controller = webView?.configuration.userContentController else { return }
        controller.removeScriptMessageHandler(forName: Self.handlerName)
    }

    /// Reinstalls the bridge after a coordinator rebuilds the page's user scripts.
    /// The same proxy is retained so pending permission requests remain associated
    /// with this bridge instance.
    func reinstall() {
        invalidate()
        installBridge()
    }

    func updateServiceName(_ name: String) {
        serviceName = name
    }

    func updateContentRedaction(_ redactsContent: Bool) {
        self.redactsContent = redactsContent
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
    
    @objc private func appDidBecomeActive() {
        syncInitialPermissionState()
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
                content.title = self.redactsContent ? self.serviceName : title
                if self.redactsContent {
                    content.body = "Open Quiper to view this protected notification."
                } else {
                    content.body = payload.body ?? ""
                    content.subtitle = payload.subtitle ?? ""
                    content.badge = payload.badge
                    content.threadIdentifier = payload.tag ?? ""
                }
                content.sound = payload.silent ? nil : .default
                var userInfo = self.redactsContent ? [:] : (payload.userInfo ?? [:])
                userInfo[NotificationMetadata.serviceIDKey] = serviceID.uuidString
                userInfo[NotificationMetadata.serviceNameKey] = serviceName
                userInfo[NotificationMetadata.sessionIndexKey] = sessionIndex
                content.userInfo = userInfo

                // Locked engines stay anonymous: no icon that would identify them.
                if !self.redactsContent,
                   let iconPNG = Self.notificationIconPNG(from: self.iconProvider?()),
                   let iconAttachment = Self.iconAttachment(pngData: iconPNG) {
                    content.attachments = [iconAttachment]
                }

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    NSLog("[Quiper] Failed to deliver notification: \(error.localizedDescription)")
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
        let setter: String
        if let requestId {
            setter = "window.__quiperNotificationBridge && window.__quiperNotificationBridge.resolve(\(requestId), '\(escaped)');"
        } else {
            setter = "window.__quiperNotificationBridge && window.__quiperNotificationBridge.setPermission('\(escaped)');"
        }
        // Each frame keeps its own bridge state, but evaluateJavaScript runs
        // in the main frame only, so propagate the push to same-origin
        // frames (cross-origin access throws and is skipped). Without this a
        // notifier running in an iframe would permanently read 'default'.
        let script = setter + """
            try {
                for (const __quiperFrame of window.frames) {
                    try {
                        __quiperFrame.__quiperNotificationBridge && __quiperFrame.__quiperNotificationBridge.setPermission('\(escaped)');
                    } catch (_) {}
                }
            } catch (_) {}
            """
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

    /// Normalizes raw icon bytes (favicon PNG/JPEG/ICO, user-uploaded image)
    /// to a small PNG attachment payload. Returns nil when the bytes are not
    /// a decodable image. Capped at 256px: banners only render a thumbnail.
    private static let iconMaxDimension = 256

    private static func notificationIconPNG(from data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let base = NSBitmapImageRep(data: tiff) else { return nil }
        let width = base.pixelsWide, height = base.pixelsHigh
        guard width > 0, height > 0 else { return nil }
        let scale = min(1.0, Double(iconMaxDimension) / Double(max(width, height)))
        let targetWidth = max(1, Int(Double(width) * scale))
        let targetHeight = max(1, Int(Double(height) * scale))
        let rep: NSBitmapImageRep
        if scale < 1.0 {
            guard let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: targetWidth,
                pixelsHigh: targetHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
            image.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            NSGraphicsContext.restoreGraphicsState()
            rep = scaled
        } else {
            rep = base
        }
        return rep.representation(using: .png, properties: [:])
        #else
        guard let image = UIImage(data: data) else { return nil }
        let width = image.size.width, height = image.size.height
        guard width > 0, height > 0 else { return nil }
        let scale = min(1.0, CGFloat(iconMaxDimension) / max(width, height))
        if scale < 1.0 {
            let target = CGSize(width: width * scale, height: height * scale)
            let renderer = UIGraphicsImageRenderer(size: target)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }.pngData()
        }
        return image.pngData()
        #endif
    }

    private static func iconAttachment(pngData: Data) -> UNNotificationAttachment? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-notification-icons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneIconAttachments(in: directory)
            let url = directory.appendingPathComponent(UUID().uuidString + ".png")
            try pngData.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "engine-icon", url: url)
        } catch {
            NSLog("[Quiper] Failed to attach engine icon to notification: \(error.localizedDescription)")
            return nil
        }
    }

    private static func pruneIconAttachments(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for file in files {
            guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
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

            // Service-worker delivery (`navigator.serviceWorker.ready.then(reg =>
            // reg.showNotification(...))`) runs in page context when invoked
            // from the page, so it can be intercepted here the same way.
            // Calls originating inside the worker itself remain invisible to
            // page scripts and still cannot be bridged.
            try {
                if (typeof ServiceWorkerRegistration !== 'undefined'
                    && ServiceWorkerRegistration.prototype
                    && typeof ServiceWorkerRegistration.prototype.showNotification === 'function'
                    && !ServiceWorkerRegistration.prototype.__quiperBridgeInstalled) {
                    ServiceWorkerRegistration.prototype.__quiperBridgeInstalled = true;
                    ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                        if (permissionState === 'granted') {
                            try {
                                send({
                                    type: 'showNotification',
                                    title: String((title === undefined || title === null) ? '' : title),
                                    options: normalize(options)
                                });
                            } catch (_) {}
                        }
                        return Promise.resolve();
                    };
                }
            } catch (_) {}

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
