import AppKit
import WebKit
import Combine

protocol WebViewManagerDelegate: AnyObject {
    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView)
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView)
    func webViewDidFinishNavigation(_ webView: WKWebView)
}

final class WebViewManager: NSObject {
    weak var delegate: WebViewManagerDelegate?
    
    // Storage
    private var webviewsByURL: [String: [Int: WKWebView]] = [:]
    private var activeDownloads: [Any] = []
    
    // State needed for logic
    private var services: [Service] = []
    private var zoomLevels: [String: CGFloat] = [:]
    
    // Dependencies
    private weak var containerView: NSView?
    private weak var dragArea: NSView? // for positioning below
    
    // Test support
    private var navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var initialLoadAwaitingFocus = Set<ObjectIdentifier>()
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]

    init(containerView: NSView) {
        self.containerView = containerView
        super.init()
    }
    
    func updateServices(_ newServices: [Service]) {
        let incomingURLs = Set(newServices.map { $0.url })
        let existingURLs = Set(webviewsByURL.keys)
        
        let removedURLs = existingURLs.subtracting(incomingURLs)
        for url in removedURLs {
            if let removedWebviews = webviewsByURL[url] {
                removedWebviews.values.forEach { tearDownWebView($0) }
            }
            webviewsByURL.removeValue(forKey: url)
        }
        
        for service in newServices where webviewsByURL[service.url] == nil {
            webviewsByURL[service.url] = [:]
        }
        
        self.services = newServices
    }
    
    func updateZoomLevels(_ levels: [String: CGFloat]) {
        self.zoomLevels = levels
        for (url, level) in levels {
            if let sessionMap = webviewsByURL[url] {
                sessionMap.values.forEach { $0.pageZoom = level }
            }
        }
    }
    
    func applyZoom(_ level: CGFloat, for serviceURL: String) {
        zoomLevels[serviceURL] = level
        if let sessionMap = webviewsByURL[serviceURL] {
            sessionMap.values.forEach { $0.pageZoom = level }
        }
    }
    
    func getWebView(for service: Service, sessionIndex: Int) -> WKWebView? {
        webviewsByURL[service.url]?[sessionIndex]
    }
    
    func getOrCreateWebView(for service: Service, sessionIndex: Int, dragArea: NSView?) -> WKWebView {
        if let existing = webviewsByURL[service.url]?[sessionIndex] {
            return existing
        }
        
        guard let contentView = containerView else {
            fatalError("WebViewManager containerView is nil")
        }
        
        // Calculate frame
        let dragHeight = dragArea?.bounds.height ?? 0
        let availableHeight = contentView.bounds.height - dragHeight
        let frame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: availableHeight
        )
        
        let userContentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        if let customCSS = service.customCSS, !customCSS.isEmpty {
            let cssScript = """
            const style = document.createElement('style');
            style.textContent = `/* Custom CSS */
            \(customCSS)`;
            document.head.appendChild(style);
            """
            let userScript = WKUserScript(source: cssScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
        }

        let webview = WKWebView(frame: frame, configuration: config)
        webview.setValue(false, forKey: "drawsBackground")
        webview.autoresizingMask = [.width, .height]
        webview.uiDelegate = self
        webview.navigationDelegate = self
        webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webview.isHidden = true
        webview.pageZoom = zoomLevels[service.url] ?? 1.0
        
        attachNotificationBridge(to: webview, service: service, sessionIndex: sessionIndex)

        // Add to view hierarchy
        if let dragArea = dragArea {
            contentView.addSubview(webview, positioned: .below, relativeTo: dragArea)
        } else {
            contentView.addSubview(webview)
        }
        
        if webviewsByURL[service.url] == nil {
            webviewsByURL[service.url] = [:]
        }
        webviewsByURL[service.url]?[sessionIndex] = webview
        
        // Load initial URL
        if let url = URL(string: service.url) {
            if url.isFileURL {
                webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webview.load(URLRequest(url: url))
            }
            let token = ObjectIdentifier(webview)
            initialLoadAwaitingFocus.insert(token)
        }
        
        // Observers
        webview.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        webview.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
        
        return webview
    }
    
    func hideAll() {
        webviewsByURL.values.forEach { sessionMap in
            sessionMap.values.forEach { $0.isHidden = true }
        }
    }
    
    func serviceURL(for webView: WKWebView) -> URL? {
        for (urlString, webViews) in webviewsByURL {
            if webViews.values.contains(webView) {
                return URL(string: urlString)
            }
        }
        return nil
    }
    
    func waitForNavigation(on webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            let id = ObjectIdentifier(webView)
            navigationContinuations[id] = continuation
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let cont = navigationContinuations.removeValue(forKey: id) {
                    cont.resume()
                }
            }
        }
    }
    
    // MARK: - KVO
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView else { return }
        
        if keyPath == "title" {
            delegate?.webViewDidUpdateTitle(webView.title ?? "", for: webView)
        } else if keyPath == "loading" {
            delegate?.webViewDidUpdateLoading(webView.isLoading, for: webView)
        }
    }
    
    // MARK: - Private Helpers
    
    private func tearDownWebView(_ webView: WKWebView) {
        detachNotificationBridge(from: webView)
        webView.removeObserver(self, forKeyPath: "title")
        webView.removeObserver(self, forKeyPath: "loading")
        webView.removeFromSuperview()
    }

    private func attachNotificationBridge(to webView: WKWebView, service: Service, sessionIndex: Int) {
        let identifier = ObjectIdentifier(webView)
        notificationBridges[identifier] = WebNotificationBridge(
            webView: webView,
            serviceURL: service.url,
            serviceName: service.name,
            sessionIndex: sessionIndex
        )
    }

    private func detachNotificationBridge(from webView: WKWebView) {
        let identifier = ObjectIdentifier(webView)
        notificationBridges[identifier]?.invalidate()
        notificationBridges.removeValue(forKey: identifier)
    }
    
    private func isInternalLink(target: URL, service: URL, friendPatterns: [String]) -> Bool {
        let targetHost = target.host?.lowercased()
        let serviceHost = service.host?.lowercased()
        
        if let tHost = targetHost, let sHost = serviceHost {
            if tHost == sHost { return true }
            
            let rootServiceHost = sHost.hasPrefix("www.") ? String(sHost.dropFirst(4)) : sHost
            if tHost == rootServiceHost || tHost.hasSuffix("." + rootServiceHost) {
                return true
            }
        } else if target.scheme == service.scheme && (target.isFileURL || target.scheme == "data") {
            // For file:// and data: URLs, consider them internal if schemes match (common in tests)
            return true
        } else if target.isFileURL && ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // During UI testing, permit all local file popups to avoid Safari redirection
            return true
        }

        let targetString = target.absoluteString
        for pattern in friendPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: targetString.utf16.count)
            if regex.firstMatch(in: targetString, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate

private final class ModalPopupWindow: NSWindow, NSWindowDelegate {
    private var shield: InteractionShieldView?
    private weak var parentWin: NSWindow?
    private var isCleaningUp = false
    
    init(contentRect: NSRect, parentWindow: NSWindow) {
        self.parentWin = parentWindow
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        
        self.level = .floating
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false // Critical: Prevent double-release when used with addChildWindow
        self.delegate = self
        
        parentWindow.addChildWindow(self, ordered: .above)
        
        // Center relative to parent
        let parentFrame = parentWindow.frame
        let x = parentFrame.midX - contentRect.width / 2
        let y = parentFrame.midY - contentRect.height / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))
        
        if let contentView = parentWindow.contentView {
            let shieldView = InteractionShieldView(frame: contentView.bounds)
            shieldView.autoresizingMask = [.width, .height]
            contentView.addSubview(shieldView, positioned: .above, relativeTo: nil)
            self.shield = shieldView
        }
    }
    
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        // 1. Remove shield and restore parent window interactivity synchronously
        shield?.removeFromSuperview()
        shield = nil
        
        if let parent = parentWin, let contentView = parent.contentView {
            contentView.subviews.filter { $0 is InteractionShieldView }.forEach { $0.removeFromSuperview() }
        }
        
        // 2. Nil out webview delegates to avoid crashes from WebKit callbacks during deallocation
        contentView?.subviews.forEach {
            if let webView = $0 as? WKWebView {
                webView.uiDelegate = nil
                webView.navigationDelegate = nil
                webView.stopLoading()
            }
        }
        
        // 3. Detach from parent
        if let parent = parentWin {
            parent.removeChildWindow(self)
            
            // 4. Asynchronously restore focus to avoid AppKit re-entrancy issues
            DispatchQueue.main.async {
                parent.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        cleanup()
    }
}

private final class PopupUIDelegate: NSObject, WKUIDelegate {
    static let shared = PopupUIDelegate()
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
    }
}

extension WebViewManager: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    
    @MainActor
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let allowedSchemes = isUITesting ? ["http", "https", "file"] : ["http", "https"]
        
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let serviceURL = serviceURL(for: webView),
              let service = services.first(where: { $0.url == serviceURL.absoluteString }) else {
            if let url = navigationAction.request.url {
                 NSWorkspace.shared.open(url)
            }
            return nil
        }
        
        let isFriend = isInternalLink(target: url, service: serviceURL, friendPatterns: service.friendDomains)
        
        if isFriend {
            guard let parentWindow = webView.window else { return nil }
            
            // Create a modal-like window for popups (like Google Login)
            let popupWindow = ModalPopupWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                parentWindow: parentWindow
            )
            popupWindow.center()
            popupWindow.title = "Login - \(service.name)"
            
            let popupWebView = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
            popupWebView.autoresizingMask = [.width, .height]
            popupWebView.uiDelegate = PopupUIDelegate.shared
            
            popupWindow.contentView?.addSubview(popupWebView)
            popupWindow.makeKeyAndOrderFront(nil)
            
            return popupWebView
        } else {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                
                
                decisionHandler(.download)
                return
            }
        }

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let serviceURL = serviceURL(for: webView),
              let service = services.first(where: { $0.url == serviceURL.absoluteString }) else {
            decisionHandler(.allow)
            return
        }

        let allowInApp = isInternalLink(target: url, service: serviceURL, friendPatterns: service.friendDomains)
        
        if allowInApp {
            let allowWithoutAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowWithoutAppLink)
            return
        }
        
        if navigationAction.navigationType == .linkActivated {
            let targetFrameIsMain = navigationAction.targetFrame?.isMainFrame ?? true
            if targetFrameIsMain {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        
        
        
        
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
             if #available(macOS 11.3, *) {
                 
                 decisionHandler(.download)
             } else {
                 
                 decisionHandler(.cancel)
             }
        }
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        
        download.delegate = self
        activeDownloads.append(download)
        
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        
        download.delegate = self
        activeDownloads.append(download)
        
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // We handle loading state via KVO and delegates, so mostly nothing needed here
        // Except explicit reset calls if needed
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let token = ObjectIdentifier(webView)
        
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        
        delegate?.webViewDidFinishNavigation(webView)
        
        if initialLoadAwaitingFocus.contains(token) {
            initialLoadAwaitingFocus.remove(token)
            // Signal delegate again or handle internally?
            // The Original MWC calls focusInputInActiveWebview with delay
            delegate?.webViewDidFinishNavigation(webView) 
        }
    }
    
    // MARK: WKDownloadDelegate
    
    @available(macOS 11.3, *)
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let fileManager = FileManager.default
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(nil)
            return
        }
        let destinationURL = downloadsURL.appendingPathComponent(suggestedFilename)
        completionHandler(destinationURL)
    }

    @available(macOS 11.3, *)
    func downloadDidFinish(_ download: WKDownload) {
        activeDownloads.removeAll { ($0 as? WKDownload) === download }
    }

    @available(macOS 11.3, *)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        activeDownloads.removeAll { ($0 as? WKDownload) === download }
    }
}
