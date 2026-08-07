import Foundation
import WebKit

@MainActor
final class WebSessionCoordinator: NSObject {
    private weak var webView: WKWebView?
    private let service: Service
    private let sessionIndex: Int
    private var notificationBridge: WebNotificationBridge?

    var onInputState: (([String: Any]) -> Void)?
    var onTitle: ((String) -> Void)?
    var onLoading: ((Bool) -> Void)?
    var onURL: ((URL) -> Void)?
    var onNavigationState: ((_ canGoBack: Bool, _ canGoForward: Bool) -> Void)?

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
    }

    func installInputTracker() {}

    // MARK: - JS injection

    func focusInput() {
        guard let webView, !service.focus_selector.isEmpty else { return }
        let jsString = WebScripts.makeFocusInputScript(
            selector: service.focus_selector,
            hasSaved: false,
            text: "",
            start: 0,
            end: 0
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
}

// MARK: - WKNavigationDelegate

extension WebSessionCoordinator: WKNavigationDelegate {
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
