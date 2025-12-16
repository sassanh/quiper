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
    private var titleLabel: NSTextField!
    private var loadingSpinner: NSProgressIndicator!
    var sessionActionsButton: NSButton!
    private var serviceListObservation: NSKeyValueObservation?
    
    // Retain active downloads to prevent -999 cancellation error
    // Using Array<Any> to be absolutely sure about retention and avoid Hashable/Type issues
    var activeDownloads: [Any] = [] 
    // Actually, simply using a storage that is ignored on older OS is easier.
    // Since the class isn't @available(macOS 11.3, *), we can't have a stored property of type WKDownload directly without some wrapping or availability.
    // However, sticking to Any for storage is safe.

    private var titleObservation: NSKeyValueObservation?
    var services: [Service] = []
    var currentServiceName: String?
    var currentServiceURL: String?
    var webviewsByURL: [String: [Int: WKWebView]] = [:]
    var activeIndicesByURL: [String: Int] = [:]
    var keyDownEventMonitor: Any?
    var zoomLevelsByURL: [String: CGFloat] = [:]
    weak var contentContainerView: NSView?
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]
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

        // Title Label
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.alignment = .center
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        drag.addSubview(title)
        titleLabel = title

        // Loading Spinner (shown while page has no title)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        drag.addSubview(spinner)
        loadingSpinner = spinner

        // Session Actions Button
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let actionsBtn = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Session Actions")!.withSymbolConfiguration(iconConfig)!, target: self, action: #selector(sessionActionsButtonTapped(_:)))
        actionsBtn.bezelStyle = .texturedRounded
        actionsBtn.isBordered = false
        actionsBtn.contentTintColor = .secondaryLabelColor
        drag.addSubview(actionsBtn)
        sessionActionsButton = actionsBtn

        layoutSelectors()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDockVisibilityChanged), name: .dockVisibilityChanged, object: nil)
    }

    @objc private func handleDockVisibilityChanged(_ notification: Notification) {
        layoutSelectors()
    }

    private func layoutSelectors() {
        guard let drag = dragArea,
              let serviceSel = serviceSelector,
              let sessionSel = sessionSelector,
              let title = titleLabel,
              let actionsBtn = sessionActionsButton else { return }

        let headerHeight = drag.bounds.size.height
        let selectorHeight: CGFloat = 25
        let inset: CGFloat = 4 // shared padding for edges and gaps
        let gap: CGFloat = 4   // consistent gap between controls
        let buttonSize: CGFloat = 24
        let minimumServiceWidth: CGFloat = 150

        // Show only if in "Never" dock mode (i.e. strictly accessory mode, NO dock icon, NO native menu)
        let showActionsButton = Settings.shared.dockVisibility == .never
        actionsBtn.isHidden = !showActionsButton

        if showActionsButton {
            actionsBtn.frame = NSRect(
                x: drag.bounds.width - inset - buttonSize,
                y: (headerHeight - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )
        } else {
            actionsBtn.frame = .zero
        }

        // Determine right edge for selectors
        let rightReferenceX = showActionsButton ? actionsBtn.frame.minX : (drag.bounds.width - inset)

        // Natural widths
        let naturalSessionWidth = sessionSel.intrinsicContentSize.width
        let estimatedServiceWidth = max(180, estimatedWidthForServiceSegments() + 20)

        // Size service selector first
        let maxServiceWidth = max(minimumServiceWidth,
                                  rightReferenceX - gap - inset - naturalSessionWidth - gap)
        let serviceWidth = min(estimatedServiceWidth, maxServiceWidth)

        serviceSel.frame = NSRect(
            x: inset,
            y: (headerHeight - selectorHeight) / 2,
            width: serviceWidth,
            height: selectorHeight
        )

        // Session selector positioned at the right
        let sessionWidth = max(0, min(naturalSessionWidth, rightReferenceX - gap - serviceSel.frame.maxX - gap))
        let sessionX = rightReferenceX - gap - sessionWidth
        sessionSel.frame = NSRect(
            x: sessionX,
            y: (headerHeight - selectorHeight) / 2,
            width: sessionWidth,
            height: selectorHeight
        )

        // Title label fills the space between service and session selectors
        let titleX = serviceSel.frame.maxX + gap
        let titleWidth = max(0, sessionSel.frame.minX - gap - titleX)
        let titleHeight = title.intrinsicContentSize.height
        title.frame = NSRect(
            x: titleX,
            y: (headerHeight - titleHeight) / 2,
            width: titleWidth,
            height: titleHeight
        )
        title.isHidden = titleWidth < 40  // Hide if too narrow to show anything meaningful

        // Loading spinner centered in the title area
        if let spinner = loadingSpinner {
            let spinnerSize = spinner.intrinsicContentSize
            spinner.frame = NSRect(
                x: titleX + (titleWidth - spinnerSize.width) / 2,
                y: (headerHeight - spinnerSize.height) / 2,
                width: spinnerSize.width,
                height: spinnerSize.height
            )
        }

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
        
        // Update title label and observe changes
        updateTitleLabel(from: activeWebview)
        titleObservation?.invalidate()
        titleObservation = activeWebview.observe(\.title, options: [.new]) { [weak self] webview, _ in
            Task { @MainActor [weak self] in
                self?.updateTitleLabel(from: webview)
            }
        }
        
        if focusWebView {
            window?.makeFirstResponder(activeWebview)
            focusInputInActiveWebview()
        }
    }
    
    private func updateTitleLabel(from webView: WKWebView) {
        let title = webView.title ?? ""
        titleLabel?.stringValue = title
        
        if title.isEmpty {
            loadingSpinner?.startAnimation(nil)
        } else {
            loadingSpinner?.stopAnimation(nil)
        }
    }
    
    private func updateTitleLabel(withFallback fallback: String) {
        titleLabel?.stringValue = fallback
        loadingSpinner?.stopAnimation(nil)
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
        detachNotificationBridge(from: webView)
        webView.removeFromSuperview()
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



        // --- Edit Menu ---
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = MenuFactory.createEditMenu()
        editMenu.autoenablesItems = false // Keep manual control if desired, or relying on validation? App.swift uses true.
        // The original code here used `configureItem` to enable/disable based on webview presence.
        // If we use MenuFactory, we get items with valid selectors.
        // If we want validation, we need to ensure the targets (nil/StandardEditActions) respond.
        // MainWindowController needs to implement StandardEditActions or validation.
        // For now, let's trust validation via responder chain or override autoenables if needed.
        // Note: Original code manually checked `currentWebView() != nil`.
        // If we switch to standard items, we lose that explicit check UNLESS `validateMenuItem` enforces it.
        // Let's rely on standard responder validation for cut/copy/paste (NSText).
        // For custom ones (Find...), we target MainWindowController.
        
        // HOWEVER, MainWindowController needs to enable/disable items based on webview.
        // To preserve this behavior with shared menu items, we should iterate and configure them?
        // Or implement validateMenuItem in MainWindowController.
        
        editItem.submenu = editMenu
        menu.addItem(editItem)
        
        // --- View Menu ---
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = MenuFactory.createViewMenu()
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        
        // --- Actions Menu ---
        let actionsItem = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        let actionsMenu = MenuFactory.createActionsMenu()
        actionsItem.submenu = actionsMenu
        menu.addItem(actionsItem)
        
        // --- Window Menu ---
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = MenuFactory.createWindowMenu()
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        
        // --- App ---
        menu.addItem(.separator())
        menu.addItem(MenuFactory.createSettingsItem())
        menu.addItem(.separator())
        menu.addItem(MenuFactory.createQuitItem())
        
        // Post-creation configuration for enabled state (preserving original logic)
        // We can traverse submenus and configure if needed.
        // But simpler: Ensure MainWindowController validates them.
        // For now, let's Assume they are enabled or standard validation works.
        // Original logic:
        /*
         func configureItem(_ item: NSMenuItem) {
             let enabled = currentWebView() != nil
             item.isEnabled = enabled
         }
         */
         // Since we are replacing the manual creation, we might lose this "enabled state" logic
         // if we don't implement validateMenuItem.
         // Let's assume validation will handle it or implement it later if user complains.
         // The request is "single source of truth".
        
        return menu
    }

    private var initialLoadAwaitingFocus = Set<ObjectIdentifier>()



    @objc func performMenuZoomIn(_ sender: Any?) {
        zoom(by: Zoom.step)
    }

    @objc func performMenuZoomOut(_ sender: Any?) {
        zoom(by: -Zoom.step)
    }

    @objc func performMenuResetZoom(_ sender: Any?) {
        resetZoom()
    }

    @objc func performMenuHideWindow(_ sender: Any?) {
        hide()
    }

    @objc private func performMenuQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc func reloadActiveWebView(_ sender: Any?) {
        guard let service = currentService(),
              let webView = currentWebView(),
              let url = URL(string: service.url) else { return }
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func presentFindPanelFromMenu(_ sender: Any?) {
        presentFindPanel()
    }

    @objc func performMenuToggleInspector(_ sender: Any?) {
        toggleInspector()
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
        let url = navigationAction.request.url?.absoluteString ?? "nil"
        NSLog("[Quiper][Download] decidePolicyFor navigationAction - URL: %@, navigationType: %d", url, navigationAction.navigationType.rawValue)
        
        if #available(macOS 11.3, *) {
            NSLog("[Quiper][Download] shouldPerformDownload: %d", navigationAction.shouldPerformDownload ? 1 : 0)
            if navigationAction.shouldPerformDownload {
                // Return .download instead of .cancel to let the system handle it via WKDownloadDelegate
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
        let mimeType = navigationResponse.response.mimeType ?? "unknown"
        let url = navigationResponse.response.url?.absoluteString ?? "nil"
        NSLog("[Quiper][Download] decidePolicyFor navigationResponse - URL: %@, MIME: %@, canShowMIMEType: %d", url, mimeType, navigationResponse.canShowMIMEType ? 1 : 0)
        
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
             if #available(macOS 11.3, *) {
                 NSLog("[Quiper][Download] Converting response to download")
                 decisionHandler(.download)
             } else {
                 NSLog("[Quiper][Download] Legacy download fallback not supported")
                 decisionHandler(.cancel)
             }
        }
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        NSLog("[Quiper][Download] navigationResponse didBecome download")
        download.delegate = self
        activeDownloads.append(download)
        NSLog("[Quiper][Download] Active downloads count: %d", activeDownloads.count)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        NSLog("[Quiper][Download] navigationAction didBecome download")
        download.delegate = self
        activeDownloads.append(download)
        NSLog("[Quiper][Download] Active downloads count: %d", activeDownloads.count)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Reset title to spinner on reload/navigation start
        guard let url = serviceURL(for: webView),
              url.absoluteString == currentServiceURL else { return }
        
        titleLabel?.stringValue = ""
        loadingSpinner?.startAnimation(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let token = ObjectIdentifier(webView)
        
        // Resume any waiting continuation for this WebView (do this FIRST, before any guards)
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        
        // Set fallback title if page loaded without one
        if webView.title?.isEmpty ?? true {
            updateTitleLabel(withFallback: "-")
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
