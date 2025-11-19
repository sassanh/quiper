import AppKit
import WebKit
import Carbon

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private var dragArea: DraggableView!
    private var serviceSelector: ServiceSelectorControl!
    private var sessionSelector: NSSegmentedControl!
    private var settingsButton: NSButton!
    private var sessionActionsButton: NSButton!
    private var services: [Service] = []
    private var currentServiceName: String?
    private var currentServiceURL: String?
    private var webviewsByURL: [String: [WKWebView]] = [:]
    private var activeIndicesByURL: [String: Int] = [:]
    private var keyDownEventMonitor: Any?
    private var zoomLevelsByURL: [String: CGFloat] = [:]
    private weak var contentContainerView: NSView?
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]
    private var draggingServiceIndex: Int?

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
        zoomLevelsByURL = Settings.shared.serviceZoomLevels
        currentServiceName = services.first?.name
        currentServiceURL = services.first?.url
        services.forEach { service in
            activeIndicesByURL[service.url] = 0
            if zoomLevelsByURL[service.url] == nil {
                zoomLevelsByURL[service.url] = Zoom.default
            }
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

    @discardableResult
    func selectService(withURL url: String) -> Bool {
        guard let index = services.firstIndex(where: { $0.url == url }) else { return false }
        selectService(at: index)
        return true
    }

    func selectService(at index: Int, focusWebView: Bool = true) {
        guard services.indices.contains(index) else { return }
        currentServiceName = services[index].name
        currentServiceURL = services[index].url
        serviceSelector.selectedSegment = index
        updateActiveWebview(focusWebView: focusWebView)
        updateSessionSelector()
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
        let keyCode = UInt16(event.keyCode)
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
        case "=":
            zoom(by: Zoom.step)
            return true
        case "-":
            zoom(by: -Zoom.step)
            return true
        default:
            break
        }

        if keyCode == UInt16(kVK_ANSI_KeypadPlus) {
            zoom(by: Zoom.step)
            return true
        }
        if keyCode == UInt16(kVK_ANSI_KeypadMinus) {
            zoom(by: -Zoom.step)
            return true
        }
        if keyCode == UInt16(kVK_Delete) {
            resetZoom()
            return true
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
        zoomLevelsByURL = Settings.shared.serviceZoomLevels
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
                removedWebviews.forEach { tearDownWebView($0) }
            }
            webviewsByURL.removeValue(forKey: url)
            activeIndicesByURL.removeValue(forKey: url)
            zoomLevelsByURL.removeValue(forKey: url)
            Settings.shared.clearZoomLevel(for: url)
        }

        for service in newServices where webviewsByURL[service.url] == nil {
            webviewsByURL[service.url] = createWebviewStack(for: service, frame: availableFrame, in: contentView)
            activeIndicesByURL[service.url] = 0
            if zoomLevelsByURL[service.url] == nil {
                zoomLevelsByURL[service.url] = Zoom.default
            }
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

    func logCustomAction(_ action: CustomAction) {
        guard let service = currentService(), let webView = currentWebView() else { return }
        let storedScript = ActionScriptStorage.loadScript(
            serviceID: service.id,
            actionID: action.id,
            fallback: service.actionScripts[action.id] ?? ""
        )
        let rawScript = storedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let script: String
        if rawScript.isEmpty {
            let message = "Action \(escapeForJavaScript(action.name.isEmpty ? "Action" : action.name)) not implemented for \(escapeForJavaScript(service.name))"
            script = "console.log(\"\(message)\")"
        } else {
            script = rawScript
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

        serviceSelector = ServiceSelectorControl()
        serviceSelector.segmentStyle = .automatic
        serviceSelector.autoresizingMask = [.minXMargin, .minYMargin]
        serviceSelector.target = self
        serviceSelector.action = #selector(serviceChanged(_:))
        serviceSelector.mouseDownSegmentHandler = { [weak self] index in
            self?.handleServiceMouseDown(at: index)
        }
        serviceSelector.dragBeganHandler = { [weak self] source in
            self?.handleServiceDragBegan(from: source)
        }
        serviceSelector.dragChangedHandler = { [weak self] destination in
            self?.handleServiceDragChanged(to: destination)
        }
        serviceSelector.dragEndedHandler = { [weak self] in
            self?.handleServiceDragEnded()
        }
        dragArea.addSubview(serviceSelector)

        sessionActionsButton = NSButton()
        if let actionsSymbol = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Session Actions") {
            actionsSymbol.isTemplate = true
            sessionActionsButton.image = actionsSymbol
            sessionActionsButton.imagePosition = .imageOnly
        } else {
            sessionActionsButton.title = "⋯"
        }
        sessionActionsButton.bezelStyle = .shadowlessSquare
        sessionActionsButton.isBordered = false
        sessionActionsButton.focusRingType = .none
        sessionActionsButton.imageScaling = .scaleProportionallyUpOrDown
        sessionActionsButton.contentTintColor = .secondaryLabelColor
        sessionActionsButton.autoresizingMask = [.minXMargin, .minYMargin]
        sessionActionsButton.toolTip = "Session Actions"
        sessionActionsButton.target = self
        sessionActionsButton.action = #selector(sessionActionsButtonTapped(_:))
        dragArea.addSubview(sessionActionsButton)

        settingsButton = NSButton()
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(named: NSImage.actionTemplateName) {
            gear.isTemplate = true
            settingsButton.image = gear
            settingsButton.imagePosition = .imageOnly
        } else {
            settingsButton.title = "⚙︎"
        }
        settingsButton.bezelStyle = .shadowlessSquare
        settingsButton.isBordered = false
        settingsButton.focusRingType = .none
        settingsButton.imageScaling = .scaleProportionallyUpOrDown
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        settingsButton.toolTip = "Open Settings"
        settingsButton.target = self
        settingsButton.action = #selector(settingsButtonTapped(_:))
        dragArea.addSubview(settingsButton)

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

    private func handleServiceMouseDown(at index: Int) {
        selectService(at: index, focusWebView: false)
    }

    private func handleServiceDragBegan(from index: Int) {
        draggingServiceIndex = index
        NSCursor.closedHand.set()
    }

    private func handleServiceDragChanged(to destination: Int) {
        guard let source = draggingServiceIndex, source != destination else { return }
        if let newIndex = reorderServices(from: source, to: destination) {
            draggingServiceIndex = newIndex
        }
    }

    private func handleServiceDragEnded() {
        draggingServiceIndex = nil
        NSCursor.arrow.set()
    }

    private func layoutSelectors() {
        let headerHeight = dragArea.bounds.size.height
        let selectorHeight: CGFloat = 25
        let buttonSize: CGFloat = 26
        let buttonSpacing: CGFloat = 6

        settingsButton.frame = NSRect(
            x: dragArea.bounds.width - buttonSize - Constants.UI_PADDING,
            y: (headerHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        sessionActionsButton.frame = NSRect(
            x: settingsButton.frame.minX - buttonSize - buttonSpacing,
            y: (headerHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        let sessionWidth: CGFloat = 300
        sessionSelector.frame = NSRect(
            x: Constants.UI_PADDING,
            y: (headerHeight - selectorHeight) / 2,
            width: sessionWidth,
            height: selectorHeight
        )

        let serviceWidth = max(180, estimatedWidthForServiceSegments() + 20)
        let serviceX = max(
            sessionSelector.frame.maxX + Constants.UI_PADDING,
            sessionActionsButton.frame.minX - serviceWidth - Constants.UI_PADDING
        )
        serviceSelector.frame = NSRect(
            x: serviceX,
            y: (headerHeight - selectorHeight) / 2,
            width: serviceWidth,
            height: selectorHeight
        )
    }

    private func createWebviews(in contentView: NSView) {
        webviewsByURL.values.flatMap { $0 }.forEach { tearDownWebView($0) }
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
        for sessionIndex in 0..<10 {
            let config = WKWebViewConfiguration()
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")

            let webview = WKWebView(frame: frame, configuration: config)
            webview.autoresizingMask = [.width, .height]
            webview.uiDelegate = self
            webview.navigationDelegate = self
            webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            webview.isHidden = true
            webview.pageZoom = zoomLevelsByURL[service.url] ?? Zoom.default
            attachNotificationBridge(to: webview, service: service, sessionIndex: sessionIndex)

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

    private func updateActiveWebview(focusWebView: Bool = true) {
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
        activeWebview.pageZoom = zoomLevelsByURL[service.url] ?? Zoom.default
        if focusWebView {
            window?.makeFirstResponder(activeWebview)
            focusInputInActiveWebview()
        }
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

    private func reorderServices(from source: Int, to destination: Int) -> Int? {
        guard services.indices.contains(source), services.indices.contains(destination) else { return nil }
        services.swapAt(source, destination)
        Settings.shared.services = services
        Settings.shared.saveSettings()
        refreshServiceSegments()
        updateSessionSelector()
        return destination
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

    private func tearDownWebView(_ webView: WKWebView) {
        detachNotificationBridge(from: webView)
        webView.removeFromSuperview()
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
    }

    @objc private func sessionChanged(_ sender: NSSegmentedControl) {
        switchSession(to: sessionIndex(forSegment: sender.selectedSegment))
    }

    @objc private func settingsButtonTapped(_ sender: NSButton) {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    @objc private func sessionActionsButtonTapped(_ sender: NSButton) {
        let menu = buildSessionActionsMenu()
        guard !menu.items.isEmpty else { return }
        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    // MARK: - NSWindowDelegate
    func windowDidResize(_ notification: Notification) {
        layoutSelectors()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusInputInActiveWebview()
    }

    private func buildSessionActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Session Actions")
        menu.autoenablesItems = false

        menu.addItem(menuItem(title: "Zoom In",
                              iconName: "plus.magnifyingglass",
                              keyEquivalent: "=",
                              modifiers: .command,
                              action: #selector(performMenuZoomIn)))
        menu.addItem(menuItem(title: "Zoom Out",
                              iconName: "minus.magnifyingglass",
                              keyEquivalent: "-",
                              modifiers: .command,
                              action: #selector(performMenuZoomOut)))
        menu.addItem(menuItem(title: "Reset Zoom",
                              iconName: "arrow.uturn.backward",
                              keyEquivalent: deleteKeyEquivalent,
                              modifiers: .command,
                              action: #selector(performMenuResetZoom)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Reload",
                              iconName: "arrow.clockwise",
                              keyEquivalent: "r",
                              modifiers: .command,
                              action: #selector(reloadActiveWebView)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Copy",
                              iconName: "doc.on.doc",
                              keyEquivalent: "c",
                              modifiers: .command,
                              action: #selector(copyFromWebView)))
        menu.addItem(menuItem(title: "Cut",
                              iconName: "scissors",
                              keyEquivalent: "x",
                              modifiers: .command,
                              action: #selector(cutFromWebView)))
        menu.addItem(menuItem(title: "Paste",
                              iconName: "doc.on.clipboard",
                              keyEquivalent: "v",
                              modifiers: .command,
                              action: #selector(pasteIntoWebView)))

        let customActions = Settings.shared.customActions
        if !customActions.isEmpty {
            menu.addItem(.separator())
            customActions.forEach { action in
                menu.addItem(menuItem(for: action))
            }
        }
        let enabled = currentWebView() != nil
        menu.items.forEach { item in
            if item.isSeparatorItem || item.representedObject is CustomAction || !item.isEnabled {
                return
            }
            item.isEnabled = enabled
        }
        return menu
    }

    private func menuItem(title: String,
                          iconName: String? = nil,
                          keyEquivalent: String = "",
                          modifiers: NSEvent.ModifierFlags = [],
                          action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        if let iconName,
           let image = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            image.isTemplate = true
            item.image = image
        }
        return item
    }

    private func menuItem(for action: CustomAction) -> NSMenuItem {
        let title = action.name.isEmpty ? "Untitled Action" : action.name
        let item = menuItem(title: title,
                            iconName: "bolt.fill",
                            keyEquivalent: "",
                            modifiers: [],
                            action: #selector(performCustomActionFromMenu(_:)))
        if let shortcut = action.shortcut,
           let info = keyEquivalent(for: shortcut) {
            item.keyEquivalent = info.key
            item.keyEquivalentModifierMask = info.modifiers
        } else {
            item.keyEquivalent = ""
        }
        item.representedObject = action
        return item
    }

    private func keyEquivalent(for configuration: HotkeyManager.Configuration) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags).intersection([.command, .option, .control, .shift])
        guard let key = character(for: UInt16(configuration.keyCode)) else { return nil }
        let normalizedKey = key.count == 1 ? key.lowercased() : key
        return (normalizedKey, modifiers)
    }

    private func character(for keyCode: UInt16) -> String? {
        if keyCode == UInt16(kVK_Delete) {
            return deleteKeyEquivalent
        }
        if keyCode == UInt16(kVK_Space) {
            return " "
        }
        return keyEquivalentMap[keyCode]
    }

    @objc private func performMenuZoomIn(_ sender: Any?) {
        zoom(by: Zoom.step)
    }

    @objc private func performMenuZoomOut(_ sender: Any?) {
        zoom(by: -Zoom.step)
    }

    @objc private func performMenuResetZoom(_ sender: Any?) {
        resetZoom()
    }

    @objc private func reloadActiveWebView(_ sender: Any?) {
        currentWebView()?.reload()
    }

    @objc private func copyFromWebView(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        window?.makeFirstResponder(webView)
        NSApp.sendAction(#selector(NSTextView.copy(_:)), to: nil, from: self)
    }

    @objc private func cutFromWebView(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        window?.makeFirstResponder(webView)
        NSApp.sendAction(#selector(NSTextView.cut(_:)), to: nil, from: self)
    }

    @objc private func pasteIntoWebView(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        window?.makeFirstResponder(webView)
        NSApp.sendAction(#selector(NSTextView.paste(_:)), to: nil, from: self)
    }

    @objc private func performCustomActionFromMenu(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CustomAction else { return }
        logCustomAction(action)
    }

    private func zoom(by delta: CGFloat) {
        guard let service = currentService() else { return }
        let currentZoom = zoomLevelsByURL[service.url] ?? Zoom.default
        let nextZoom = max(Zoom.min, min(Zoom.max, currentZoom + delta))
        applyZoom(nextZoom, to: service)
    }

    private func resetZoom() {
        guard let service = currentService() else { return }
        applyZoom(Zoom.default, to: service)
    }

    private func applyZoom(_ value: CGFloat, to service: Service) {
        zoomLevelsByURL[service.url] = value
        if let webviews = webviewsByURL[service.url] {
            webviews.forEach { $0.pageZoom = value }
        }
        Settings.shared.storeZoomLevel(value, for: service.url)
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

private enum Zoom {
    static let step: CGFloat = 0.1
    static let min: CGFloat = 0.5
    static let max: CGFloat = 2.5
    static let `default`: CGFloat = 1.0
}

private let deleteKeyEquivalent: String = {
    guard let scalar = UnicodeScalar(NSDeleteCharacter) else { return "" }
    return String(Character(scalar))
}()

private let keyEquivalentMap: [UInt16: String] = [
    UInt16(kVK_ANSI_A): "a",
    UInt16(kVK_ANSI_B): "b",
    UInt16(kVK_ANSI_C): "c",
    UInt16(kVK_ANSI_D): "d",
    UInt16(kVK_ANSI_E): "e",
    UInt16(kVK_ANSI_F): "f",
    UInt16(kVK_ANSI_G): "g",
    UInt16(kVK_ANSI_H): "h",
    UInt16(kVK_ANSI_I): "i",
    UInt16(kVK_ANSI_J): "j",
    UInt16(kVK_ANSI_K): "k",
    UInt16(kVK_ANSI_L): "l",
    UInt16(kVK_ANSI_M): "m",
    UInt16(kVK_ANSI_N): "n",
    UInt16(kVK_ANSI_O): "o",
    UInt16(kVK_ANSI_P): "p",
    UInt16(kVK_ANSI_Q): "q",
    UInt16(kVK_ANSI_R): "r",
    UInt16(kVK_ANSI_S): "s",
    UInt16(kVK_ANSI_T): "t",
    UInt16(kVK_ANSI_U): "u",
    UInt16(kVK_ANSI_V): "v",
    UInt16(kVK_ANSI_W): "w",
    UInt16(kVK_ANSI_X): "x",
    UInt16(kVK_ANSI_Y): "y",
    UInt16(kVK_ANSI_Z): "z",
    UInt16(kVK_ANSI_0): "0",
    UInt16(kVK_ANSI_1): "1",
    UInt16(kVK_ANSI_2): "2",
    UInt16(kVK_ANSI_3): "3",
    UInt16(kVK_ANSI_4): "4",
    UInt16(kVK_ANSI_5): "5",
    UInt16(kVK_ANSI_6): "6",
    UInt16(kVK_ANSI_7): "7",
    UInt16(kVK_ANSI_8): "8",
    UInt16(kVK_ANSI_9): "9",
    UInt16(kVK_ANSI_Equal): "=",
    UInt16(kVK_ANSI_Minus): "-",
    UInt16(kVK_ANSI_LeftBracket): "[",
    UInt16(kVK_ANSI_RightBracket): "]",
    UInt16(kVK_ANSI_Semicolon): ";",
    UInt16(kVK_ANSI_Quote): "'",
    UInt16(kVK_ANSI_Comma): ",",
    UInt16(kVK_ANSI_Period): ".",
    UInt16(kVK_ANSI_Slash): "/",
    UInt16(kVK_ANSI_Grave): "`",
    UInt16(kVK_ANSI_KeypadPlus): "=",
    UInt16(kVK_ANSI_KeypadMinus): "-",
    UInt16(kVK_ANSI_Keypad0): "0",
    UInt16(kVK_ANSI_Keypad1): "1",
    UInt16(kVK_ANSI_Keypad2): "2",
    UInt16(kVK_ANSI_Keypad3): "3",
    UInt16(kVK_ANSI_Keypad4): "4",
    UInt16(kVK_ANSI_Keypad5): "5",
    UInt16(kVK_ANSI_Keypad6): "6",
    UInt16(kVK_ANSI_Keypad7): "7",
    UInt16(kVK_ANSI_Keypad8): "8",
    UInt16(kVK_ANSI_Keypad9): "9",
    UInt16(kVK_ANSI_KeypadDecimal): ".",
    UInt16(kVK_ANSI_KeypadDivide): "/",
    UInt16(kVK_ANSI_KeypadMultiply): "*"
]
