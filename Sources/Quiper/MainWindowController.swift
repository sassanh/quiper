import AppKit
import WebKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private var dragArea: DraggableView!
    private var serviceSelector: NSSegmentedControl!
    private var sessionSelector: NSSegmentedControl!
    private var services: [Service] = []
    private var currentServiceName: String?
    private var currentServiceURL: String?
    private var webviewsByURL: [String: [WKWebView]] = [:]
    private var activeIndicesByURL: [String: Int] = [:]
    private var keyDownEventMonitor: Any?
    private weak var contentContainerView: NSView?

    private var inspectorVisible = false {
        didSet {
            NotificationCenter.default.post(name: .inspectorVisibilityChanged, object: inspectorVisible)
        }
    }
    
    init() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 500, y: 200, width: 550, height: 620),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
        services = Settings.shared.loadSettings()
        currentServiceName = services.first?.name
        currentServiceURL = services.first?.url
        services.forEach { service in
            activeIndicesByURL[service.url] = 0
        }
        setupUI()
        self.window?.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API
    var serviceCount: Int { services.count }
    var activeServiceURL: String? { currentService()?.url }

    func selectService(at index: Int) {
        guard services.indices.contains(index) else { return }
        currentServiceName = services[index].name
        currentServiceURL = services[index].url
        serviceSelector.selectedSegment = index
        updateActiveWebview()
    }

    func switchSession(to index: Int) {
        guard let service = currentService() else { return }
        let bounded = max(0, min(index, 9))
        activeIndicesByURL[service.url] = bounded
        sessionSelector.selectedSegment = segmentIndex(forSession: bounded)
        updateActiveWebview()
    }

    func handleCommandShortcut(event: NSEvent) -> Bool {
        if (window as? OverlayWindow)?.isFullScreen == true {
            return false
        }
        guard event.modifierFlags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isControl = event.modifierFlags.contains(.control)
        let isOption = event.modifierFlags.contains(.option)
        let isShift = event.modifierFlags.contains(.shift)

        if isControl && isShift && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        if isControl || isOption {
            if let digit = Int(key), digit >= 1, digit <= services.count {
                selectService(at: digit - 1)
                return true
            }
            if key == "i" {
                toggleInspector()
                return true
            }
            return false
        }

        switch key {
        case "0":
            switchSession(to: 9)
            return true
        case "1","2","3","4","5","6","7","8","9":
            if let value = Int(key) {
                switchSession(to: value - 1)
                return true
            }
        case ",":
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return true
        case "h":
            hide()
            return true
        default:
            break
        }

        return false
    }
    
    func currentWebViewURL() -> URL? {
        currentWebView()?.url
    }

    func reloadServices(_ services: [Service]? = nil) {
        let newServices = services ?? Settings.shared.loadSettings()
        updateServices(newServices: newServices)
    }

    private func updateServices(newServices: [Service]) {
        guard let contentView = contentContainerView ?? window?.contentView else { return }
        let availableFrame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - Constants.DRAGGABLE_AREA_HEIGHT
        )

        let incomingURLs = Set(newServices.map { $0.url })
        let existingURLs = Set(webviewsByURL.keys)

        let removedURLs = existingURLs.subtracting(incomingURLs)
        for url in removedURLs {
            if let removedWebviews = webviewsByURL[url] {
                removedWebviews.forEach { $0.removeFromSuperview() }
            }
            webviewsByURL.removeValue(forKey: url)
            activeIndicesByURL.removeValue(forKey: url)
        }

        for service in newServices where webviewsByURL[service.url] == nil {
            webviewsByURL[service.url] = createWebviewStack(for: service, frame: availableFrame, in: contentView)
            activeIndicesByURL[service.url] = 0
        }

        services = newServices
        syncCurrentServiceSelection()
        refreshServiceSegments()
        updateActiveWebview()
    }


    func toggleInspector() {
        guard let inspector = currentWebView()?.value(forKey: "inspector") as? NSObject else {
            return
        }
        let showSelector = NSSelectorFromString("show")
        let closeSelector = NSSelectorFromString("close")
        if inspectorVisible {
            if inspector.responds(to: closeSelector) {
                inspector.perform(closeSelector)
            }
        } else {
            if inspector.responds(to: showSelector) {
                inspector.perform(showSelector)
            }
        }
        inspectorVisible.toggle()
    }

    func focusInputInActiveWebview() {
        guard let service = currentService() else { return }
        let selector = service.focus_selector
        guard !selector.isEmpty else { return }
        currentWebView()?.evaluateJavaScript("setTimeout(() => document.querySelector(\\\"\(selector)\\\")?.focus(), 0);", completionHandler: nil)
    }

    func currentWebView() -> WKWebView? {
        guard let service = currentService(),
              let webviewsForService = webviewsByURL[service.url] else {
            return nil
        }
        let activeIndex = activeIndicesByURL[service.url] ?? 0
        guard webviewsForService.indices.contains(activeIndex) else { return nil }
        return webviewsForService[activeIndex]
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let webView = currentWebView() {
            window?.makeFirstResponder(webView)
        }
        focusInputInActiveWebview()
        setShortcutsEnabled(true)
    }

    func hide() {
        window?.orderOut(nil)
        setShortcutsEnabled(false)
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        if enabled {
            if keyDownEventMonitor == nil {
                keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if self?.handleCommandShortcut(event: event) == true {
                        return nil
                    }
                    return event
                }
            }
        } else {
            if let monitor = keyDownEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownEventMonitor = nil
            }
        }
    }

    // MARK: - Private helpers
    private func configureWindow() {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        window.setFrameAutosaveName(Constants.WINDOW_FRAME_AUTOSAVE_NAME)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.delegate = self

        let frame = window.contentRect(forFrameRect: window.frame)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = Constants.WINDOW_CORNER_RADIUS

            let host = NSView(frame: glass.bounds)
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            host.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
            host.layer?.masksToBounds = true

            glass.contentView = host
            window.contentView = glass
            contentContainerView = host
        } else {
            let effect = NSVisualEffectView(frame: frame)
            if #available(macOS 13.0, *) {
                effect.material = .underWindowBackground
            } else {
                effect.material = .hudWindow
            }
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
            effect.layer?.masksToBounds = true
            effect.autoresizingMask = [.width, .height]
            window.contentView = effect
            contentContainerView = effect
        }
    }

    private func setupUI() {
        guard let contentView = contentContainerView ?? window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        createDragArea(in: contentView)
        createWebviews(in: contentView)
        updateActiveWebview()
    }

    private func createDragArea(in contentView: NSView) {
        let bounds = contentView.bounds
        dragArea = DraggableView(frame: NSRect(
            x: 0,
            y: bounds.size.height - Constants.DRAGGABLE_AREA_HEIGHT,
            width: bounds.size.width,
            height: Constants.DRAGGABLE_AREA_HEIGHT
        ))
        dragArea.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(dragArea)

        serviceSelector = NSSegmentedControl()
        serviceSelector.segmentStyle = .automatic
        serviceSelector.autoresizingMask = [.minXMargin, .minYMargin]
        serviceSelector.target = self
        serviceSelector.action = #selector(serviceChanged(_:))
        dragArea.addSubview(serviceSelector)

        sessionSelector = NSSegmentedControl()
        sessionSelector.segmentStyle = .automatic
        sessionSelector.segmentCount = 10
        sessionSelector.autoresizingMask = [.minXMargin, .minYMargin]
        for index in 0..<10 {
            sessionSelector.setLabel(index == 9 ? "0" : "\(index + 1)", forSegment: index)
        }
        sessionSelector.target = self
        sessionSelector.action = #selector(sessionChanged(_:))
        dragArea.addSubview(sessionSelector)

        layoutSelectors()
        refreshServiceSegments()
        updateSessionSelector()
    }

    private func layoutSelectors() {
        let headerHeight = dragArea.bounds.size.height
        let selectorHeight: CGFloat = 25

        let sessionWidth: CGFloat = 300
        sessionSelector.frame = NSRect(
            x: Constants.UI_PADDING,
            y: (headerHeight - selectorHeight) / 2,
            width: sessionWidth,
            height: selectorHeight
        )

        let serviceWidth = max(180, estimatedWidthForServiceSegments() + 20)
        serviceSelector.frame = NSRect(
            x: dragArea.bounds.width - serviceWidth - Constants.UI_PADDING,
            y: (headerHeight - selectorHeight) / 2,
            width: serviceWidth,
            height: selectorHeight
        )
    }

    private func createWebviews(in contentView: NSView) {
        webviewsByURL.values.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        webviewsByURL.removeAll()
        activeIndicesByURL.removeAll()

        let frame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - Constants.DRAGGABLE_AREA_HEIGHT
        )

        for service in services {
            webviewsByURL[service.url] = createWebviewStack(for: service, frame: frame, in: contentView)
            activeIndicesByURL[service.url] = 0
        }
    }

    private func createWebviewStack(for service: Service, frame: NSRect, in contentView: NSView) -> [WKWebView] {
        var serviceViews: [WKWebView] = []
        for _ in 0..<10 {
            let config = WKWebViewConfiguration()
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")

            let webview = WKWebView(frame: frame, configuration: config)
            webview.autoresizingMask = [.width, .height]
            webview.uiDelegate = self
            webview.navigationDelegate = self
            webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            webview.isHidden = true

            contentView.addSubview(webview, positioned: .below, relativeTo: dragArea)
            serviceViews.append(webview)
        }
        return serviceViews
    }

    private func currentService() -> Service? {
        if let url = currentServiceURL,
           let match = services.first(where: { $0.url == url }) {
            currentServiceName = match.name
            return match
        }
        if let name = currentServiceName,
           let match = services.first(where: { $0.name == name }) {
            currentServiceURL = match.url
            return match
        }
        currentServiceName = services.first?.name
        currentServiceURL = services.first?.url
        return services.first
    }

    private func updateActiveWebview() {
        guard let service = currentService(),
              let webviewsForService = webviewsByURL[service.url] else {
            return
        }

        let activeIndex = activeIndicesByURL[service.url] ?? 0
        guard webviewsForService.indices.contains(activeIndex) else { return }

        let activeWebview = webviewsForService[activeIndex]
        if activeWebview.url == nil, let url = URL(string: service.url) {
            activeWebview.load(URLRequest(url: url))
        }

        webviewsByURL.values.flatMap { $0 }.forEach { $0.isHidden = true }
        activeWebview.isHidden = false
        window?.makeFirstResponder(activeWebview)
        focusInputInActiveWebview()
    }

    private func refreshServiceSegments() {
        serviceSelector.segmentCount = services.count
        for (index, service) in services.enumerated() {
            serviceSelector.setLabel(service.name, forSegment: index)
        }
        if let currentName = currentServiceName,
           let idx = services.firstIndex(where: { $0.name == currentName }) {
            serviceSelector.selectedSegment = idx
        } else {
            serviceSelector.selectedSegment = services.isEmpty ? -1 : 0
            currentServiceName = services.first?.name
        }
        layoutSelectors()
    }

    private func syncCurrentServiceSelection() {
        if let url = currentServiceURL,
           let match = services.first(where: { $0.url == url }) {
            currentServiceName = match.name
            return
        }
        if let name = currentServiceName,
           let match = services.first(where: { $0.name == name }) {
            currentServiceURL = match.url
            currentServiceName = match.name
            return
        }
        currentServiceName = services.first?.name
        currentServiceURL = services.first?.url
    }

    private func updateSessionSelector() {
        guard let service = currentService() else { return }
        let index = activeIndicesByURL[service.url] ?? 0
        sessionSelector.selectedSegment = segmentIndex(forSession: index)
    }

    private func estimatedWidthForServiceSegments() -> CGFloat {
        guard let font = serviceSelector.font else { return CGFloat(services.count * 80) }
        return services.reduce(0) { partialResult, service in
            let size = (service.name as NSString).size(withAttributes: [.font: font])
            return partialResult + size.width + 20
        }
    }

    private func sessionIndex(forSegment segment: Int) -> Int {
        segment == 9 ? 9 : segment
    }

    private func segmentIndex(forSession session: Int) -> Int {
        session == 9 ? 9 : session
    }

    private func initiateDownload(from url: URL) {
        URLSession.shared.downloadTask(with: url) { location, response, error in
            guard let location, error == nil else {
                NSLog("[Quiper] Download failed: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            let suggested = response?.suggestedFilename ?? url.lastPathComponent
            let destination = downloads.appendingPathComponent(suggested)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                NSLog("[Quiper] Failed to move download: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: - Actions
    @objc private func serviceChanged(_ sender: NSSegmentedControl) {
        selectService(at: sender.selectedSegment)
        updateSessionSelector()
    }

    @objc private func sessionChanged(_ sender: NSSegmentedControl) {
        switchSession(to: sessionIndex(forSegment: sender.selectedSegment))
    }

    // MARK: - NSWindowDelegate
    func windowDidResize(_ notification: Notification) {
        layoutSelectors()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusInputInActiveWebview()
    }

}


@MainActor
extension MainWindowController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload, let url = navigationAction.request.url {
            initiateDownload(from: url)
            decisionHandler(.cancel)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else if let url = navigationResponse.response.url {
            decisionHandler(.cancel)
            initiateDownload(from: url)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
