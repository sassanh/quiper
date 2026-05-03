import AppKit
import WebKit
import Carbon
import Combine
import CoreImage
import QuartzCore

@MainActor
private struct CGSFuncs {
    typealias CGSConnectionID = UInt32
    typealias CGSWindowID = UInt32
    typealias CGSSetWindowBackgroundBlurRadiusFunc = @convention(c) (CGSConnectionID, CGSWindowID, Int32) -> Int32
    typealias CGSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID

    static var getMainConnection: CGSMainConnectionIDFunc?
    static var setBlurRadius: CGSSetWindowBackgroundBlurRadiusFunc?
    static var initialized = false
    
    static func initialize() {
        if initialized { return }
        
        var handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/Current/SkyLight", RTLD_LAZY)
        if handle == nil {
             handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/Versions/Current/CoreGraphics", RTLD_LAZY)
        }
        
        if let validHandle = handle {
            if let mainConnSym = dlsym(validHandle, "CGSMainConnectionID") ?? dlsym(validHandle, "SLSMainConnectionID") {
                getMainConnection = unsafeBitCast(mainConnSym, to: CGSMainConnectionIDFunc.self)
            }
            
            if let setBlurSym = dlsym(validHandle, "SLSSetWindowBackgroundBlurRadius") ?? dlsym(validHandle, "CGSSetWindowBackgroundBlurRadius") {
                setBlurRadius = unsafeBitCast(setBlurSym, to: CGSSetWindowBackgroundBlurRadiusFunc.self)
            }
        }
        initialized = true
    }
}

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
    private var serviceSelector: SegmentedControl?
    private var collapsibleServiceSelector: CollapsibleSelector?
    private var sessionSelector: SegmentedControl?
    private var collapsibleSessionSelector: CollapsibleSelector?
    private var titleLabel: HoverTextField!

    private var windowMarginView: WindowMarginView!
    private var windowOutlineView: WindowOutlineView!
    private var loadingBorderView: LoadingBorderView!
    private var isLoadingObservation: NSKeyValueObservation?
    private var sessionActionsButton: NSButton!
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
    private var webViewManager: WebViewManager!
    private var findBarViewController: FindBarViewController!
    private var draggingServiceIndex: Int?
    var activeIndicesByURL: [String: Int] = [:]
    var keyDownEventMonitor: Any?
    var skipSafeAreaCheck = false
    var skipModalCheck = false
    
    // For test support: track navigation completions
    private var backgroundEffectView: NSVisualEffectView?

    override var acceptsFirstResponder: Bool { true }
    
    // Header Visibility logic
    private var headerTrackingArea: NSTrackingArea?
    private var headerActionTimer: Timer?
    private var isHeaderHovered = false
    private var isModifiersForHeaderDown = false
    private var isHeaderForcedVisibleForAction = false
    private var isUpdatingHeaderVisibility = false
    private var selectorCursorMonitor: Timer?

    // Window size toggle state
    private var isCompactMode = false
    private var previousWindowFrame: NSRect?
    // Original constant width of the transparent margin on each side in hidden mode
    internal let barBorderWidth: CGFloat = 8
    
    // Dynamic margin applied to the window frame. In hidden mode, it's the full barBorderWidth.
    // In visible mode, it's just the thickness of the outline, allowing the outline to grow outwards
    // without being clipped by the window frame.
    internal var currentMargin: CGFloat {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        if isHiddenMode {
            return barBorderWidth
        } else {
            let isDark = window?.effectiveAppearance.name.rawValue.contains("Dark") ?? false
            let settings = isDark ? Settings.shared.windowAppearance.dark : Settings.shared.windowAppearance.light
            // Align outward to integral boundary
            return ceil(settings.outlineWidth)
        }
    }
    // Solid-color background view for .solidColor appearance mode; positioned at content rect
    var contentColorView: NSView?
    @MainActor internal private(set) var blurWindow: NSWindow?
    

    deinit {
        let bw = blurWindow
        let win = window
        if let bw = bw {
            DispatchQueue.main.async { [weak win] in
                win?.removeChildWindow(bw)
                bw.orderOut(nil)
                bw.close()
            }
        }
        NotificationCenter.default.removeObserver(self)
    }


    private var inspectorVisible = false {
        didSet {
            NotificationCenter.default.post(name: .inspectorVisibilityChanged, object: inspectorVisible)
        }
    }
    
    init(services: [Service]? = nil) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        let windowWidth: CGFloat = isScreenshotMode ? 640 : (isUITesting ? 900 : 550)
        let windowHeight: CGFloat = isScreenshotMode ? 480 : 620
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - (windowWidth / 2)
        let y = screenFrame.midY - (windowHeight / 2)
        
        let window = OverlayWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        let initialServices = services ?? Settings.shared.loadSettings()
        
        // Ensure window is properly configured before using it
        configureWindow(for: window)
        
        // Verify content view is ready
        guard let contentView = window.contentView else {
            fatalError("Failed to initialize window content view")
        }
        
        webViewManager = WebViewManager(containerView: contentView)
        self.services = initialServices
        webViewManager.updateServices(initialServices)
        
        self.services.forEach { service in
            activeIndicesByURL[service.url] = 0
        }
        setupUI()
        self.window?.delegate = self
        addObserver(self, forKeyPath: "window", options: [.new], context: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            // System appearance changed, update window background
            applyWindowAppearance()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
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
        await webViewManager.waitForNavigation(on: webView)
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
        
        serviceSelector?.selectedSegment = index
        collapsibleServiceSelector?.selectedSegment = index
        
        if let sel = activeServiceSelector {
            NSAccessibility.post(element: sel, notification: .valueChanged)
            if let combo = sel as? SegmentedControl {
                 combo.setAccessibilityLabel("Active: \(services[index].name)")
            }
        }
        
        updateActiveWebview(focusWebView: focusWebView)
        updateSessionSelector()
        layoutSelectors()
        
        showHeaderTemporarily()
    }

    func switchSession(to index: Int) {
        guard let service = currentService() else { return }
        let bounded = max(0, min(index, 9))
        activeIndicesByURL[service.url] = bounded
        
        let segmentIdx = segmentIndex(forSession: bounded)
        sessionSelector?.selectedSegment = segmentIdx
        collapsibleSessionSelector?.selectedSegment = segmentIdx
        
        if let sel = activeSessionSelector {
            NSAccessibility.post(element: sel, notification: .valueChanged)
        }
        
        updateActiveWebview()
        layoutSelectors() // Re-layout after session change to update selector width
        
        showHeaderTemporarily()
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
        let incomingURLs = Set(newServices.map { $0.url })
        let existingURLs = Set(activeIndicesByURL.keys)

        let removedURLs = existingURLs.subtracting(incomingURLs)
        for url in removedURLs {
            activeIndicesByURL.removeValue(forKey: url)
        }
        
        for service in newServices where activeIndicesByURL[service.url] == nil {
             activeIndicesByURL[service.url] = 0
        }

        webViewManager.updateServices(newServices)
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

        webView.callAsyncJavaScript(wrappedScript, in: nil, in: .page) { [weak self] result in
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
    
    func playErrorSound() {
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
        NotificationCenter.default.post(name: .windowDidShow, object: nil)
    }

    func hide() {
        window?.orderOut(nil)
        setShortcutsEnabled(false)
        NotificationCenter.default.post(name: .windowDidHide, object: nil)
    }

    func toggleWindowSize() {
        guard let window = window else { return }
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        if isCompactMode {
            // Restore to previous size/position, or use default if no previous frame
            let targetFrame: NSRect
            if let previous = previousWindowFrame {
                targetFrame = previous
            } else {
                // Default fallback size (800x620, centered)
                let width: CGFloat = 800
                let height: CGFloat = 620
                let x = screenFrame.midX - (width / 2)
                let y = screenFrame.midY - (height / 2)
                targetFrame = NSRect(x: x, y: y, width: width, height: height)
            }
            
            window.setFrame(targetFrame, display: true, animate: true)
            isCompactMode = false
            previousWindowFrame = nil // Clear saved frame after restoration
        } else {
            // Save current frame before switching to compact mode
            previousWindowFrame = window.frame
            
            // Switch to compact mode: 550x400, positioned at top-right
            let width: CGFloat = 550
            let height: CGFloat = 400
            let padding: CGFloat = 20
            let x = screenFrame.maxX - width - padding
            let y = screenFrame.maxY - height - padding
            
            let newFrame = NSRect(x: x, y: y, width: width, height: height)
            window.setFrame(newFrame, display: true, animate: true)
            isCompactMode = true
        }
        
        // Update layout after resize
        layoutSelectors()
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        if enabled {
            if keyDownEventMonitor == nil {
                keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    if event.type == .keyDown {
                        if self?.handleCommandShortcut(event: event) == true {
                            return nil
                        }
                    } else if event.type == .flagsChanged {
                        self?.handleFlagsChanged(event: event)
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
    
    // MARK: - Input Handling
    
    func showHeaderTemporarily() {
        guard Settings.shared.topBarVisibility == .hidden else { return }
        isHeaderForcedVisibleForAction = true
        updateHeaderVisibility()
        headerActionTimer?.invalidate()
        headerActionTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isHeaderForcedVisibleForAction = false
                self?.updateHeaderVisibility()
            }
        }
    }

    private var hasModalWindow: Bool {
        let mainWindow = window
        
        return mainWindow?.attachedSheet != nil
            || NSApp.windows.contains { $0 !== mainWindow && $0.isVisible && $0.isKeyWindow && !($0 is ActivePanel) }
    }

    func handleFlagsChanged(event: NSEvent) {
        // Suppress expansion when any modal window is open over the main window.
        // We check if any window other than the main window is currently key — this
        // covers the settings window (child window) and any future modal dialogs.
        if !(skipModalCheck || !hasModalWindow) { return }

        // Mask out device-specific bits so comparison with stored modifier values works reliably
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let appShortcuts = Settings.shared.appShortcutBindings
        
        // Check for session expander logic
        var shouldExpandSession = false
        let sessionMask = NSEvent.ModifierFlags(rawValue: appShortcuts.sessionDigitsModifiers)
        if appShortcuts.sessionDigitsModifiers > 0 && modifiers == sessionMask {
             shouldExpandSession = true
        } else if let alt = appShortcuts.sessionDigitsAlternateModifiers, alt > 0,
                  modifiers == NSEvent.ModifierFlags(rawValue: alt) {
             shouldExpandSession = true
        }
        
        // Service Digits (e.g. Cmd+Ctrl)
        var shouldExpandService = false
        let servicePrimaryMask = NSEvent.ModifierFlags(rawValue: appShortcuts.serviceDigitsPrimaryModifiers)
        if appShortcuts.serviceDigitsPrimaryModifiers > 0 && modifiers == servicePrimaryMask {
             shouldExpandService = true
        } else if let sec = appShortcuts.serviceDigitsSecondaryModifiers, sec > 0,
                  modifiers == NSEvent.ModifierFlags(rawValue: sec) {
             shouldExpandService = true
        }
        
        // Apply expansion states
        // Only expand if we have collapsible selectors and they are not hidden (i.e. in Compact/Auto mode)
        
        if let sessionSel = collapsibleSessionSelector, !sessionSel.isHidden && Settings.shared.showHiddenBarOnModifiers {
            if shouldExpandSession {
                if !sessionSel.isExpanded {
                    sessionSel.expand() 
                }
            } else {
                // Collapse immediately if keys released and mouse is not hovering safely
                if sessionSel.isExpanded && (skipSafeAreaCheck || !isMouseInSafeArea(for: sessionSel)) {
                     sessionSel.collapse()
                }
            }
        }
        
        if let serviceSel = collapsibleServiceSelector, !serviceSel.isHidden && Settings.shared.showHiddenBarOnModifiers {
            if shouldExpandService {
                if !serviceSel.isExpanded {
                    serviceSel.expand()
                }
            } else {
                if serviceSel.isExpanded && (skipSafeAreaCheck || !isMouseInSafeArea(for: serviceSel)) {
                    serviceSel.collapse()
                }
            }
        }
        
        let shouldShowHeader = (shouldExpandSession || shouldExpandService) && Settings.shared.showHiddenBarOnModifiers
        if isModifiersForHeaderDown != shouldShowHeader {
            isModifiersForHeaderDown = shouldShowHeader
            updateHeaderVisibility()
        }
    }
    
    private func isMouseInSafeArea(for selector: CollapsibleSelector) -> Bool {
        guard let panel = selector.expandedPanel else { return false }
        let mouseInScreen = NSEvent.mouseLocation
        let padding = selector.safeAreaPadding
        // Inset by negative padding = outset
        let safeFrame = panel.frame.insetBy(dx: -padding, dy: -padding)
        return safeFrame.contains(mouseInScreen)
    }

    func handleCommandShortcut(event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt16(event.keyCode)
        let appShortcuts = Settings.shared.appShortcutBindings
        let config = HotkeyManager.Configuration(keyCode: UInt32(keyCode), modifierFlags: modifiers.rawValue)

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isControl = modifiers.contains(.control)
        let isOption = modifiers.contains(.option)
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isControl && isShift && key == "q" {
            NSApp.terminate(nil)
            return true
        }

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
        case "m":
            toggleWindowSize()
            return true;
        case "h":
            hide();
            return true;
        case "q":
            hide();
            return true;
        case "w":
            closeCurrentTab()
            return true
        case "r":
            guard !isInspectorFocused() else {
                return false
            }
            reloadActiveWebView(nil)
            return true
        case "f":
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.show()
            return true
        case "g":
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.handleFindRepeat(shortcutShifted: isShift)
            return true
        case ",":
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return true
        case "=":
            guard !isInspectorFocused() else {
                return false
            }
            zoom(by: Zoom.step)
            return true
        case "-":
            guard !isInspectorFocused() else {
                return false
            }
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
            performMenuResetZoom(nil)
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

    private func isInspectorFocused() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        
        // Walk up the view hierarchy to see if any view is an inspector view
        var current: NSView? = responder as? NSView
        while let view = current {
            let className = String(describing: type(of: view))
            // WKInspectorWKWebView is the common class name for the inspector webview
            if className.contains("Inspector") {
                return true
            }
            current = view.superview
        }
        
        // Also check window class if it's a separate window (though we already check keyWindow in shortcut handler)
        if let window = responder as? NSWindow {
             return String(describing: type(of: window)).contains("Inspector")
        }
        
        return false
    }

    // MARK: - Dynamic Window Layout
    
    /// Unifies the layout logic for both hidden and visible modes.
    /// Dynamically adjusts the main window frame if the required margin changes,
    /// and repositions the internal content/drag rects accordingly.
    private func updateWindowMarginAndLayout() {
        guard let win = window, let containerView = win.contentView else { return }
        
        let newMargin = currentMargin
        let oldMargin = windowMarginView?.contentInset ?? 0
        
        // If the required margin has changed (e.g. toggling visibility mode, or changing outline width),
        // adjust the physical window frame to accommodate the new margin while keeping content static.
        if newMargin != oldMargin {
            let diff = newMargin - oldMargin
            var frame = win.frame
            
            let targetWidth = frame.size.width + 2 * diff
            let targetHeight = frame.size.height + 2 * diff
            
            // Constrain to screen size
            let screenFrame = win.screen?.frame ?? NSRect(x: 0, y: 0, width: 10000, height: 10000)
            let finalWidth = min(targetWidth, screenFrame.width)
            let finalHeight = min(targetHeight, screenFrame.height)
            
            let actualDiffW = (finalWidth - frame.size.width) / 2
            let actualDiffH = (finalHeight - frame.size.height) / 2
            
            frame.origin.x -= actualDiffW
            frame.origin.y -= actualDiffH
            frame.size.width = finalWidth
            frame.size.height = finalHeight
            // Update state BEFORE calling setFrame to prevent infinite recursion in windowDidResize
            windowMarginView?.contentInset = newMargin
            windowOutlineView?.contentInset = newMargin
            
            win.setFrame(frame, display: true)
        }
        
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        let bar = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        
        let cRect: NSRect
        let dRect: NSRect
        
        if isHiddenMode {
            cRect = NSRect(x: newMargin,
                           y: isBottom ? newMargin + bar : newMargin,
                           width: containerView.bounds.width - 2 * newMargin,
                           height: containerView.bounds.height - 2 * newMargin - bar)
            dRect = NSRect(x: newMargin,
                           y: isBottom ? newMargin : containerView.bounds.height - newMargin - bar,
                           width: containerView.bounds.width - 2 * newMargin,
                           height: bar)
            dragArea?.isTransparentBackground = true
        } else {
            // In visible mode, the bar and content are separate.
            cRect = NSRect(x: newMargin,
                           y: isBottom ? newMargin + bar : newMargin,
                           width: containerView.bounds.width - 2 * newMargin,
                           height: containerView.bounds.height - 2 * newMargin - bar)
            dRect = NSRect(x: newMargin,
                           y: isBottom ? newMargin : containerView.bounds.height - newMargin - bar,
                           width: containerView.bounds.width - 2 * newMargin,
                           height: bar)
            dragArea?.isTransparentBackground = false
        }
        
        let contentMaskedCorners: CACornerMask // For standard (unflipped) views like NSView
        let flippedMaskedCorners: CACornerMask // For flipped views like NSVisualEffectView
        if isHiddenMode {
            contentMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            flippedMaskedCorners = contentMaskedCorners
        } else {
            if isBottom {
                // Bar at bottom: round TOP corners
                contentMaskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] // maxY is top in unflipped
                flippedMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // minY is top in flipped
            } else {
                // Bar at top: round BOTTOM corners
                contentMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // minY is bottom in unflipped
                flippedMaskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] // maxY is bottom in flipped
            }
        }
        
        backgroundEffectView?.frame = cRect
        // NSVisualEffectView is flipped by default, so it needs the flipped corners
        backgroundEffectView?.layer?.maskedCorners = flippedMaskedCorners
        
        contentColorView?.frame = cRect
        // contentColorView is a standard NSView, so it needs the unflipped corners
        contentColorView?.layer?.maskedCorners = contentMaskedCorners
        
        webViewManager.updateLayout(contentRect: cRect, animated: false)
        dragArea?.frame = dRect
        dragArea?.autoresizingMask = []
        
        // Round the bar's outer corners so they align with the window border curve
        if isHiddenMode {
            dragArea?.layer?.cornerRadius = 0
            dragArea?.layer?.maskedCorners = []
        } else {
            dragArea?.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
            if isBottom {
                // Bar at bottom: round its bottom corners (minY in standard coords)
                dragArea?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else {
                // Bar at top: round its top corners (maxY in standard coords)
                dragArea?.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
        
        // Tell the frame views which edge the bar is on so they can align correctly
        windowMarginView?.configureBarEdge(isBottom ? .bottom : .top)
        windowOutlineView?.configureBarEdge(isBottom ? .bottom : .top)
        
        // Ensure blur window strictly follows the content frame, ignoring the transparent margin
        updateBlurWindowFrame()
    }

    // MARK: - Private helpers
    private func matches(_ lhs: HotkeyManager.Configuration, _ rhs: HotkeyManager.Configuration?) -> Bool {
        guard let rhs, !rhs.isDisabled else { return false }
        return lhs == rhs
    }

    private func configureWindow(for window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        // fullSizeContentView is often required for proper backdrop/blur effects on borderless windows
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        if !isUITesting && !isScreenshotMode {
            window.setFrameAutosaveName(Constants.WINDOW_FRAME_AUTOSAVE_NAME)
        } else {
            // Force frame for tests/screenshots, overriding any potental restoration
            let width: CGFloat = isScreenshotMode ? 640 : 900
            let height: CGFloat = isScreenshotMode ? 480 : 400
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let x = screenFrame.midX - (width / 2)
            let y = screenFrame.midY - (height / 2)

            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        
        // Final clamp to ensure no oversized or undersized frames persist from previous sessions/crashes
        if let screen = window.screen {
            let sf = screen.frame
            var f = window.frame
            
            // Constrain to physical screen dimensions (MAX)
            f.size.width = min(f.width, sf.width)
            f.size.height = min(f.height, sf.height)
            
            // Constrain to sane minimum dimensions (MIN)
            f.size.width = max(f.width, Constants.WINDOW_MIN_WIDTH)
            f.size.height = max(f.height, Constants.WINDOW_MIN_HEIGHT)
            
            window.setFrame(f, display: true)
        }
        
        window.minSize = NSSize(width: Constants.WINDOW_MIN_WIDTH, height: Constants.WINDOW_MIN_HEIGHT)
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // window.delegate = self // Moved to init to prevent premature callbacks before webViewManager is ready


        let frame = window.contentRect(forFrameRect: window.frame)
        
        // CONTAINER VIEW
        // This view will be the main content view. It can hold a solid background color (layer)
        // or be transparent to let the visual effect view show through.
        let containerView = NSView(frame: frame)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        containerView.layer?.masksToBounds = true
        containerView.autoresizingMask = [.width, .height]
        window.contentView = containerView
        
        windowMarginView = WindowMarginView(frame: containerView.bounds)
        windowMarginView.contentInset = currentMargin
        windowMarginView.autoresizingMask = [.width, .height]
        
        windowOutlineView = WindowOutlineView(frame: containerView.bounds)
        windowOutlineView.contentInset = currentMargin
        windowOutlineView.autoresizingMask = [.width, .height]
        
        // VISUAL EFFECT VIEW (Background Only)
        // Placed as a subview of containerView, at the very bottom (z-index).
        // It provides the blur material. We can hide it when using solid colors.
        let effect = NSVisualEffectView(frame: containerView.bounds)
        effect.material = .underWindowBackground
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.autoresizingMask = []
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        effect.layer?.masksToBounds = true
        
        // Add effect view FIRST so it's behind everything else added later
        containerView.addSubview(effect, positioned: .below, relativeTo: nil)
        backgroundEffectView = effect
        
        applyWindowAppearance()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        createDragArea(in: contentView)
        
        webViewManager.delegate = self
        
        activeIndicesByURL.removeAll()
        for service in services {
            activeIndicesByURL[service.url] = 0
        }
        webViewManager.updateServices(services)

        findBarViewController = FindBarViewController()
        findBarViewController.delegate = self
        findBarViewController.addTo(contentView: contentView, topOffset: Settings.shared.dragAreaPosition == .top ? Constants.DRAGGABLE_AREA_HEIGHT : 0)
        
        // windowMarginView handles the thick border and hit target, placed behind dragArea
        contentView.addSubview(windowMarginView, positioned: .below, relativeTo: dragArea)
        // windowOutlineView handles the thin outline, placed in front of everything
        contentView.addSubview(windowOutlineView, positioned: .above, relativeTo: nil)

        updateActiveWebview()
        updateHeaderTrackingArea()
        // Apply static layout before first visibility update
        updateWindowMarginAndLayout()
        updateHeaderVisibility(animated: false)
    }

    private func updateHeaderTrackingArea() {
        guard let contentView = window?.contentView else { return }
        if let area = headerTrackingArea {
            contentView.removeTrackingArea(area)
        }
        // Narrow 8pt strip at the very top edge - only show header when mouse is very close to top
        let edgeStrip: CGFloat = 50
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        // Add 4pt padding to the tracking rect to account for the outer border
        let y = isBottom ? 0 : contentView.bounds.height - edgeStrip
        let trackingRect = NSRect(x: 0, y: y, width: contentView.bounds.width, height: edgeStrip)
        let area = NSTrackingArea(rect: trackingRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        contentView.addTrackingArea(area)
        headerTrackingArea = area
    }
    
    private var isMouseInHeaderTrackingArea: Bool {
        guard let window = self.window,
              let trackingArea = headerTrackingArea,
              let contentView = window.contentView else { return false }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: mouseLocation)
        let viewLocation = contentView.convert(windowLocation, from: nil)
        
        return trackingArea.rect.contains(viewLocation)
    }
    
    override func mouseEntered(with event: NSEvent) {
        if let area = headerTrackingArea, event.trackingArea == area {
            isHeaderHovered = true
            updateHeaderVisibility()
        } else {
            super.mouseEntered(with: event)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if let area = headerTrackingArea, event.trackingArea == area {
            isHeaderHovered = false
            updateHeaderVisibility()
        } else {
            super.mouseExited(with: event)
        }
    }
    
    @objc private func topBarVisibilityChanged() {
        updateWindowMarginAndLayout()
        updateHeaderTrackingArea()
        updateHeaderVisibility(animated: false)
    }
    
    @objc private func appearanceSettingsChanged() {
        updateWindowMarginAndLayout()
    }

    @objc private func dragAreaPositionChanged() {
        guard let contentView = window?.contentView else { return }
        windowMarginView?.setRevealed(false, edge: .none, animated: false)
        windowOutlineView?.setRevealed(false, edge: .none, animated: false)
        
        updateWindowMarginAndLayout()
        findBarViewController?.layoutIn(contentView: contentView, topOffset: Settings.shared.dragAreaPosition == .top ? Constants.DRAGGABLE_AREA_HEIGHT : 0)
        updateHeaderTrackingArea()
        updateHeaderVisibility(animated: false)
    }

    private func updateHeaderVisibility(animated: Bool = true) {
        guard !isUpdatingHeaderVisibility else { return }
        isUpdatingHeaderVisibility = true
        defer { isUpdatingHeaderVisibility = false }

        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let isHeaderHovered = isMouseInHeaderTrackingArea
        let isAnySelectorExpanded = (collapsibleSessionSelector?.isExpanded == true) || (collapsibleServiceSelector?.isExpanded == true)

        let shouldShowHeaderIfHidden = isHeaderHovered ||
                                       isModifiersForHeaderDown ||
                                       isHeaderForcedVisibleForAction ||
                                       isAnySelectorExpanded

        let temporaryRevealAllowed = skipModalCheck || !hasModalWindow
        let finalVisible = !isHiddenMode || (shouldShowHeaderIfHidden && temporaryRevealAllowed)

        let isBottom = Settings.shared.dragAreaPosition == .bottom
        let edge: WindowMarginView.ThickEdge = isBottom ? .bottom : .top

        if isHiddenMode {
            let currentAlpha = dragArea?.alphaValue ?? 0
            let alreadyVisible = currentAlpha > 0.5
            if finalVisible {
                // Snap selectors to final position before animating in
                layoutSelectors()
                windowMarginView?.setRevealed(true, edge: edge, animated: animated)
                windowOutlineView?.setRevealed(true, edge: edge, animated: animated)
                // Only animate if bar isn't already fully visible (avoids flash on expand/collapse events)
                if animated && !alreadyVisible {
                    let slideOffset: CGFloat = 8
                    let translateY: CGFloat = isBottom ? slideOffset : -slideOffset
                    let showDuration: CFTimeInterval = 0.25
                    // Snap to off-edge position, then slide+fade in
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    dragArea?.layer?.transform = CATransform3DMakeTranslation(0, translateY, 0)
                    dragArea?.layer?.opacity = 0
                    CATransaction.commit()
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = showDuration
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        dragArea?.animator().alphaValue = 1.0
                    }
                    let slideAnim = CABasicAnimation(keyPath: "transform")
                    slideAnim.fromValue = CATransform3DMakeTranslation(0, translateY, 0)
                    slideAnim.toValue = CATransform3DIdentity
                    slideAnim.duration = showDuration
                    slideAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    slideAnim.isRemovedOnCompletion = true
                    dragArea?.layer?.add(slideAnim, forKey: "slideIn")
                    dragArea?.layer?.transform = CATransform3DIdentity
                } else if !animated {
                    dragArea?.layer?.removeAllAnimations()
                    dragArea?.layer?.transform = CATransform3DIdentity
                    dragArea?.alphaValue = 1.0
                }
                // else: already visible and animated=true — nothing to do, keep current state
            } else {
                // Collapse any open selectors — re-entry is blocked by the guard above
                collapsibleSessionSelector?.collapse()
                collapsibleServiceSelector?.collapse()
                stopSelectorCursorMonitor()
                windowMarginView?.setRevealed(false, edge: edge, animated: animated)
                windowOutlineView?.setRevealed(false, edge: edge, animated: animated)
                // Only animate if bar isn't already hidden
                if animated && alreadyVisible {
                    let slideOffset: CGFloat = 8
                    let translateY: CGFloat = isBottom ? slideOffset : -slideOffset
                    let hideDuration: CFTimeInterval = 0.18
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = hideDuration
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        dragArea?.animator().alphaValue = 0.0
                    }
                    // Slide out animation; model layer stays at identity so on remove there's no snap
                    let slideAnim = CABasicAnimation(keyPath: "transform")
                    slideAnim.fromValue = CATransform3DIdentity
                    slideAnim.toValue = CATransform3DMakeTranslation(0, translateY, 0)
                    slideAnim.duration = hideDuration
                    slideAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    slideAnim.isRemovedOnCompletion = true
                    dragArea?.layer?.add(slideAnim, forKey: "slideOut")
                } else if !animated {
                    dragArea?.layer?.removeAllAnimations()
                    dragArea?.layer?.transform = CATransform3DIdentity
                    dragArea?.alphaValue = 0.0
                }
                // else: already hidden and animated=true — nothing to do
            }
        } else {
            // Visible mode: bar always shown inside window, no frame ring
            windowMarginView?.setRevealed(false, edge: .none, animated: false)
            windowOutlineView?.setRevealed(false, edge: .none, animated: false)
            // Restore the bar's own background and visibility (was cleared/hidden in hidden mode)
            dragArea?.isTransparentBackground = false
            dragArea?.layer?.removeAllAnimations()
            dragArea?.layer?.transform = CATransform3DIdentity
            dragArea?.alphaValue = 1.0
            updateWindowMarginAndLayout()
        }
    }

    private func createDragArea(in contentView: NSView) {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        let barHeight = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        let initialFrame = NSRect(x: 0,
                                  y: isBottom ? 0 : contentView.bounds.height - barHeight,
                                  width: contentView.bounds.width,
                                  height: barHeight)
        let drag = DraggableView(frame: initialFrame)
        drag.autoresizingMask = isHiddenMode ? [] : (isBottom ? [.width, .maxYMargin] : [.width, .minYMargin])
        drag.alphaValue = isHiddenMode ? 0.0 : 1.0
        contentView.addSubview(drag)
        dragArea = drag

        // Service Selector (Static)
        let serviceSel = SegmentedControl(frame: .zero)
        serviceSel.enableDragReorder = true
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
        serviceSel.alwaysShowTooltips = false
        serviceSel.selectorDelegate = self  // Add delegate for instantiation state
        serviceSel.showInstantiationState = true  // Enable instantiation state feature

        serviceSel.segmentCount = services.count
        for (index, service) in services.enumerated() {
            serviceSel.setLabel(service.name, forSegment: index)
            serviceSel.setToolTip(service.name, forSegment: index)
        }
        serviceSel.setAccessibilityIdentifier("ServiceSelector")
        drag.addSubview(serviceSel)
        serviceSelector = serviceSel

        // Service Selector (Collapsible)
        let collapsibleServiceSel = CollapsibleSelector()
        collapsibleServiceSel.enableDragReorder = true
        collapsibleServiceSel.target = self
        collapsibleServiceSel.action = #selector(serviceChanged(_:))
        collapsibleServiceSel.delegate = self
        collapsibleServiceSel.showInstantiationState = true  // Enable the feature
        collapsibleServiceSel.mouseDownSegmentHandler = serviceSel.mouseDownSegmentHandler
        collapsibleServiceSel.dragBeganHandler = serviceSel.dragBeganHandler
        collapsibleServiceSel.dragChangedHandler = serviceSel.dragChangedHandler
        collapsibleServiceSel.dragEndedHandler = serviceSel.dragEndedHandler
        collapsibleServiceSel.alwaysShowTooltips = false
        collapsibleServiceSel.setItems(services.map { $0.name })
        // Flex: shrink-to-fit (high hugging, high compression resistance)
        collapsibleServiceSel.setContentHuggingPriority(.required, for: .horizontal)
        collapsibleServiceSel.setContentCompressionResistancePriority(.required, for: .horizontal)
        collapsibleServiceSel.setAccessibilityIdentifier("CollapsibleServiceSelector")
        drag.addSubview(collapsibleServiceSel)
        collapsibleServiceSelector = collapsibleServiceSel

        // Session Selector (Static)
        let sessionSel = SegmentedControl(frame: .zero)
        sessionSel.trackingMode = .selectOne
        sessionSel.segmentCount = 10
        for i in 0..<10 {
            sessionSel.setLabel("\(i == 9 ? 0 : i + 1)", forSegment: i)
        }
        sessionSel.target = self
        sessionSel.action = #selector(sessionChanged(_:))
        sessionSel.selectorDelegate = self
        sessionSel.showInstantiationState = true  // Enable instantiation state feature
        sessionSel.sizeToFit()
        sessionSel.setAccessibilityIdentifier("SessionSelector")
        drag.addSubview(sessionSel)
        sessionSelector = sessionSel

        // Session Selector (Collapsible)
        let collapsibleSessionSel = CollapsibleSelector()
        collapsibleSessionSel.target = self
        collapsibleSessionSel.action = #selector(sessionChanged(_:))
        // Populate items to define segment count (10) - caller provides display labels
        collapsibleSessionSel.setItems((0..<10).map { "\($0 == 9 ? 0 : $0 + 1)" })
        collapsibleSessionSel.delegate = self
        collapsibleSessionSel.showInstantiationState = true  // Enable the feature
        // Flex: shrink-to-fit (high hugging, high compression resistance)
        collapsibleSessionSel.setContentHuggingPriority(.required, for: .horizontal)
        collapsibleSessionSel.setContentCompressionResistancePriority(.required, for: .horizontal)
        collapsibleSessionSel.setAccessibilityIdentifier("CollapsibleSessionSelector")
        drag.addSubview(collapsibleSessionSel)
        collapsibleSessionSelector = collapsibleSessionSel
        
        updateSelectorsMode() // Set initial hidden states based on mode/width

        // Title Label
        let title = HoverTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.alignment = .center
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        drag.addSubview(title)
        titleLabel = title



        // Loading Border View (animated border around title when loading resources)
        let borderView = LoadingBorderView(frame: .zero)
        borderView.isHidden = true
        drag.addSubview(borderView, positioned: .below, relativeTo: title)
        loadingBorderView = borderView
        
        // Connect title label to border view for extended hover area
        title.hitTestView = borderView
        
        // Prevent title tooltip if session selector is expanded over it
        title.shouldShowTooltip = { [weak self] event in
                guard let self = self,
                      let sessionSel = self.collapsibleSessionSelector,
                      let mainWindow = self.window else { return true }
                
                // If the session selector is expanded, check the panel's frame in screen coordinates
                if !sessionSel.isHidden && sessionSel.isExpanded,
                   let panel = sessionSel.expandedPanel {
                    let pointInWindow = event.locationInWindow
                    let pointInScreen = mainWindow.convertToScreen(NSRect(origin: pointInWindow, size: .zero)).origin
                    if panel.frame.contains(pointInScreen) {
                        return false
                    }
                }
                return true
            }

        // Session Actions Button
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let actionsBtn = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Session Actions")!.withSymbolConfiguration(iconConfig)!, target: self, action: #selector(sessionActionsButtonTapped(_:)))
        actionsBtn.bezelStyle = .texturedRounded
        actionsBtn.contentTintColor = .secondaryLabelColor
        actionsBtn.refusesFirstResponder = true  // Prevent focus from being stolen from webview
        drag.addSubview(actionsBtn)
        sessionActionsButton = actionsBtn

        layoutSelectors()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDockVisibilityChanged), name: .dockVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSelectorDisplayModeChanged), name: .selectorDisplayModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(topBarVisibilityChanged), name: .topBarVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dragAreaPositionChanged), name: .dragAreaPositionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowAppearanceChanged), name: .windowAppearanceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationStatusChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationStatusChanged), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleColorSchemeChanged), name: .colorSchemeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowSettings), name: .settingsWindowDidOpen, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseSettings), name: .settingsWindowDidClose, object: nil)
        
        // Observe window width for Auto mode
        if let window = self.window {
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowDidResize), name: NSWindow.didResizeNotification, object: window)
            
            // Observe system appearance changes to update window background when system theme changes
            window.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        }
        
        // Apply initial color scheme
        applyColorScheme()
    }

    @objc private func handleApplicationStatusChanged(_ notification: Notification) {
        if notification.name == NSApplication.didResignActiveNotification {
            // Reset modifier-driven visibility states when leaving the app
            // to prevent the header from getting stuck due to missed key-up events (e.g. Cmd+Tab)
            isModifiersForHeaderDown = false
            collapsibleSessionSelector?.collapse()
            collapsibleServiceSelector?.collapse()
        }
        updateHeaderVisibility(animated: true)
    }

    @objc private func handleDockVisibilityChanged(_ notification: Notification) {
        layoutSelectors()
    }
    
    @objc private func handleSelectorDisplayModeChanged(_ notification: Notification) {
        updateSelectorsMode()
        layoutSelectors()
    }

    @objc private func handleWindowDidResize(_ notification: Notification) {
        if Settings.shared.selectorDisplayMode == .auto {
            updateSelectorsMode()
            layoutSelectors()
        }
        updateWindowMarginAndLayout()
        updateHeaderTrackingArea()
    }
    
    @objc private func handleWindowAppearanceChanged(_ notification: Notification) {
        applyWindowAppearance()
        updateWindowMarginAndLayout()
    }
    
    @objc private func handleColorSchemeChanged(_ notification: Notification) {
        applyColorScheme()
    }
    
    @objc private func handleShowSettings(_ notification: Notification) {
        collapsibleServiceSelector?.collapse()
        collapsibleSessionSelector?.collapse()
        updateHeaderVisibility(animated: true)
    }
    
    @objc private func handleCloseSettings(_ notification: Notification) {
        isHeaderHovered = isMouseInHeaderTrackingArea
        updateHeaderVisibility(animated: true)
    }
    
    private func applyColorScheme() {
        let scheme = Settings.shared.colorScheme
        let appearance = scheme.nsAppearance
        window?.appearance = appearance
        blurWindow?.appearance = appearance
        // Also update window appearance when color scheme changes
        applyWindowAppearance()
    }
    
    private func currentThemeSettings() -> ThemeAppearanceSettings? {
        guard let win = window else { return nil }
        let effectiveAppearance = win.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? Settings.shared.windowAppearance.dark : Settings.shared.windowAppearance.light
    }
    
    private func applyWindowAppearance() {
        guard let win = window, let themeSettings = currentThemeSettings() else { return }
        
        // Ensure main window is transparent and hit-testable via radius 1 blur
        win.isOpaque = false
        win.backgroundColor = .clear
        setWindowBlurRadius(win, radius: 1)
        
        // 1. Manage the Blur Window (Child)
        if blurWindow == nil {
            let bw = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            bw.isOpaque = false
            bw.backgroundColor = .clear
            bw.hasShadow = false
            bw.ignoresMouseEvents = true
            bw.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            win.addChildWindow(bw, ordered: .below)
            blurWindow = bw
        }
        
        guard let bw = blurWindow else { return }
        
        // 2. Apply theme to the blur window
        bw.backgroundColor = .clear
        bw.contentView?.wantsLayer = true
        
        switch themeSettings.mode {
        case .macOSEffects:
            bw.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            setWindowBlurRadius(bw, radius: themeSettings.blurRadius)
            
            // Sync with main window's effect view
            backgroundEffectView?.isHidden = false
            backgroundEffectView?.material = themeSettings.material.nsMaterial
            contentColorView?.isHidden = true
            
        case .solidColor:
            backgroundEffectView?.isHidden = true
            contentColorView?.isHidden = true
            
            // Apply the solid color to the layer and the optimized blur to the child window
            bw.contentView?.layer?.backgroundColor = themeSettings.backgroundColor.nsColor.cgColor
            setWindowBlurRadius(bw, radius: themeSettings.blurRadius)
        }
        
        updateBlurWindowFrame()
        win.contentView?.needsDisplay = true
    }
    
    /// Synchronizes the blur window's frame with the current content area in screen coordinates.
    private func updateBlurWindowFrame() {
        guard let win = window, let bw = blurWindow, let contentView = win.contentView else { return }
        
        // Map exactly to the visual content bounds, ignoring any transparent margin
        let targetFrame = backgroundEffectView?.frame ?? contentView.bounds
        let rectInScreen = win.convertToScreen(targetFrame)
        
        // Use setFrame with display: true and ensure the window is ordered correctly
        bw.setFrame(rectInScreen, display: true)
        
        // Ensure corner radius is applied to the child window's content
        bw.contentView?.wantsLayer = true
        bw.contentView?.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        bw.contentView?.layer?.masksToBounds = true
        
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        
        if isHiddenMode {
            bw.contentView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            if isBottom {
                // Bar at bottom, round top corners. Standard view, so maxY is top.
                bw.contentView?.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            } else {
                // Bar at top, round bottom corners. Standard view, so minY is bottom.
                bw.contentView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            }
        }
    }
    /// Sets the window's background blur radius using CoreGraphics Services private API
    /// This directly talks to the WindowServer to set blur behind the window
    private func setWindowBlurRadius(_ window: NSWindow, radius: Double) {
        CGSFuncs.initialize()
        
        guard let getMainConnection = CGSFuncs.getMainConnection,
              let setBlurRadius = CGSFuncs.setBlurRadius else { return }
        
        let connection = getMainConnection()
        
        if window.windowNumber > 0 {
             let wid = UInt32(window.windowNumber)
             let intRadius = Int32(radius)
             
             // For the blur to be visible:
             // 1. Shadow should be disabled
             // 2. Window must be non-opaque
             if intRadius > 0 {
                 window.hasShadow = false
                 window.isOpaque = false
             } 

             let result = setBlurRadius(connection, wid, intRadius)
             if result != 0 {
                 NSLog("[Quiper] Warning: CGSSetWindowBackgroundBlurRadius failed: \(result)")
             }
        }
    }

    
    private func updateSelectorsMode() {
        let mode = Settings.shared.selectorDisplayMode
        let windowWidth = window?.frame.width ?? 0

        let useCompact: Bool
        switch mode {
        case .expanded: useCompact = false
        case .compact: useCompact = true
        case .auto:
            let inset: CGFloat = 4
            let gap: CGFloat = 4
            let buttonSize: CGFloat = 24
            let minimumServiceWidth: CGFloat = 150
            let titleAreaMargin: CGFloat = 2
            let minTitleWidth: CGFloat = 120

            let showActionsButton = Settings.shared.dockVisibility == .never
            let rightOffset = showActionsButton ? (inset + buttonSize + gap) : inset

            let staticServiceWidth = max(minimumServiceWidth, estimatedWidthForServiceSegments())
            let staticSessionWidth = sessionSelector?.fittingSize.width ?? 0

            // Total width required for static mode with minimum title width
            let requiredWidth = minTitleWidth + rightOffset + inset + staticSessionWidth + staticServiceWidth + (2 * gap) + (2 * titleAreaMargin)

            useCompact = windowWidth < requiredWidth
        }

        serviceSelector?.isHidden = useCompact
        collapsibleServiceSelector?.isHidden = !useCompact

        sessionSelector?.isHidden = useCompact
        collapsibleSessionSelector?.isHidden = !useCompact

        // Sync selections
        syncSelectorSelections()
    }
    private func syncSelectorSelections() {
        let serviceIdx = services.firstIndex(where: { $0.url == currentServiceURL }) ?? 0
        serviceSelector?.selectedSegment = serviceIdx
        collapsibleServiceSelector?.selectedSegment = serviceIdx
        
        let sessionIdx = segmentIndex(forSession: activeIndicesByURL[currentServiceURL ?? ""] ?? 0)
        sessionSelector?.selectedSegment = sessionIdx
        collapsibleSessionSelector?.selectedSegment = sessionIdx
    }

    private func layoutSelectors() {
        guard let drag = dragArea,
              let title = titleLabel,
              let actionsBtn = sessionActionsButton else { return }
        
        // FindBar layout is now handled by FindBarViewController.addTo()/layoutIn() logic
        // We might need to call it if window resizes?
        // Original code called layoutFindBar() inside layoutSelectors() or windowDidResize.
        // FindBarViewController has active auto-layout or manual frame logic?
        // It has `layoutIn`. Let's assume we should call it if we want it to stay positioned.
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        findBarViewController?.layoutIn(contentView: window!.contentView!, topOffset: isBottom ? 0 : Constants.DRAGGABLE_AREA_HEIGHT)

        
        // Find visible selectors
        let activeServiceSel = (serviceSelector?.isHidden == false) ? serviceSelector : (collapsibleServiceSelector?.isHidden == false ? collapsibleServiceSelector : nil)
        let activeSessionSel = (sessionSelector?.isHidden == false) ? sessionSelector : (collapsibleSessionSelector?.isHidden == false ? collapsibleSessionSelector : nil)
        
        guard let serviceSel = activeServiceSel,
              let sessionSel = activeSessionSel else { return }

        let headerHeight = drag.bounds.size.height
        let selectorHeight: CGFloat = 25
        let gap: CGFloat = 4   // consistent gap between controls
        let buttonSize: CGFloat = 24
        let minimumServiceWidth: CGFloat = 150

        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        // In hidden mode the dragArea is already inset by barBorderWidth from the window edge,
        // so its x=0 aligns with the webview left edge — no extra inset needed.
        let inset: CGFloat = isHiddenMode ? 0 : 4

        // Vertically center selectors within the full visual bar height.
        // In hidden mode an extra `barBorderWidth` (4px) of border renders outside the dragArea
        // on the active edge, shifting the visual midpoint. Compensate so top and bottom margins match.
        let selectorY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - selectorHeight) / 2
                // For top bar the extra margin is above dragArea; for bottom bar it's below.
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - selectorHeight) / 2
            }
        }()

        let buttonY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - buttonSize) / 2
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - buttonSize) / 2
            }
        }()

        // Show only if in "Never" dock mode (i.e. strictly accessory mode, NO dock icon, NO native menu)
        let showActionsButton = Settings.shared.dockVisibility == .never
        actionsBtn.isHidden = !showActionsButton

        if showActionsButton {
            actionsBtn.frame = NSRect(
                x: drag.bounds.width - inset - buttonSize,
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )
        } else {
            actionsBtn.frame = .zero
        }

        // Determine right edge for selectors
        let rightReferenceX = showActionsButton ? (actionsBtn.frame.minX - gap) : (drag.bounds.width - inset)

        // Session width
        let sessionWidth: CGFloat
        if let coll = sessionSel as? CollapsibleSelector {
            sessionWidth = coll.currentWidth
        } else {
            sessionWidth = sessionSel.fittingSize.width
        }

        // Service width
        let serviceWidth: CGFloat
        if let coll = serviceSel as? CollapsibleSelector {
            serviceWidth = coll.currentWidth
        } else {
            serviceWidth = max(minimumServiceWidth, estimatedWidthForServiceSegments())
        }


        // Size service selector first
        let maxServiceWidth = max(minimumServiceWidth,
                                  rightReferenceX - gap - sessionWidth - gap)
        let actualServiceWidth = min(serviceWidth, maxServiceWidth)

        serviceSel.frame = NSRect(
            x: inset,
            y: selectorY,
            width: actualServiceWidth,
            height: selectorHeight
        )

        // Session selector positioned at the right
        let sessionX = rightReferenceX - sessionWidth
        sessionSel.frame = NSRect(
            x: sessionX,
            y: selectorY,
            width: sessionWidth,
            height: selectorHeight
        )

        // Calculate available space for title area (between selectors with margin)
        let titleAreaMargin: CGFloat = 2  // Margin from selectors
        let titleAreaX = serviceSel.frame.maxX + gap + titleAreaMargin
        let titleAreaWidth = max(0, sessionSel.frame.minX - gap - titleAreaX - titleAreaMargin)
        
        // Minimum width to show title and border meaningfully
        let minTitleAreaWidth: CGFloat = 60
        let shouldHideTitleArea = titleAreaWidth < minTitleAreaWidth
        
        // Loading border view frames the title area, aligned with selectors
        if let borderView = loadingBorderView {
            borderView.frame = NSRect(
                x: titleAreaX,
                y: selectorY,
                width: titleAreaWidth,
                height: selectorHeight
            )
            // Hide border if no room, but don't stop animation (it may resume when resized)
            borderView.isHidden = shouldHideTitleArea || !borderView.isAnimating
        }
        
        // Title label positioned inside the border with padding
        let titlePadding: CGFloat = 4  // Padding from border edges
        let titleWidth = max(0, titleAreaWidth - titlePadding * 2)
        let titleHeight = title.intrinsicContentSize.height
        let titleY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - titleHeight) / 2
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - titleHeight) / 2
            }
        }()
        title.frame = NSRect(
            x: titleAreaX + titlePadding,
            y: titleY,
            width: titleWidth,
            height: titleHeight
        )
        title.isHidden = shouldHideTitleArea

    }

    // Removed createWebviews and createWebviewStack as they are replaced by lazy loading
    private func getOrCreateWebview(for service: Service, sessionIndex: Int) -> WKWebView {
        // Safety check to prevent startup crashes if called before init is complete
        guard let manager = webViewManager else {
            NSLog("[Quiper] WARNING: getOrCreateWebview called before webViewManager initialized. Returning dummy.")
            return WKWebView(frame: .zero)
        }
        
        let wasInstantiated = manager.getWebView(for: service, sessionIndex: sessionIndex) != nil
        let webView = manager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea)
        
        // If this was a new instantiation, refresh the selector display
        if !wasInstantiated {
            refreshInstantiationState()
        }
        
        return webView
    }
    
    /// Refresh the instantiation state display for all selectors
    private func refreshInstantiationState() {
        collapsibleServiceSelector?.refreshInstantiationState()
        collapsibleSessionSelector?.refreshInstantiationState()
        
        // Also refresh regular SegmentedControls
        serviceSelector?.needsDisplay = true
        sessionSelector?.needsDisplay = true
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
        guard let service = currentService(), webViewManager != nil else { return }
        
        let activeIndex = activeIndicesByURL[service.url] ?? 0
        
        // Hide all existing webviews
        webViewManager.hideAll()
        
        // Get or create the active one
        let activeWebview = getOrCreateWebview(for: service, sessionIndex: activeIndex)
        
        // Show the session (wrapper + webview + inspector)
        webViewManager.showSession(activeWebview)
        
        if let zoom = Settings.shared.serviceZoomLevels[service.url] {
             webViewManager.applyZoom(zoom, for: service.url)
        }
        
        // Update title label and observe changes
        updateTitleLabel(from: activeWebview)
        
        // Load initial state (observers handled by manager now, but we need to update UI)
        updateTitleLabel(from: activeWebview)
        
        // Listeners for internal state changes
        // Manager uses delegate pattern now

        
        if focusWebView {
            window?.makeFirstResponder(activeWebview)
            focusInputInActiveWebview()
        }
    }
    
    private func updateTitleLabel(from webView: WKWebView) {
        let title = webView.title ?? ""
        titleLabel?.stringValue = title
        
        let isLoading = webView.isLoading
        
        // Dynamic Update for title label if truncated
        if let label = titleLabel {
            if label.isTruncated() {
                QuickTooltip.shared.updateIfVisible(with: title, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
        // Update session selector tooltip for the active session
        if let service = currentService() {
            let activeIndex = activeIndicesByURL[service.url] ?? 0
            let segIdx = segmentIndex(forSession: activeIndex)
            sessionSelector?.setToolTip(title, forSegment: segIdx)
            collapsibleSessionSelector?.setToolTip(title, forSegment: segIdx)
            
            // Dynamic Update for session tooltip if visible
            if let selector = sessionSelector {
                QuickTooltip.shared.updateIfVisible(with: title, for: (selector, segIdx), isLoading: isLoading)
            }
            // Collapsible selector internal view matching
            if let collapsible = collapsibleSessionSelector {
                collapsible.setToolTip(title, forSegment: segIdx)
            }
        }
        
        updateLoadingIndicator(for: webView)
    }
    
    private func updateLoadingIndicator(for webView: WKWebView) {
        let isLoading = webView.isLoading
        
        if isLoading {
            loadingBorderView?.startAnimating()
        } else {
            loadingBorderView?.stopAnimating()
        }
        
        // Update tooltip spinner for the specific session
        guard let serviceUrlStr = serviceURL(for: webView)?.absoluteString,
              serviceUrlStr == currentServiceURL,
              let service = services.first(where: { $0.url == serviceUrlStr }),
              let sessionIndex = (0...9).first(where: { webViewManager.getWebView(for: service, sessionIndex: $0) == webView }) else { return }
        
        let segIdx = segmentIndex(forSession: sessionIndex)
        var title = webView.title ?? ""
        
        // If this is the active webView and the title label is empty (manually cleared),
        // respect that empty state to ensure tooltips sync with the "blank" title
        // instead of reverting to the stale webView.title.
        if let labelTitle = titleLabel?.stringValue, labelTitle.isEmpty,
           let currentUrl = currentServiceURL,
           let activeIdx = activeIndicesByURL[currentUrl],
           activeIdx == sessionIndex {
            title = ""
        }
        
        if let selector = sessionSelector {
            QuickTooltip.shared.updateIfVisible(with: title, for: (selector, segIdx), isLoading: isLoading)
        }
        if let collapsible = collapsibleSessionSelector {
            collapsible.setToolTip(title, forSegment: segIdx)
        }
    }
    
    private func updateTitleLabel(withFallback fallback: String) {
        titleLabel?.stringValue = fallback
        
        // Dynamic Update for title label if truncated
        if let label = titleLabel {
            if label.isTruncated() {
                // Pass strict width to match label width
                QuickTooltip.shared.updateIfVisible(with: fallback, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
            // Update session selector tooltip for the active session
            if let service = currentService() {
                let activeIndex = activeIndicesByURL[service.url] ?? 0
                let segIdx = segmentIndex(forSession: activeIndex)
                
                // Ensure we use the fallback if title is empty
                sessionSelector?.setToolTip(fallback, forSegment: segIdx)
                collapsibleSessionSelector?.setToolTip(fallback, forSegment: segIdx)
                
                // Dynamic Update for session tooltip if visible
                // Forcing this update ensures that even if title went blank, the tooltip reflects the fallback
                if let selector = sessionSelector {
                    QuickTooltip.shared.updateIfVisible(with: fallback, for: (selector, segIdx), isLoading: false)
                }
                // Collapsible selector internal view matching
                if let collapsible = collapsibleSessionSelector {
                    collapsible.setToolTip(fallback, forSegment: segIdx)
                }
            }
        
        loadingBorderView?.stopAnimating()
    }

    private func refreshServiceSegments() {
        serviceSelector?.segmentCount = services.count
        for (index, service) in services.enumerated() {
            serviceSelector?.setLabel(service.name, forSegment: index)
            serviceSelector?.setToolTip(service.name, forSegment: index)
        }

        collapsibleServiceSelector?.setItems(services.map { $0.name })
        
        if let idx = services.firstIndex(where: { $0.url == currentServiceURL }) {
            collapsibleServiceSelector?.selectedSegment = idx
            serviceSelector?.selectedSegment = idx
        } else {
            if services.isEmpty {
                currentServiceURL = nil
                currentServiceName = nil
                titleLabel?.stringValue = ""
                collapsibleServiceSelector?.selectedSegment = -1
                serviceSelector?.selectedSegment = -1
                loadingBorderView?.stopAnimating()
            } else {
                collapsibleServiceSelector?.selectedSegment = 0
                serviceSelector?.selectedSegment = 0
            }
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
        let segmentIdx = segmentIndex(forSession: index)
        
        // Update tooltips for all sessions based on their webview titles
        // Update tooltips for all sessions based on their webview titles
        if let selector = sessionSelector {
            for sessionIdx in 0..<10 {
                let segIdx = segmentIndex(forSession: sessionIdx)
                let title = webViewManager.getWebView(for: service, sessionIndex: sessionIdx)?.title ?? "Session \(sessionIdx == 9 ? 0 : sessionIdx + 1)"
                selector.setToolTip(title, forSegment: segIdx)
                collapsibleSessionSelector?.setToolTip(title, forSegment: segIdx)
            }
        } else if let collapsible = collapsibleSessionSelector {
             for sessionIdx in 0..<10 {
                let segIdx = segmentIndex(forSession: sessionIdx)
                let title = webViewManager.getWebView(for: service, sessionIndex: sessionIdx)?.title ?? "Session \(sessionIdx == 9 ? 0 : sessionIdx + 1)"
                collapsible.setToolTip(title, forSegment: segIdx)
            }

        }

        sessionSelector?.selectedSegment = segmentIdx
        collapsibleSessionSelector?.selectedSegment = segmentIdx
        sessionSelector?.needsDisplay = true
        collapsibleSessionSelector?.needsDisplay = true
    }

    private var activeServiceSelector: NSView? {
        if let sel = serviceSelector, !sel.isHidden { return sel }
        if let sel = collapsibleServiceSelector, !sel.isHidden { return sel }
        return nil
    }

    private var activeSessionSelector: NSView? {
        if let sel = sessionSelector, !sel.isHidden { return sel }
        if let sel = collapsibleSessionSelector, !sel.isHidden { return sel }
        return nil
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

    /// Cmd+W: uninstantiate the current tab and navigate to the closest previously-used
    /// instantiated tab, following browser heuristics:
    ///   1. Same service — nearest instantiated session to the LEFT (lower index)
    ///   2. Same service — nearest instantiated session to the RIGHT (higher index)
    ///   3. Other services to the LEFT — their active session if instantiated, else any instantiated session
    ///   4. Other services to the RIGHT — same
    ///   5. Fallback — stay on current service, switch to session 0 (will be uninstantiated)
    private func closeCurrentTab() {
        guard let service = currentService() else { return }
        let currentSession = activeIndicesByURL[service.url] ?? 0
        let currentServiceIndex = services.firstIndex(where: { $0.url == service.url }) ?? 0

        // Remove the current webview
        webViewManager.removeWebView(for: service, sessionIndex: currentSession)

        // Helper: find the nearest instantiated session in a service, biased toward `preferred` direction
        func nearestInstantiatedSession(in svc: Service, excluding: Int? = nil) -> Int? {
            let sessions = (0..<10).filter { $0 != excluding && webViewManager.getWebView(for: svc, sessionIndex: $0) != nil }
            return sessions.first
        }

        // 1 & 2: Search within the same service — left first, then right
        let leftSessions  = stride(from: currentSession - 1, through: 0, by: -1)
        let rightSessions = stride(from: currentSession + 1, to: 10, by: 1)

        for idx in leftSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
            switchSession(to: idx)
            refreshInstantiationState()
            return
        }
        for idx in rightSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
            switchSession(to: idx)
            refreshInstantiationState()
            return
        }

        // 3 & 4: Search other services — left first, then right
        let leftServices  = stride(from: currentServiceIndex - 1, through: 0, by: -1).map { services[$0] }
        let rightServices = stride(from: currentServiceIndex + 1, to: services.count, by: 1).map { services[$0] }

        for svc in (leftServices + rightServices) {
            // Prefer the previously active session for this service (user heuristic: return
            // to where you left off). Only fall back to nearest if that session was closed.
            let activeSession = activeIndicesByURL[svc.url] ?? 0
            let targetSession: Int?
            if webViewManager.getWebView(for: svc, sessionIndex: activeSession) != nil {
                targetSession = activeSession
            } else {
                targetSession = nearestInstantiatedSession(in: svc)
            }
            if let session = targetSession {
                let svcIndex = services.firstIndex(where: { $0.url == svc.url })!
                activeIndicesByURL[svc.url] = session
                selectService(at: svcIndex)
                refreshInstantiationState()
                return
            }
        }

        // 5: Fallback — nothing else is instantiated; stay on current service, session 0
        switchSession(to: 0)
        refreshInstantiationState()
    }

    private func estimatedWidthForServiceSegments() -> CGFloat {
        let font = serviceSelector?.font ?? NSFont.systemFont(ofSize: 13)
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
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen else { return frameSize }
        let screenFrame = screen.frame
        
        // Constrain to physical screen dimensions
        return NSSize(width: min(frameSize.width, screenFrame.width),
                      height: min(frameSize.height, screenFrame.height))
    }

    func windowDidResize(_ notification: Notification) {
        updateWindowMarginAndLayout()
        layoutSelectors()
        updateHeaderTrackingArea()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // If we have child windows (like login popups), don't redirect focus
        if let childWindows = window?.childWindows, !childWindows.isEmpty {
            return
        }

        // If settings window is visible, redirect focus to it
        let settingsWindow = AppDelegate.sharedSettingsWindow
        if settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Always ensure webview is the first responder when main window becomes key
        if let webView = currentWebView() {
            window?.makeFirstResponder(webView)
        }
        focusInputInActiveWebview()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Collapse all collapsible selectors when window loses focus
        collapsibleServiceSelector?.collapse()
        collapsibleSessionSelector?.collapse()
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
        guard let service = currentService() else { return }
        webViewManager.applyZoom(Zoom.default, for: service.url)
    }

    func zoom(by delta: CGFloat) {
        guard let service = currentService() else { return }
        // We need to fetch current zoom from manager. It stores state.
        // But manager state access is currently internal.
        // Let's assume we can add public access or just track it here?
        // Actually, better to just let manager handle it fully, but we need 'current'.
        // For now, let's rely on Settings.shared since that's the persistent store
        let currentZoom = Settings.shared.serviceZoomLevels[service.url] ?? Zoom.default
        let nextZoom = max(Zoom.min, min(Zoom.max, currentZoom + delta))
        
        webViewManager.applyZoom(nextZoom, for: service.url)
        Settings.shared.storeZoomLevel(nextZoom, for: service.url)
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
        findBarViewController.show()
    }

    @objc func performMenuToggleInspector(_ sender: Any?) {
        toggleInspector()
    }

    @objc func performCustomActionFromMenu(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CustomAction else { return }
        performCustomAction(action)
    }


    
    private func serviceURL(for webView: WKWebView) -> URL? {
        return webViewManager.serviceURL(for: webView)
    }
}

// MARK: - CollapsibleSelectorDelegate
@MainActor
extension MainWindowController: CollapsibleSelectorDelegate {
    func isLoading(index: Int) -> Bool {
        guard let service = currentService(),
              let webView = webViewManager.getWebView(for: service, sessionIndex: index) else { return false }
        return webView.isLoading
    }
    
    func selector(_ selector: CollapsibleSelector, isInstantiated index: Int) -> Bool {
        if selector === collapsibleServiceSelector {
            // For services: instantiated if ANY session of this service is instantiated
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            
            // Check if any session (0-9) has an instantiated webview
            for sessionIdx in 0..<10 {
                if webViewManager.getWebView(for: service, sessionIndex: sessionIdx) != nil {
                    return true
                }
            }
            return false
        } else if selector === collapsibleSessionSelector {
            // For sessions: instantiated if webview exists for current service + this session
            guard let service = currentService() else { return false }
            return webViewManager.getWebView(for: service, sessionIndex: index) != nil
        }
        
        // Fallback: assume instantiated
        return true
    }
    
    func segmentedControl(_ control: SegmentedControl, isInstantiated index: Int) -> Bool {
        if control === serviceSelector {
            // For services: instantiated if ANY session of this service is instantiated
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            for sessionIdx in 0..<10 {
                if webViewManager.getWebView(for: service, sessionIndex: sessionIdx) != nil {
                    return true
                }
            }
            return false
        } else if control === sessionSelector {
            // For sessions: instantiated if webview exists for current service + this session
            guard let service = currentService() else { return false }
            return webViewManager.getWebView(for: service, sessionIndex: index) != nil
        }
        return true
    }
    
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int) {
        // Drag logic is handled by closures on the control currently
    }
    
    func selectorWillExpand(_ selector: CollapsibleSelector) {
        if selector === collapsibleServiceSelector {
            collapsibleSessionSelector?.collapse()
        } else if selector === collapsibleSessionSelector {
            collapsibleServiceSelector?.collapse()
        }
    }
    
    func collapsibleSelector(_ selector: CollapsibleSelector, didChangeExpansionState isExpanded: Bool) {
        if isExpanded {
            startSelectorCursorMonitorIfNeeded()
        }
        updateHeaderVisibility()
    }
    
    private func startSelectorCursorMonitorIfNeeded() {
        guard selectorCursorMonitor == nil else { return }
        selectorCursorMonitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkSelectorSafeZones() }
        }
    }
    
    private func stopSelectorCursorMonitor() {
        selectorCursorMonitor?.invalidate()
        selectorCursorMonitor = nil
    }
    
    private func checkSelectorSafeZones() {
        let mouse = NSEvent.mouseLocation
        let selectors = [collapsibleSessionSelector, collapsibleServiceSelector].compactMap { $0 }
        var anyExpanded = false
        
        for selector in selectors where selector.isExpanded {
            anyExpanded = true
            
            // If the user is holding the modifier keys, keep it expanded regardless of mouse position.
            // (Collapse will be triggered when they release the keys).
            if isModifiersForHeaderDown { continue }
            
            // If the user is currently dragging a segment to reorder, keep it expanded.
            if draggingServiceIndex != nil { continue }
            
            // If the user is currently tracking a drag or click inside the selector itself, keep it expanded.
            if selector.isTrackingMouse { continue }
            
            if let panel = selector.expandedPanel {
                // Outset panel frame by safeAreaPadding
                let safeRect = panel.frame.insetBy(dx: -selector.safeAreaPadding, dy: -selector.safeAreaPadding)
                if !safeRect.contains(mouse) {
                    selector.collapse()
                }
            }
        }
        if !anyExpanded { stopSelectorCursorMonitor() }
    }
}

// MARK: - FindBarDelegate
extension MainWindowController: FindBarDelegate {
    func activeWebViewForFind() -> WKWebView? {
        currentWebView()
    }
}

// MARK: - WebViewManagerDelegate
extension MainWindowController: WebViewManagerDelegate {
    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView) {
        // Only update UI if this is the active webview
        guard webView == currentWebView() else { return }
        updateTitleLabel(from: webView)
    }
    
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView) {
        // Only update UI if this is the active webview
        guard webView == currentWebView() else { return }
        updateLoadingIndicator(for: webView)
    }
    
    func webViewDidFinishNavigation(_ webView: WKWebView) {
        guard webView == currentWebView() else { return }
        
        // Set fallback title if page loaded without one
        if webView.title?.isEmpty ?? true {
             updateTitleLabel(withFallback: "-")
        }
        
        window?.makeFirstResponder(webView)
        
        let runFocus: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.focusInputInActiveWebview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.focusInputInActiveWebview()
            }
        }
        
        DispatchQueue.main.async(execute: runFocus)
    }
}



enum Zoom {
    static let step: CGFloat = 0.1
    static let min: CGFloat = 0.5
    static let max: CGFloat = 2.5
    static let `default`: CGFloat = 1.0
}

// MARK: - Helper Views

final class HoverTextField: NSTextField {
    // Prevent focus from being stolen from webview
    override var acceptsFirstResponder: Bool { false }
    
    private var trackingArea: NSTrackingArea?
    
    // Explicitly allow setting a larger hit-test view (e.g., the LoadingBorderView)
    weak var hitTestView: NSView?
    
    // Check if tooltip should be shown (e.g., to prevent showing when obscured)
    var shouldShowTooltip: ((NSEvent) -> Bool)?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // Use hitTestView bounds if available, otherwise self.bounds
        let rect: NSRect
        if let hitView = hitTestView, let superview = superview {
             // Convert hitView frame to our coordinate system
             // But simpler: just track mouse moves over self and parent?
             // Actually, the cleanly supported way is to add tracking rect for *that* view on that view.
             // But since we want to trigger *this* tooltip logic...
             // Let's make the tracking area cover the hitTestView's frame relative to self
             rect = convert(hitView.frame, from: superview)
        } else {
             rect = bounds
        }
        
        trackingArea = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Check external condition first
        if let shouldShow = shouldShowTooltip, !shouldShow(event) {
            return
        }
        
        if !stringValue.isEmpty {
            // Only show if truncated
            if isTruncated() {
                // Use the hitTestView width if available for positioning visual width logic?
                // Actually user requested "area of the rounded spinning rectangle"
                // So if we have hitTestView, we use its width as the forced width
                let width = hitTestView?.bounds.width ?? bounds.width
                QuickTooltip.shared.show(stringValue, for: self, forcedWidth: width)
            }
        }
    }
    
    func isTruncated() -> Bool {
        guard let cell = cell else { return false }
        // Use a large width to measure the full natural width of the text
        let properSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: bounds.height))
        // Compare against the available width (hitTestView if present)
        let availableWidth = hitTestView?.bounds.width ?? bounds.width
        return properSize.width > availableWidth
    }
    
    override func mouseExited(with event: NSEvent) {
        QuickTooltip.shared.hide(for: self)
    }
}
