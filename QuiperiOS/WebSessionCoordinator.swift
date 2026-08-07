import Foundation
import UIKit
import WebKit

@MainActor
final class WebSessionCoordinator: NSObject {
    private weak var webView: WKWebView?
    private let service: Service
    private let sessionIndex: Int
    private var notificationBridge: WebNotificationBridge?
    private var userApprovedURLs = Set<URL>()

    var onInputState: (([String: Any]) -> Void)?
    var onTitle: ((String) -> Void)?
    var onLoading: ((Bool) -> Void)?
    var onURL: ((URL) -> Void)?
    var onNavigationState: ((_ canGoBack: Bool, _ canGoForward: Bool) -> Void)?
    var onRememberRoutingDecision: ((_ host: String, _ action: RoutingAction) -> Void)?
    var onDidFinish: (() -> Void)?

    init(webView: WKWebView, service: Service, sessionIndex: Int) {
        self.webView = webView
        self.service = service
        self.sessionIndex = sessionIndex
        super.init()

        let bridge = WebNotificationBridge(
            webView: webView,
            serviceID: service.id,
            serviceName: service.name,
            sessionIndex: sessionIndex
        )
        self.notificationBridge = bridge

        let userContentController = webView.configuration.userContentController
        userContentController.addUserScript(WebScripts.makeValueSetterInterceptorScript())
        userContentController.addUserScript(WebScripts.makeInputStateTrackerScript(
            selector: service.focus_selector,
            initiallyActive: true
        ))
        userContentController.add(self, name: "quiperInputState")

        let cssToInject = Self.resolvedCustomCSS(for: service)
        if !cssToInject.isEmpty {
            userContentController.addUserScript(
                WKUserScript(source: WebScripts.makeCustomCSSInjectionScript(css: cssToInject), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )
        }
    }

    /// Mirrors the macOS `customCSS(for:)` resolution: a synced template uses the
    /// bundled default, otherwise the engine's own stored CSS.
    private static func resolvedCustomCSS(for service: Service) -> String {
        ActionScripts.syncedCustomCSS(for: service) ?? service.customCSS ?? ""
    }

    func installInputTracker() {}

    // MARK: - JS injection

    func focusInput(restoring state: TabInputState?) {
        guard let webView, !service.focus_selector.isEmpty else { return }
        let shouldRestore = service.preservePrompt
        let inputState = shouldRestore ? state : nil
        let jsString = WebScripts.makeFocusInputScript(
            selector: service.focus_selector,
            hasSaved: inputState != nil,
            text: inputState?.text ?? "",
            start: inputState?.start ?? 0,
            end: inputState?.end ?? 0
        )
        webView.evaluateJavaScript(jsString, completionHandler: nil)
    }

    func injectAndSubmit(_ text: String) {
        guard let webView, !service.focus_selector.isEmpty else { return }
        let jsString = WebScripts.makeInjectAndSubmitScript(
            selector: service.focus_selector,
            text: text
        )
        webView.evaluateJavaScript(jsString, completionHandler: nil)
    }

    // MARK: - Link routing

    private var allowWithoutAppLink: WKNavigationActionPolicy {
        WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func presentRoutingPrompt(for url: URL, webView: WKWebView) {
        let alert = UIAlertController(
            title: "Security & Routing",
            message: "How would you like to open this link?\n\(url.absoluteString)",
            preferredStyle: .alert
        )
        let host = url.host ?? ""
        let openHere = UIAlertAction(title: "Open Here", style: .default) { [weak self] _ in
            self?.userApprovedURLs.insert(url)
            webView.load(URLRequest(url: url))
        }
        let openHereAlways = UIAlertAction(title: "Always Open Here", style: .default) { [weak self] _ in
            self?.onRememberRoutingDecision?(host, .internalStay)
            self?.userApprovedURLs.insert(url)
            webView.load(URLRequest(url: url))
        }
        let openExternally = UIAlertAction(title: "Open Externally", style: .default) { [weak self] _ in
            self?.openExternally(url)
        }
        let openExternallyAlways = UIAlertAction(title: "Always Open Externally", style: .default) { [weak self] _ in
            self?.onRememberRoutingDecision?(host, .external)
            self?.openExternally(url)
        }
        alert.addAction(openHere)
        alert.addAction(openHereAlways)
        alert.addAction(openExternally)
        alert.addAction(openExternallyAlways)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in })
        topViewController()?.present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension WebSessionCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let serviceURL = URL(string: service.url) else {
            decisionHandler(.allow)
            return
        }

        // Only route main frame navigations (including new windows where targetFrame is nil)
        let targetFrameIsMain = navigationAction.targetFrame?.isMainFrame ?? true
        if !targetFrameIsMain {
            decisionHandler(.allow)
            return
        }

        if userApprovedURLs.contains(url) {
            userApprovedURLs.remove(url)
            decisionHandler(allowWithoutAppLink)
            return
        }

        switch RoutingResolver.route(for: url, service: service, serviceURL: serviceURL) {
        case .openHere:
            decisionHandler(allowWithoutAppLink)
        case .openNewWindow:
            decisionHandler(.cancel)
            openExternally(url)
        case .openExternal:
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                openExternally(url)
            } else {
                decisionHandler(.allow)
            }
        case .showPrompt:
            decisionHandler(.cancel)
            presentRoutingPrompt(for: url, webView: webView)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        onLoading?(true)
        notifyNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        notifyNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        onLoading?(false)
        if let url = webView.url {
            onURL?(url)
        }
        onTitle?(webView.title ?? "")
        notifyNavigationState(for: webView)
        onDidFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        onLoading?(false)
        notifyNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        onLoading?(false)
        notifyNavigationState(for: webView)
    }

    private func notifyNavigationState(for webView: WKWebView) {
        onNavigationState?(webView.canGoBack, webView.canGoForward)
    }
}

// MARK: - WKScriptMessageHandler

extension WebSessionCoordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "quiperInputState",
              let payload = message.body as? [String: Any] else {
            return
        }
        onInputState?(payload)
    }
}

// MARK: - WKUIDelegate

extension WebSessionCoordinator: WKUIDelegate {
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        Task { @MainActor in
            let granted = await MediaCapturePermission.ensureAccess(for: type)
            decisionHandler(granted ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler() })
        topViewController()?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        topViewController()?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in textField.text = defaultText }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        topViewController()?.present(alert, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return nil }
        var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
