import AppKit
import WebKit
import Carbon
import Combine

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let jsTools: [String: String] = [
        "waitFor": """
        function waitFor(check, timeoutMs = 10) {
          return new Promise((resolve, reject) => {
            const start = Date.now();
            const step = () => {
              try {
                if (check()) { resolve(true); return; }
              } catch (err) {
                reject(err);
                return;
              }
              if (Date.now() - start >= timeoutMs) {
                reject(new Error(`waitFor timed out after ${timeoutMs}ms. check function: ${String(check)}`));
                return;
              }
              window.requestAnimationFrame(step);
            };
            step();
          })
        }
        """
    ]

    private var dragArea: DraggableView!
    private var serviceSelector: ServiceSelectorControl!
    var sessionSelector: NSSegmentedControl!
    var settingsButton: NSButton!
    var sessionActionsButton: NSButton!
    var services: [Service] = []
    var currentServiceName: String?
    var currentServiceURL: String?
    var webviewsByURL: [String: [Int: WKWebView]] = [:]
    var activeIndicesByURL: [String: Int] = [:]
    var keyDownEventMonitor: Any?
    var zoomLevelsByURL: [String: CGFloat] = [:]
    weak var contentContainerView: NSView?
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]
    private var titleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var draggingServiceIndex: Int?
    private var findBar: NSVisualEffectView?
    private var findField: NSSearchField?
    private var findStatusLabel: NSTextField?
    private var findPreviousButton: NSButton?
    private var findNextButton: NSButton?
    private var isFindBarVisible = false
    private var currentFindString: String = ""
    private var findDebouncer = FindDebouncer()
    
    // For test support: track navigation completions
    private var navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()


    private var inspectorVisible = false {
        didSet {
            NotificationCenter.default.post(name: .inspectorVisibilityChanged, object: inspectorVisible)
        }
    }
    
    init(services: [Service]? = nil) {
        let window = OverlayWindow(
            contentRect: NSRect(x: 500, y: 200, width: 550, height: 620),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
        let initialServices = services ?? Settings.shared.loadSettings()
        self.services = initialServices
        zoomLevelsByURL = Settings.shared.serviceZoomLevels
        currentServiceName = self.services.first?.name
        currentServiceURL = self.services.first?.url
        self.services.forEach { service in
            activeIndicesByURL[service.url] = 0
            if zoomLevelsByURL[service.url] == nil {
                zoomLevelsByURL[service.url] = Zoom.default
            }
        }
        setupUI()
        self.window?.delegate = self
        addObserver(self, forKeyPath: "window", options: [.new], context: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API
    var serviceCount: Int { services.count }
    var activeServiceURL: String? { currentService()?.url }
    var activeSessionIndex: Int {
        guard let service = currentService() else { return 0 }
        return activeIndicesByURL[service.url] ?? 0
    }

    var activeWebView: WKWebView? {
        guard let service = currentService(),
              let index = activeIndicesByURL[service.url] else {
            return nil
        }
        return getOrCreateWebview(for: service, sessionIndex: index)
    }
    
    /// Wait for the next navigation to complete on the specified WebView.
    /// For test support - allows event-driven waiting instead of manual sleeps.
    func waitForNavigation(on webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            let id = ObjectIdentifier(webView)
            navigationContinuations[id] = continuation
            // Timeout safety: resume after 5s if navigation never completes
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let cont = navigationContinuations.removeValue(forKey: id) {
                    cont.resume()
                }
            }
        }
    }


    @discardableResult
    func selectService(withURL url: String) -> Bool {
        guard let index = services.firstIndex(where: { $0.url == url }) else { return false }
        selectService(at: index)
        return true
    }
    
    // Protocol conformance
    func selectService(at index: Int) {
        selectService(at: index, focusWebView: true)
    }

    func selectService(at index: Int, focusWebView: Bool = true) {
        guard services.indices.contains(index) else { return }
        currentServiceName = services[index].name
        currentServiceURL = services[index].url
        serviceSelector.selectedSegment = index
        NSAccessibility.post(element: serviceSelector!, notification: .valueChanged)
        serviceSelector.setAccessibilityLabel("Active: \(services[index].name)") // Expose for UI testing
        updateActiveWebview(focusWebView: focusWebView)
        updateSessionSelector()
    }

    func switchSession(to index: Int) {
        guard let service = currentService() else { return }
        let bounded = max(0, min(index, 9))
        activeIndicesByURL[service.url] = bounded
        sessionSelector.selectedSegment = segmentIndex(forSession: bounded)
        NSAccessibility.post(element: sessionSelector!, notification: .valueChanged)
        sessionSelector.setAccessibilityLabel("Active Session: \(bounded + 1)")
        updateActiveWebview()
    }

    // Protocol conformance
    func reloadServices() {
        reloadServices(nil)
    }

    func reloadServices(_ services: [Service]? = nil) {
        let newServices = services ?? Settings.shared.loadSettings()
        updateServices(newServices: newServices)
    }

    private func updateServices(newServices: [Service]) {
        zoomLevelsByURL = Settings.shared.serviceZoomLevels

        let incomingURLs = Set(newServices.map { $0.url })
        let existingURLs = Set(webviewsByURL.keys)

        let removedURLs = existingURLs.subtracting(incomingURLs)
        for url in removedURLs {
            if let removedWebviews = webviewsByURL[url] {
                removedWebviews.values.forEach { tearDownWebView($0) }
            }
            webviewsByURL.removeValue(forKey: url)
            activeIndicesByURL.removeValue(forKey: url)
            zoomLevelsByURL.removeValue(forKey: url)
            Settings.shared.clearZoomLevel(for: url)
        }

        for service in newServices where webviewsByURL[service.url] == nil {
            webviewsByURL[service.url] = [:] // Initialize empty dictionary
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
        currentWebView()?.evaluateJavaScript("setTimeout(() => document.querySelector(\"\(selector)\")?.focus(), 0);", completionHandler: nil)
    }

    func performCustomAction(_ action: CustomAction) {
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
            playErrorSound()
        } else {
            script = rawScript
        }

        let wrappedScript = """
        try {
          const wrapper = async () => {
            \(script)
          };
          await wrapper();
          return "ok";
        } catch (err) {
          return { quiperError: (err && err.message) ? err.message : String(err) };
        }
        """

        webView.callAsyncJavaScript(wrappedScript, in: nil, in: .defaultClient) { [weak self] result in
            switch (result) {
            case .success (let value):
                if let dict = value as? [String: Any], let message = dict["quiperError"] as? String {
                    self?.playErrorSound()
                    NSLog("[Quiper] Custom action script failed (caught exception): \(message)")
                    self?.focusInputInActiveWebview()
                    return
                }
            case .failure (let error):
                self?.playErrorSound()
                NSLog("[Quiper] Custom action script failed (error): \(error)")
                self?.focusInputInActiveWebview()
                return
            }
        }
    }
    
    private func playErrorSound() {
        NSSound.beep()
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("QuiperTestBeep"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func currentWebView() -> WKWebView? {
        guard let service = currentService(),
              let index = activeIndicesByURL[service.url] else {
            return nil
        }
        return getOrCreateWebview(for: service, sessionIndex: index)
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

    func handleCommandShortcut(event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt16(event.keyCode)
        let appShortcuts = Settings.shared.appShortcutBindings
        let config = HotkeyManager.Configuration(keyCode: UInt32(keyCode), modifierFlags: modifiers.rawValue)
        
        NSLog("[QuiperDebug] HandleKeyDown: keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue)")

        // Check App Bindings
        if matches(config, appShortcuts.configuration(for: .nextSession)) || matches(config, appShortcuts.alternateConfiguration(for: .nextSession)) {
            stepSession(by: 1)
            return true
        }
        if matches(config, appShortcuts.configuration(for: .previousSession)) || matches(config, appShortcuts.alternateConfiguration(for: .previousSession)) {
            stepSession(by: -1)
            return true
        }
        if matches(config, appShortcuts.configuration(for: .nextService)) || matches(config, appShortcuts.alternateConfiguration(for: .nextService)) {
            stepService(by: 1)
            return true
        }
        if matches(config, appShortcuts.configuration(for: .previousService)) || matches(config, appShortcuts.alternateConfiguration(for: .previousService)) {
            stepService(by: -1)
            return true
        }
        
        // Check Custom Actions
        if let action = Settings.shared.customActions.first(where: { $0.shortcut == config }) {
            performCustomAction(action)
            return true
        }
        
        // Check Service Activation
        if let service = services.first(where: { $0.activationShortcut == config }) {
            selectService(withURL: service.url)
            return true
        }
        
        // Digit shortcuts for sessions and services
        if let digit = digitValue(for: keyCode) {
            if (appShortcuts.sessionDigitsModifiers > 0 && modifiers.rawValue == appShortcuts.sessionDigitsModifiers) ||
                (appShortcuts.sessionDigitsAlternateModifiers.map { $0 > 0 && modifiers.rawValue == $0 } ?? false) {
                let index = digit == 0 ? 9 : digit - 1
                switchSession(to: index)
                return true
            }
            let targetIndex: Int? = {
                if digit == 0 {
                    return services.count >= 10 ? 9 : nil
                }
                return (1...services.count).contains(digit) ? digit - 1 : nil
            }()

            if appShortcuts.serviceDigitsPrimaryModifiers > 0 && modifiers.rawValue == appShortcuts.serviceDigitsPrimaryModifiers {
                if let idx = targetIndex {
                    selectService(at: idx)
                    return true
                }
            }
            if let secondary = appShortcuts.serviceDigitsSecondaryModifiers,
               secondary > 0,
               modifiers.rawValue == secondary {
                if let idx = targetIndex {
                    selectService(at: idx)
                    return true
                }
            }
        }


        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isControl = modifiers.contains(.control)
        let isOption = modifiers.contains(.option)
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isControl && isShift && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        // Remaining built-in shortcuts require Command
        if !isCommand {
            return false
        }

        if isControl || isOption {
            if key == "i" {
                toggleInspector()
                return true
            }
            return false
        }

        switch key {
        case ",":
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return true
        case "h":
            hide()
            return true
        case "w":
            if NSApp.keyWindow == window {
                hide()
                return true
            }
            return false
        case "r":
            reloadActiveWebView(nil)
            return true
        case "f":
            presentFindPanel()
            return true
        case "g":
            handleFindRepeat(shortcutShifted: isShift)
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
    
    private func digitValue(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Keypad0): return 0
        case UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_Keypad1): return 1
        case UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_Keypad2): return 2
        case UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_Keypad3): return 3
        case UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_Keypad4): return 4
        case UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_Keypad5): return 5
        case UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_Keypad6): return 6
        case UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_Keypad7): return 7
        case UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_Keypad8): return 8
        case UInt16(kVK_ANSI_9), UInt16(kVK_ANSI_Keypad9): return 9
        default: return nil
        }
    }

    // MARK: - Private helpers
    private func matches(_ lhs: HotkeyManager.Configuration, _ rhs: HotkeyManager.Configuration?) -> Bool {
        guard let rhs, !rhs.isDisabled else { return false }
        return lhs == rhs
    }

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
            effect.material = .underWindowBackground
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
        // No longer creating all webviews upfront
        webviewsByURL.removeAll()
        activeIndicesByURL.removeAll()
        
        for service in services {
            webviewsByURL[service.url] = [:] // Initialize empty
            activeIndicesByURL[service.url] = 0
        }
        
        createFindBar(in: contentView)
        updateActiveWebview()
    }

    private func createDragArea(in contentView: NSView) {
        let drag = DraggableView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - Constants.DRAGGABLE_AREA_HEIGHT,
            width: contentView.bounds.width,
            height: Constants.DRAGGABLE_AREA_HEIGHT
        ))
        drag.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(drag)
        dragArea = drag

        // Service Selector
        let serviceSel = ServiceSelectorControl(frame: .zero)
        serviceSel.target = self
        serviceSel.action = #selector(serviceChanged(_:))
        serviceSel.mouseDownSegmentHandler = { [weak self] index in
            self?.handleServiceMouseDown(at: index)
        }
        serviceSel.dragBeganHandler = { [weak self] source in
            self?.handleServiceDragBegan(from: source)
        }
        serviceSel.dragChangedHandler = { [weak self] destination in
            self?.handleServiceDragChanged(to: destination)
        }
        serviceSel.dragEndedHandler = { [weak self] in
            self?.handleServiceDragEnded()
        }
        serviceSel.segmentCount = services.count
        for (index, service) in services.enumerated() {
            serviceSel.setLabel(service.name, forSegment: index)
        }
        if let currentName = currentServiceName,
           let idx = services.firstIndex(where: { $0.name == currentName }) {
            serviceSel.selectedSegment = idx
        } else {
            serviceSel.selectedSegment = services.isEmpty ? -1 : 0
        }
        
        serviceSel.setAccessibilityElement(true)
        serviceSel.setAccessibilityIdentifier("ServiceSelector")
        if let currentName = currentServiceName {
            serviceSel.setAccessibilityLabel("Active: \(currentName)")
        }
        drag.addSubview(serviceSel)
        serviceSelector = serviceSel

        // Session Selector
        let sessionSel = NSSegmentedControl(frame: .zero)
        sessionSel.segmentStyle = .rounded
        sessionSel.trackingMode = .selectOne
        sessionSel.segmentCount = 10
        for i in 0..<10 {
            sessionSel.setLabel("\(i == 9 ? 0 : i + 1)", forSegment: i)
            sessionSel.setWidth(24, forSegment: i)
        }
        sessionSel.selectedSegment = 0
        sessionSel.target = self
        sessionSel.action = #selector(sessionChanged(_:))
        sessionSel.setAccessibilityElement(true)
        sessionSel.setAccessibilityIdentifier("SessionSelector")
        sessionSel.setAccessibilityLabel("Active Session: 1")
        drag.addSubview(sessionSel)
        sessionSelector = sessionSel

        // Settings Button
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)

        let settingsBtn = NSButton(image: NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")!.withSymbolConfiguration(iconConfig)!, target: self, action: #selector(settingsButtonTapped(_:)))
        settingsBtn.bezelStyle = .texturedRounded
        settingsBtn.isBordered = false
        settingsBtn.contentTintColor = .secondaryLabelColor
        drag.addSubview(settingsBtn)
        settingsButton = settingsBtn

        // Session Actions Button
        let actionsBtn = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Session Actions")!.withSymbolConfiguration(iconConfig)!, target: self, action: #selector(sessionActionsButtonTapped(_:)))
        actionsBtn.bezelStyle = .texturedRounded
        actionsBtn.isBordered = false
        actionsBtn.contentTintColor = .secondaryLabelColor
        drag.addSubview(actionsBtn)
        sessionActionsButton = actionsBtn

        layoutSelectors()
    }

    private func layoutSelectors() {
        guard let drag = dragArea,
              let serviceSel = serviceSelector,
              let sessionSel = sessionSelector,
              let settingsBtn = settingsButton,
              let actionsBtn = sessionActionsButton else { return }

        let headerHeight = drag.bounds.size.height
        let selectorHeight: CGFloat = 25
        let inset: CGFloat = 4 // shared padding for edges and gaps
        let gap: CGFloat = 4   // consistent gap between controls
        let buttonSize: CGFloat = 24
        let minimumServiceWidth: CGFloat = 150

        // Settings button on the RIGHT
        settingsBtn.frame = NSRect(
            x: drag.bounds.width - inset - buttonSize,
            y: (headerHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        // Session actions button just left of settings
        actionsBtn.frame = NSRect(
            x: settingsBtn.frame.minX - gap - buttonSize,
            y: (headerHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        // Natural widths
        let naturalSessionWidth = sessionSel.intrinsicContentSize.width
        let estimatedServiceWidth = max(180, estimatedWidthForServiceSegments() + 20)

        // Size service selector first, leaving room for the session selector’s natural width
        let maxServiceWidth = max(minimumServiceWidth,
                                  actionsBtn.frame.minX - gap - inset - naturalSessionWidth - gap)
        let serviceWidth = min(estimatedServiceWidth, maxServiceWidth)

        serviceSel.frame = NSRect(
            x: inset,
            y: (headerHeight - selectorHeight) / 2,
            width: serviceWidth,
            height: selectorHeight
        )

        // Session selector fills remaining space up to the action button (no extra gap)
        let sessionStart = serviceSel.frame.maxX + gap
        let availableForSession = actionsBtn.frame.minX - gap - sessionStart
        let sessionWidth = max(0, min(naturalSessionWidth, availableForSession))
        let sessionX = actionsBtn.frame.minX - gap - sessionWidth
        sessionSel.frame = NSRect(
            x: sessionX,
            y: (headerHeight - selectorHeight) / 2,
            width: sessionWidth,
            height: selectorHeight
        )

        layoutFindBar()
    }

    // Removed createWebviews and createWebviewStack as they are replaced by lazy loading

    private func getOrCreateWebview(for service: Service, sessionIndex: Int) -> WKWebView {
        if let existing = webviewsByURL[service.url]?[sessionIndex] {
            return existing
        }
        
        // Create new WebView
        guard let contentView = contentContainerView ?? window?.contentView else {
            fatalError("ContentView not available")
        }
        
        let availableHeight = contentView.bounds.height - Constants.DRAGGABLE_AREA_HEIGHT
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

        let webview = WKWebView(frame: frame, configuration: config)
        webview.autoresizingMask = [.width, .height]
        webview.uiDelegate = self
        webview.navigationDelegate = self
        webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webview.isHidden = true // Start hidden
        webview.pageZoom = zoomLevelsByURL[service.url] ?? Zoom.default
        
        // Enable robust accessibility verification for UI tests by mapping title -> accessibilityLabel
        let observation = webview.observe(\.title, options: [.initial, .new]) { webview, _ in
            webview.setAccessibilityLabel(webview.title)
        }
        titleObservations[ObjectIdentifier(webview)] = observation
        
        attachNotificationBridge(to: webview, service: service, sessionIndex: sessionIndex)

        // Add to view hierarchy
        contentView.addSubview(webview, positioned: .below, relativeTo: dragArea)
        
        // Store it
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
            // Ensure focus runs after the first load completes
            let token = ObjectIdentifier(webview)
            initialLoadAwaitingFocus.insert(token)
        }
        
        return webview
    }

    private func createFindBar(in contentView: NSView) {
        // ... (remains same) ...
        let bar = NSVisualEffectView(frame: .zero)
        bar.material = .menu
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 10
        bar.layer?.masksToBounds = true
        bar.isHidden = true

        let field = NSSearchField(frame: .zero)
        field.placeholderString = "Find in page"
        field.delegate = self
        field.target = self
        field.font = NSFont.systemFont(ofSize: 13)
        if let cell = field.cell as? NSSearchFieldCell {
            cell.sendsSearchStringImmediately = true
            cell.sendsWholeSearchString = false
        }

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail

        let prevButton = NSButton(title: "‹", target: self, action: #selector(findPreviousTapped))
        prevButton.bezelStyle = .roundRect
        prevButton.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let nextButton = NSButton(title: "›", target: self, action: #selector(findNextTapped))
        nextButton.bezelStyle = .roundRect
        nextButton.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        bar.addSubview(field)
        bar.addSubview(status)
        bar.addSubview(prevButton)
        bar.addSubview(nextButton)

        contentView.addSubview(bar, positioned: .above, relativeTo: nil)

        findBar = bar
        findField = field
        findStatusLabel = status
        findPreviousButton = prevButton
        findNextButton = nextButton
        layoutFindBar()
    }

    // ... (layoutFindBar remains same) ...
    private func layoutFindBar() {
        guard let contentView = contentContainerView ?? window?.contentView,
              let bar = findBar,
              let field = findField,
              let status = findStatusLabel,
              let prev = findPreviousButton,
              let next = findNextButton else { return }

        let barWidth: CGFloat = 360
        let barHeight: CGFloat = 46
        let padding: CGFloat = 12
        let buttonWidth: CGFloat = 32
        let buttonHeight: CGFloat = 24

        let originX = contentView.bounds.width - barWidth - padding
        let originY = contentView.bounds.height - Constants.DRAGGABLE_AREA_HEIGHT - barHeight - padding
        bar.frame = NSRect(x: originX, y: originY, width: barWidth, height: barHeight)

        field.frame = NSRect(
            x: padding,
            y: (barHeight - buttonHeight) / 2,
            width: 170,
            height: buttonHeight
        )

        let statusWidth: CGFloat = 90
        status.frame = NSRect(
            x: field.frame.maxX + 8,
            y: (barHeight - 18) / 2,
            width: statusWidth,
            height: 18
        )

        prev.frame = NSRect(
            x: status.frame.maxX + 6,
            y: (barHeight - buttonHeight) / 2,
            width: buttonWidth,
            height: buttonHeight
        )

        next.frame = NSRect(
            x: prev.frame.maxX + 4,
            y: prev.frame.minY,
            width: buttonWidth,
            height: buttonHeight
        )
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
        guard let service = currentService() else { return }
        
        let activeIndex = activeIndicesByURL[service.url] ?? 0
        
        // Hide all existing webviews
        webviewsByURL.values.forEach { sessionMap in
            sessionMap.values.forEach { $0.isHidden = true }
        }
        
        // Get or create the active one
        let activeWebview = getOrCreateWebview(for: service, sessionIndex: activeIndex)
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
        sessionSelector.setAccessibilityLabel("Active Session: \(index + 1)")
    }

    private func stepSession(by delta: Int) {
        guard let service = currentService() else { return }
        let current = activeIndicesByURL[service.url] ?? 0
        let next = (current + delta + 10) % 10
        switchSession(to: next)
    }

    private func stepService(by delta: Int) {
        guard !services.isEmpty else { return }
        let currentIndex = services.firstIndex(where: { $0.url == currentServiceURL }) ??
                           services.firstIndex(where: { $0.name == currentServiceName }) ??
                           0
        let next = (currentIndex + delta + services.count) % services.count
        selectService(at: next)
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
        let identifier = ObjectIdentifier(webView)
        titleObservations[identifier]?.invalidate()
        titleObservations.removeValue(forKey: identifier)
        
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
        menu.addItem(menuItem(title: "Find…",
                              iconName: "magnifyingglass",
                              keyEquivalent: "f",
                              modifiers: .command,
                              action: #selector(presentFindPanelFromMenu)))
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

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Hide Window",
                              iconName: "eye.slash",
                              keyEquivalent: "w",
                              modifiers: .command,
                              alwaysEnabled: true,
                              action: #selector(performMenuHideWindow)))
        menu.addItem(menuItem(title: "Quit",
                              iconName: "power",
                              keyEquivalent: "q",
                              modifiers: [.command, .control, .shift],
                              alwaysEnabled: true,
                              action: #selector(performMenuQuit)))

        let enabled = currentWebView() != nil
        for item in menu.items {
            if item.isSeparatorItem ||
                item.representedObject is CustomAction ||
                (item.representedObject as? MenuItemTag) == .alwaysEnabled ||
                !item.isEnabled {
                continue
            }
            item.isEnabled = enabled
        }
        return menu
    }

    private var initialLoadAwaitingFocus = Set<ObjectIdentifier>()

    private func menuItem(title: String,
                          iconName: String? = nil,
                          keyEquivalent: String = "",
                          modifiers: NSEvent.ModifierFlags = [],
                          alwaysEnabled: Bool = false,
                          action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        if let iconName,
           let image = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            image.isTemplate = true
            item.image = image
        }
        if alwaysEnabled {
            item.representedObject = MenuItemTag.alwaysEnabled
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

    private enum MenuItemTag {
        case alwaysEnabled
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

    @objc private func performMenuHideWindow(_ sender: Any?) {
        hide()
    }

    @objc private func performMenuQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func reloadActiveWebView(_ sender: Any?) {
        guard let service = currentService(),
              let webView = currentWebView(),
              let url = URL(string: service.url) else { return }
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func presentFindPanelFromMenu(_ sender: Any?) {
        presentFindPanel()
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

    @objc func performCustomActionFromMenu(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CustomAction else { return }
        NSLog("[QuiperDebug] Menu Item Triggered Action: \(action.name)")
        performCustomAction(action)
    }

    func zoom(by delta: CGFloat) {
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
            webviews.values.forEach { $0.pageZoom = value }
        }
        Settings.shared.storeZoomLevel(value, for: service.url)
    }

    private func presentFindPanel() {
        showFindBar()
    }

    private func closeFindPanelIfNeeded() -> Bool {
        guard isFindBarVisible else { return false }
        hideFindBar()
        return true
    }

}

private extension MainWindowController {
    func showFindBar() {
        guard let bar = findBar, let field = findField else { return }
        bar.isHidden = false
        isFindBarVisible = true
        window?.makeFirstResponder(field)
        if field.stringValue.isEmpty {
            field.stringValue = currentFindString
        }
        if let editor = field.currentEditor() {
            editor.selectAll(nil)
        }
        updateFindStatus(matchFound: nil, index: nil, total: nil)
    }

    func hideFindBar() {
        currentFindString = findField?.stringValue ?? currentFindString
        findBar?.isHidden = true
        isFindBarVisible = false
        findStatusLabel?.stringValue = ""
        resetFind()
        window?.makeFirstResponder(currentWebView())
    }
    
    func handleFindRepeat(shortcutShifted: Bool) {
        guard let field = findField else {
            presentFindPanel()
            return
        }
        if !isFindBarVisible {
            showFindBar()
            window?.makeFirstResponder(currentWebView())
        }
        let trimmedField = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedField.isEmpty {
            if currentFindString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                window?.makeFirstResponder(field)
                NSSound.beep()
                return
            }
            field.stringValue = currentFindString
        }
        performFind(forward: !shortcutShifted)
    }

    func updateFindStatus(matchFound: Bool?, index: Int?, total: Int?) {
        guard let label = findStatusLabel else { return }
        guard let matchFound else {
            label.stringValue = currentFindString.isEmpty ? "" : "No matches"
            return
        }

        if !matchFound {
            label.stringValue = "No matches"
            return
        }

        if let idx = index, let total, total > 0 {
            label.stringValue = "\(idx) of \(total)"
        } else {
            label.stringValue = "Match found"
        }
    }

    func performFind(forward: Bool, newSearch: Bool = false) {
        guard let webView = currentWebView() else { return }
        
        let searchString = findField?.stringValue ?? ""
        if newSearch && searchString == currentFindString {
            return
        }
        
        currentFindString = searchString
        let trimmed = currentFindString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetFind()
            return
        }
        
        let escaped = escapeForJavaScript(trimmed)
        let resetSelection = newSearch ? "true" : "false"
        let backwards = forward ? "false" : "true"
        let script = """
        (() => {
            const search = "\(escaped)";
            const backwards = \(backwards);
            let forceReset = \(resetSelection);
            const root = document.body || document.documentElement;
            const selection = window.getSelection();
            if (!root || !selection) {
                return { match: false, current: 0, total: 0 };
            }
            if (!document.getElementById("__quiperFindSelectionStyle")) {
                const style = document.createElement("style");
                style.id = "__quiperFindSelectionStyle";
                style.textContent = `
                    ::selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                    ::-moz-selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                `;
                (document.head || document.body || document.documentElement).appendChild(style);
            }
            const textContent = root.innerText || root.textContent || "";
            const escapedPattern = search.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&");
            const regex = escapedPattern ? new RegExp(escapedPattern, "gi") : null;
            if (!window.__quiperFindState) {
                window.__quiperFindState = { search: "", total: 0, index: 0 };
            }
            const state = window.__quiperFindState;
            if (state.search !== search) {
                state.search = search;
                forceReset = true;
            }
            if (!search) {
                state.total = 0;
                state.index = 0;
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            if (forceReset) {
                state.total = regex ? (textContent.match(regex) || []).length : 0;
                state.index = backwards ? state.total + 1 : 0;
                selection.removeAllRanges();
                const range = document.createRange();
                range.selectNodeContents(root);
                range.collapse(!backwards);
                selection.addRange(range);
            }
            const total = state.total;
            if (!total) {
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            const match = window.find(search, false, backwards, true, false, true, false);
            if (!match) {
                return { match: false, current: 0, total };
            }
            if (backwards) {
                state.index = state.index <= 1 ? total : state.index - 1;
            } else {
                state.index = state.index >= total ? 1 : state.index + 1;
            }
            const selectionNode = selection.focusNode && selection.focusNode.nodeType === Node.TEXT_NODE
                ? selection.focusNode.parentElement
                : selection.focusNode;
            if (selectionNode && selectionNode.scrollIntoView) {
                selectionNode.scrollIntoView({ block: 'center', inline: 'nearest' });
            }
            return { match: true, current: state.index, total };
        })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard error == nil else {
                self?.updateFindStatus(matchFound: false, index: nil, total: nil)
                return
            }
            if let dict = result as? [String: Any],
               let match = dict["match"] as? Bool {
                let current = dict["current"] as? Int
                let total = dict["total"] as? Int
                self?.updateFindStatus(matchFound: match, index: current, total: total)
            } else {
                self?.updateFindStatus(matchFound: false, index: nil, total: nil)
            }
        }
    }
    
    func resetFind() {
        updateFindStatus(matchFound: nil, index: nil, total: nil)
        let script = """
        (() => {
          if (window.__quiperFindState) {
              window.__quiperFindState.search = "";
              window.__quiperFindState.total = 0;
              window.__quiperFindState.index = 0;
          }
          const sel = window.getSelection();
          if (sel) { sel.removeAllRanges(); }
        })();
        """
        currentWebView()?.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc func findPreviousTapped() {
        performFind(forward: false)
    }

    @objc func findNextTapped() {
        performFind(forward: true)
    }
    
    private func serviceURL(for webView: WKWebView) -> URL? {
        for (urlString, webViews) in webviewsByURL {
            if webViews.values.contains(webView) {
                return URL(string: urlString)
            }
        }
        return nil
    }

    private func isInternalLink(target: URL, service: URL, friendPatterns: [String]) -> Bool {
        guard let targetHost = target.host?.lowercased(),
              let serviceHost = service.host?.lowercased() else {
            return false
        }
        
        if targetHost == serviceHost { return true }
        
        // Strip www. from service host to get root (heuristic)
        let rootServiceHost = serviceHost.hasPrefix("www.") ? String(serviceHost.dropFirst(4)) : serviceHost
        
        // Allow if target is the root host or a subdomain (ends with .root)
        if targetHost == rootServiceHost || targetHost.hasSuffix("." + rootServiceHost) {
            return true
        }

        // Friend domains via regex patterns
        for pattern in friendPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: target.absoluteString.utf16.count)
            if regex.firstMatch(in: target.absoluteString, options: [], range: range) != nil {
                return true
            }
        }

        return false
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

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let serviceURL = serviceURL(for: webView),
              let service = services.first(where: { $0.url == serviceURL.absoluteString }) else {
            decisionHandler(.allow)
            return
        }

        // Only intercept user-initiated navigations; keep programmatic/internal loads in-app.
        if navigationAction.navigationType == .linkActivated {
            let targetFrameIsMain = navigationAction.targetFrame?.isMainFrame ?? true
            let allowInApp = isInternalLink(target: url, service: serviceURL, friendPatterns: service.friendDomains)

            if allowInApp {
                decisionHandler(.allow)
                return
            }

            if targetFrameIsMain {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let token = ObjectIdentifier(webView)
        
        // Resume any waiting continuation for this WebView (do this FIRST, before any guards)
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        
        guard let url = serviceURL(for: webView),
              url.absoluteString == currentServiceURL else { return }

        window?.makeFirstResponder(webView)

        let runFocus: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.focusInputInActiveWebview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.focusInputInActiveWebview()
            }
        }

        if initialLoadAwaitingFocus.contains(token) {
            initialLoadAwaitingFocus.remove(token)
            // First load of this webview
            DispatchQueue.main.async(execute: runFocus)
        } else {
            // Subsequent reloads
            DispatchQueue.main.async(execute: runFocus)
        }
    }
}

extension MainWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field == findField else { return }
        findDebouncer.debounce()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control == findField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            performFind(forward: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideFindBar()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            performFind(forward: false)
            return true
        }
        return false
    }
}

private final class FindDebouncer: NSObject {
    private var timer: Timer?
    var callback: (() -> Void)?
    
    func debounce(interval: TimeInterval = 0.3) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(timerFired),
                                     userInfo: nil,
                                     repeats: false)
    }
    
    @objc private func timerFired() {
        callback?()
    }
}

enum Zoom {
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
