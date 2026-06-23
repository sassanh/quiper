import AppKit
import WebKit
import Carbon
import Combine
import CoreImage
import QuartzCore

@MainActor
struct CGSFuncs {
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

    var dragArea: DraggableView!
    var serviceSelector: SegmentedControl?
    var collapsibleServiceSelector: CollapsibleSelector?
    var sessionSelector: SegmentedControl?
    var collapsibleSessionSelector: CollapsibleSelector?
    var titleLabel: HoverTextField!
    var navigationButtonGroup: NavigationButtonGroup!
    var refreshStopButton: RefreshStopButton!
    var trashSessionButton: HoverIconButton!
    var promptHistoryButton: HoverIconButton!
    var canGoBackObservation: NSKeyValueObservation?
    var canGoForwardObservation: NSKeyValueObservation?
    var isLoadingNavObservation: NSKeyValueObservation?

    var windowMarginView: WindowMarginView!
    var windowOutlineView: WindowOutlineView!
    var loadingBorderView: LoadingBorderView!
    var isLoadingObservation: NSKeyValueObservation?
    var sessionActionsButton: NSButton!
    var manualLockButton: NSButton!
    var serviceListObservation: NSKeyValueObservation?
    
    var activeDownloads: [Any] = [] 

    private var titleObservation: NSKeyValueObservation?
    var sessionTitleObservations: [String: NSKeyValueObservation] = [:]
    var services: [Service] = []
    var currentServiceName: String?
    var currentServiceURL: String?
    var webViewManager: WebViewManager!
    var emptyStateView: EmptyStateView!
    var findBarViewController: FindBarViewController!
    var draggingServiceIndex: Int?
    var activeIndicesByURL: [String: Int] = [:]
    var keyDownEventMonitor: Any?
    var skipSafeAreaCheck = false
    var skipModalCheck = false
    
    var backgroundEffectView: NSVisualEffectView?
    
    var lastActivityTime = Date()
    var inactivityTimer: Timer?
    var activityMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    
    var headerTrackingArea: NSTrackingArea?
    var headerActionTimer: Timer?
    var isHeaderHovered = false
    var isModifiersForHeaderDown = false
    var isHeaderForcedVisibleForAction = false
    var isUpdatingHeaderVisibility = false
    var selectorCursorMonitor: Timer?
    var lastCommandPressedTime: TimeInterval = 0
    var lastCommandReleasedTime: TimeInterval = 0
    var wasBothCmdsDown = false
    var modifierHUDView: ModifierHUDView?
    var onboardingHUD: GhostOnboardingHUDView?

    private var isCompactMode = false
    private var previousWindowFrame: NSRect?
    let barBorderWidth: CGFloat = 8
    
    var currentMargin: CGFloat {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        if isHiddenMode {
            return barBorderWidth
        } else {
            let isDark = window?.effectiveAppearance.name.rawValue.contains("Dark") ?? false
            let settings = isDark ? Settings.shared.windowAppearance.dark : Settings.shared.windowAppearance.light
            return ceil(settings.outlineWidth)
        }
    }
    var contentColorView: NSView?
    var blurWindow: NSWindow?
    
    deinit {
        MainActor.assumeIsolated {
            let bw = blurWindow
            let win = window
            if let bw = bw {
                win?.removeChildWindow(bw)
                bw.orderOut(nil)
                bw.close()
            }
            removeObserver(self, forKeyPath: "window")
            win?.removeObserver(self, forKeyPath: "effectiveAppearance")
            NotificationCenter.default.removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            
            if let monitor = activityMonitor {
                NSEvent.removeMonitor(monitor)
            }
            inactivityTimer?.invalidate()
        }
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
        
        configureWindow(for: window)
        
        guard let contentView = window.contentView else {
            fatalError("Failed to initialize window content view")
        }
        
        webViewManager = WebViewManager(containerView: contentView)
        
        emptyStateView = EmptyStateView(frame: contentView.bounds)
        emptyStateView.onEngineSelected = { [weak self] index in
            self?.selectService(at: index)
        }
        emptyStateView.onSessionSelected = { [weak self] svcIndex, sessionIndex in
            guard let self = self, self.services.indices.contains(svcIndex) else { return }
            let service = self.services[svcIndex]
            self.activeIndicesByURL[service.url] = sessionIndex
            self.selectService(at: svcIndex)
        }
        emptyStateView.isHidden = true
        contentView.addSubview(emptyStateView)
        
        self.services = initialServices
        webViewManager.updateServices(initialServices)
        
        self.services.forEach { service in
            activeIndicesByURL[service.url] = 0
        }
        setupUI()
        setupInactivityMonitoring()
        self.window?.delegate = self
        addObserver(self, forKeyPath: "window", options: [.new], context: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
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
        guard let manager = webViewManager else { return nil }
        guard let service = currentService(),
              let index = activeIndicesByURL[service.url] else {
            return nil
        }
        return manager.getWebView(for: service, sessionIndex: index)
    }
    
    func waitForNavigation(on webView: WKWebView) async {
        await webViewManager.waitForNavigation(on: webView)
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
        guard !GhostOnboardingManager.shared.isActive else { return }
        guard let service = currentService() else { return }
        let selector = FocusSelectorStorage.loadSelector(serviceID: service.id, fallback: service.focus_selector)
        guard !selector.isEmpty else { return }
        guard let webView = currentWebView() else { return }
        let escapedSelector = escapeForJavaScript(selector)
        
        let sessionIdx = activeIndicesByURL[service.url] ?? 0
        let shouldRestore = service.preservePrompt
        let inputState = shouldRestore ? webViewManager?.getTabInputState(for: service.url, sessionIndex: sessionIdx) : nil
        
        let hasSaved = inputState != nil
        let textVal = inputState?.text ?? ""
        let startVal = inputState?.start ?? 0
        let endVal = inputState?.end ?? 0
        let jsString = """
        (function() {
            const selector = "\(escapedSelector)";
            const hasSaved = \(hasSaved);
            const text = \(escapeForJavaScriptLiteral(textVal));
            const start = \(startVal);
            const end = \(endVal);
            
            function getContentEditableSelection(el) {
                const selection = window.getSelection();
                if (!selection.rangeCount) return { start: 0, end: 0 };
                const range = selection.getRangeAt(0);
                const preCaretRange = range.cloneRange();
                preCaretRange.selectNodeContents(el);
                preCaretRange.setEnd(range.startContainer, range.startOffset);
                const startOffset = preCaretRange.toString().length;
                preCaretRange.setEnd(range.endContainer, range.endOffset);
                const endOffset = preCaretRange.toString().length;
                return { start: startOffset, end: endOffset };
            }

            function setContentEditableSelection(el, start, end) {
                const range = document.createRange();
                const selection = window.getSelection();
                
                let currentOffset = 0;
                let startNode = null;
                let startNodeOffset = 0;
                let endNode = null;
                let endNodeOffset = 0;
                
                function traverse(node) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const len = node.length;
                        if (!startNode && currentOffset + len >= start) {
                            startNode = node;
                            startNodeOffset = start - currentOffset;
                        }
                        if (!endNode && currentOffset + len >= end) {
                            endNode = node;
                            endNodeOffset = end - currentOffset;
                        }
                        currentOffset += len;
                    } else {
                        for (let i = 0; i < node.childNodes.length; i++) {
                            traverse(node.childNodes[i]);
                            if (startNode && endNode) break;
                        }
                    }
                }
                
                traverse(el);
                
                if (!startNode) {
                    startNode = el;
                    startNodeOffset = el.childNodes.length;
                }
                if (!endNode) {
                    endNode = el;
                    endNodeOffset = el.childNodes.length;
                }
                
                try {
                    range.setStart(startNode, startNodeOffset);
                    range.setEnd(endNode, endNodeOffset);
                    selection.removeAllRanges();
                    selection.addRange(range);
                } catch (e) {
                    console.error("Error setting contenteditable selection", e);
                }
            }

            function tryFocusAndRestore(el) {
                const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                
                if (hasSaved) {
                    window.__quiperHasSavedSelection = true;
                    window.__quiperSavedStart = start;
                    window.__quiperSavedEnd = end;
                    
                    if (isContentEditable) {
                        if (typeof text === 'string' && el.innerText !== text) {
                            el.innerText = text;
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                        }
                    } else {
                        if (typeof text === 'string' && el.value !== text) {
                            el.value = text;
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                        }
                    }
                } else {
                    window.__quiperHasSavedSelection = false;
                }
                
                el.focus();
                
                if (hasSaved) {
                    if (isContentEditable) {
                        setContentEditableSelection(el, start, end);
                    } else {
                        el.setSelectionRange(start, end);
                    }
                }

                // Register a focus listener to override programmatic focus resets
                if (!el.__quiperFocusListenerAdded) {
                    el.__quiperFocusListenerAdded = true;
                    el.addEventListener('focus', () => {
                        const lastInteract = window.__quiperLastInteractionTime || 0;
                        if (hasSaved && (Date.now() - lastInteract > 300)) {
                            if (isContentEditable) {
                                setContentEditableSelection(el, start, end);
                            } else {
                                el.setSelectionRange(start, end);
                            }
                        }
                    });
                }
            }

            if (window.__quiperFocusInterval) {
                clearInterval(window.__quiperFocusInterval);
                window.__quiperFocusInterval = null;
            }

            const initialEl = document.querySelector(selector);
            if (initialEl) {
                tryFocusAndRestore(initialEl);
                return;
            }

            const startTime = Date.now();
            const timeout = 15000;
            window.__quiperFocusInterval = setInterval(() => {
                const polledEl = document.querySelector(selector);
                if (polledEl) {
                    clearInterval(window.__quiperFocusInterval);
                    window.__quiperFocusInterval = null;
                    tryFocusAndRestore(polledEl);
                } else if (Date.now() - startTime > timeout) {
                    clearInterval(window.__quiperFocusInterval);
                    window.__quiperFocusInterval = null;
                }
            }, 100);
        })();
        """
        
        webView.evaluateJavaScript(jsString, completionHandler: nil)
    }

    func focusInputInActiveWebviewWithFallback() {
        guard !GhostOnboardingManager.shared.isActive else { return }
        
        let runFocus: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }
            if let webView = self.currentWebView() {
                self.window?.makeFirstResponder(webView)
            }
            self.focusInputInActiveWebview()
        }
        
        // Warm up WebKit's internal focus chain. When the window comes back from
        // orderOut, the web content process doesn't consider itself "activated"
        // and silently ignores JavaScript .focus() calls until it receives
        // focus via the native responder chain.
        if let webView = currentWebView() {
            warmUpWebViewFocus(webView)
        }
        
        // 1st pass: immediate (on next runloop turn)
        DispatchQueue.main.async(execute: runFocus)
    }

    /// Re-establishes WebKit's internal focus chain after the window was hidden.
    /// When the window comes back from `orderOut`, the WKWebView's internal
    /// content view loses first-responder status, causing JavaScript `.focus()`
    /// calls to be silently ignored by some pages (notably Gemini).
    ///
    /// Instead of synthesizing mouse events (which would create real click
    /// events on whatever web element is at the target coordinate), this walks
    /// the WKWebView's subview hierarchy to find the deepest first-responder-
    /// eligible view (WebKit's internal content view) and makes it the first
    /// responder directly — safely, with no web-level side effects.
    private func warmUpWebViewFocus(_ webView: WKWebView) {
        guard let win = window else { return }

        // Temporarily resign first responder so that re-assigning it triggers
        // WebKit's internal becomeFirstResponder path even if the webview
        // was already nominally first responder.
        win.makeFirstResponder(nil)

        // Walk the subview tree to find the deepest view that can become
        // first responder — this is WKWebView's private content view that
        // bridges to the web rendering process.
        if let contentView = deepestFirstResponder(in: webView) {
            win.makeFirstResponder(contentView)
        } else {
            // Fallback: just re-focus the webview itself
            win.makeFirstResponder(webView)
        }
    }

    private func deepestFirstResponder(in view: NSView) -> NSView? {
        for subview in view.subviews.reversed() {
            if let found = deepestFirstResponder(in: subview) {
                return found
            }
        }
        // Skip the WKWebView itself — we want its internal content view
        if view is WKWebView { return nil }
        return view.acceptsFirstResponder ? view : nil
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

    private func escapeForJavaScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    var isEmptyStateActive: Bool {
        return emptyStateView != nil && !emptyStateView.isHidden
    }

    func currentWebView() -> WKWebView? {
        guard let manager = webViewManager else { return nil }
        guard let service = currentService(),
              let index = activeIndicesByURL[service.url] else {
            return nil
        }
        return manager.getWebView(for: service, sessionIndex: index)
    }

    func show() {
        checkInactivityLock()
        var didTeleport = false
        if let window = window {
            // Standard show attempt
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.makeKeyAndOrderFront(nil)
            
            // If WindowServer's space cache is broken, the window will be trapped on another space.
            // We surgically deploy the teleport sequence only when the standard show fails.
            if !window.isOnActiveSpace {
                didTeleport = true
                window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
                window.makeKeyAndOrderFront(nil)
                
                // Wait 100ms for WindowServer to physically execute the space jump
                // before flipping the flag back, otherwise it cancels the jump mid-flight.
                // updateCollectionBehaviorForVisibilityState is also deferred here because
                // it would synchronously set .canJoinAllSpaces and undo the teleport.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateCollectionBehaviorForVisibilityState()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        
        if let sheet = window?.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else if !GhostOnboardingManager.shared.isActive {
            focusInputInActiveWebviewWithFallback()
        }
        
        setShortcutsEnabled(true)
        if !didTeleport {
            updateCollectionBehaviorForVisibilityState()
        }
        NotificationCenter.default.post(name: .windowDidShow, object: nil)
    }

    func hide() {
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet, returnCode: .cancel)
        }
        window?.orderOut(nil)
        
        updateCollectionBehaviorForVisibilityState()
        
        findBarViewController?.hide()
        setShortcutsEnabled(false)
        hideModifierHUD()
        NotificationCenter.default.post(name: .windowDidHide, object: nil)
    }

    func toggleWindowSize() {
        guard let window = window else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        if isCompactMode {
            let targetFrame: NSRect
            if let previous = previousWindowFrame {
                targetFrame = previous
            } else {
                let width: CGFloat = 800
                let height: CGFloat = 620
                let x = screenFrame.midX - (width / 2)
                let y = screenFrame.midY - (height / 2)
                targetFrame = NSRect(x: x, y: y, width: width, height: height)
            }
            window.setFrame(targetFrame, display: true, animate: true)
            isCompactMode = false
            previousWindowFrame = nil
        } else {
            previousWindowFrame = window.frame
            let width: CGFloat = 550
            let height: CGFloat = 400
            let padding: CGFloat = 20
            let x = screenFrame.maxX - width - padding
            let y = screenFrame.maxY - height - padding
            let newFrame = NSRect(x: x, y: y, width: width, height: height)
            window.setFrame(newFrame, display: true, animate: true)
            isCompactMode = true
        }
        layoutSelectors()
    }

    func updateWindowMarginAndLayout() {
        guard let win = window, let containerView = win.contentView else { return }
        
        let newMargin = currentMargin
        let oldMargin = windowMarginView?.contentInset ?? 0
        
        if newMargin != oldMargin {
            let diff = newMargin - oldMargin
            var frame = win.frame
            
            let targetWidth = frame.size.width + 2 * diff
            let targetHeight = frame.size.height + 2 * diff
            
            let screenFrame = win.screen?.frame ?? NSRect(x: 0, y: 0, width: 10000, height: 10000)
            let finalWidth = min(targetWidth, screenFrame.width)
            let finalHeight = min(targetHeight, screenFrame.height)
            
            let actualDiffW = (finalWidth - frame.size.width) / 2
            let actualDiffH = (finalHeight - frame.size.height) / 2
            
            frame.origin.x -= actualDiffW
            frame.origin.y -= actualDiffH
            frame.size.width = finalWidth
            frame.size.height = finalHeight
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
        
        let contentMaskedCorners: CACornerMask
        let flippedMaskedCorners: CACornerMask
        if isHiddenMode {
            contentMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            flippedMaskedCorners = contentMaskedCorners
        } else {
            if isBottom {
                contentMaskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                flippedMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else {
                contentMaskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                flippedMaskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
        
        if isHiddenMode {
            backgroundEffectView?.frame = cRect
            backgroundEffectView?.layer?.maskedCorners = flippedMaskedCorners
            
            contentColorView?.frame = cRect
            contentColorView?.layer?.maskedCorners = contentMaskedCorners
        } else {
            let fullRect = NSRect(x: newMargin,
                                  y: newMargin,
                                  width: containerView.bounds.width - 2 * newMargin,
                                  height: containerView.bounds.height - 2 * newMargin)
            
            backgroundEffectView?.frame = fullRect
            backgroundEffectView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            
            contentColorView?.frame = fullRect
            contentColorView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        emptyStateView?.frame = cRect
        emptyStateView?.layer?.maskedCorners = contentMaskedCorners
        emptyStateView?.layer?.masksToBounds = true
        
        webViewManager.setContentFrame(cRect, animated: false)
        dragArea?.frame = dRect
        dragArea?.autoresizingMask = []
        
        if isHiddenMode {
            dragArea?.layer?.cornerRadius = 0
            dragArea?.layer?.maskedCorners = []
        } else {
            dragArea?.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
            if isBottom {
                dragArea?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else {
                dragArea?.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
        
        windowMarginView?.configureBarEdge(isBottom ? .bottom : .top)
        windowOutlineView?.configureBarEdge(isBottom ? .bottom : .top)
        
        updateBlurWindowFrame()
    }

    private func configureWindow(for window: NSWindow) {
        window.level = .floating
        updateCollectionBehaviorForVisibilityState()
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        if !isUITesting && !isScreenshotMode {
            window.setFrameAutosaveName(Constants.WINDOW_FRAME_AUTOSAVE_NAME)
        } else {
            let width: CGFloat = isScreenshotMode ? 640 : 900
            let height: CGFloat = isScreenshotMode ? 480 : 400
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let x = screenFrame.midX - (width / 2)
            let y = screenFrame.midY - (height / 2)

            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        
        if let screen = window.screen {
            let sf = screen.frame
            var f = window.frame
            
            f.size.width = min(f.width, sf.width)
            f.size.height = min(f.height, sf.height)
            
            f.size.width = max(f.width, Constants.WINDOW_MIN_WIDTH)
            f.size.height = max(f.height, Constants.WINDOW_MIN_HEIGHT)
            
            window.setFrame(f, display: true)
        }
        
        window.minSize = NSSize(width: Constants.WINDOW_MIN_WIDTH, height: Constants.WINDOW_MIN_HEIGHT)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let frame = window.contentRect(forFrameRect: window.frame)
        
        let containerView = WindowContentView(frame: frame)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.01).cgColor
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
        
        let effect = NSVisualEffectView(frame: containerView.bounds)
        effect.material = .underWindowBackground
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        effect.layer?.masksToBounds = true
        
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

        restoreTabsState()

        findBarViewController = FindBarViewController()
        findBarViewController.delegate = self
        findBarViewController.addTo(parentWindow: window!, topOffset: Settings.shared.dragAreaPosition == .top ? Constants.DRAGGABLE_AREA_HEIGHT : 0)
        
        contentView.addSubview(windowMarginView, positioned: .below, relativeTo: dragArea)
        contentView.addSubview(windowOutlineView, positioned: .above, relativeTo: nil)

        updateWindowMarginAndLayout()
        updateActiveWebview()
        updateHeaderTrackingArea()
        layoutSelectors()
        updateHeaderVisibility(animated: false)
    }

struct SecureTabState: Codable {
    var activeIndex: Int
    var openTabs: [Int: String]
    var tabInputs: [Int: TabInputState]?
    var tabPromptHistories: [Int: [PromptHistoryEntry]]?
    var tabPromptHistoryEnabledOverrides: [Int: Bool]?

    enum CodingKeys: String, CodingKey {
        case activeIndex
        case openTabs
        case tabInputs
        case tabPromptHistories
        case tabPromptHistoryEnabledOverrides
    }

    init(activeIndex: Int, openTabs: [Int: String], tabInputs: [Int: TabInputState]?, tabPromptHistories: [Int: [PromptHistoryEntry]]?, tabPromptHistoryEnabledOverrides: [Int: Bool]?) {
        self.activeIndex = activeIndex
        self.openTabs = openTabs
        self.tabInputs = tabInputs
        self.tabPromptHistories = tabPromptHistories
        self.tabPromptHistoryEnabledOverrides = tabPromptHistoryEnabledOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeIndex = try container.decode(Int.self, forKey: .activeIndex)
        openTabs = try container.decode([Int: String].self, forKey: .openTabs)
        tabInputs = try container.decodeIfPresent([Int: TabInputState].self, forKey: .tabInputs)
        tabPromptHistories = try container.decodeIfPresent([Int: [PromptHistoryEntry]].self, forKey: .tabPromptHistories)
        tabPromptHistoryEnabledOverrides = try container.decodeIfPresent([Int: Bool].self, forKey: .tabPromptHistoryEnabledOverrides)
    }
}

    func saveTabsState() {
        guard Settings.shared.tabSurvivalPolicy != .never else { return }

        var state = PersistedTabState()
        
        // Filter out encrypted engines from the global active Service URL
        if let currentURL = currentServiceURL,
           let svc = services.first(where: { $0.url == currentURL }),
           svc.isEncrypted {
            state.activeServiceURL = nil
        } else {
            state.activeServiceURL = currentServiceURL
        }
        
        // Filter out encrypted engines from global active indices
        var unencryptedIndices = activeIndicesByURL
        for svc in services where svc.isEncrypted {
            unencryptedIndices.removeValue(forKey: svc.url)
        }
        state.activeIndicesByURL = unencryptedIndices

        if let manager = webViewManager {
            var allOpenTabs = manager.getOpenSessionsState()
            var allTabInputs = manager.getOpenSessionsInputState()
            var allPromptHistories = manager.getOpenSessionsPromptHistories()
            var allPromptHistoryOverrides = manager.getOpenSessionsPromptHistoryOverrides()
            
            // Filter out services with preservePrompt disabled
            for svc in services {
                if !svc.preservePrompt {
                    allTabInputs.removeValue(forKey: svc.url)
                }
            }
            
            // Extract and save encrypted services securely
            for svc in services where svc.isEncrypted {
                if let sessions = allOpenTabs[svc.url] {
                    // Only save to secure storage if it's currently unlocked
                    if EncryptedVolumeManager.shared.isUnlocked(for: svc.id) {
                        let activeIdx = activeIndicesByURL[svc.url] ?? 0
                        let secureInputs = allTabInputs[svc.url]
                        let secureHistories = allPromptHistories[svc.url]
                        let secureOverrides = allPromptHistoryOverrides[svc.url]
                        let secureState = SecureTabState(
                            activeIndex: activeIdx,
                            openTabs: sessions,
                            tabInputs: secureInputs,
                            tabPromptHistories: secureHistories,
                            tabPromptHistoryEnabledOverrides: secureOverrides
                        )
                        let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: svc.id).appendingPathComponent("quiper_tabs.json")
                        if let data = try? JSONEncoder().encode(secureState) {
                            try? data.write(to: stateURL)
                        }
                    }
                }
                // Remove from the global unencrypted state
                allOpenTabs.removeValue(forKey: svc.url)
                allTabInputs.removeValue(forKey: svc.url)
                allPromptHistories.removeValue(forKey: svc.url)
                allPromptHistoryOverrides.removeValue(forKey: svc.url)
            }
            state.openTabs = allOpenTabs
            state.tabInputs = allTabInputs
            state.tabPromptHistories = allPromptHistories
            state.tabPromptHistoryEnabledOverrides = allPromptHistoryOverrides
        }

        Settings.shared.persistedTabState = state
        Settings.shared.saveSettings()
    }

    func restoreTabsState() {
        guard Settings.shared.tabSurvivalPolicy != .never,
              let savedState = Settings.shared.persistedTabState else {
            return
        }

        // Restore activeIndicesByURL
        for (url, index) in savedState.activeIndicesByURL {
            if services.contains(where: { $0.url == url }) {
                activeIndicesByURL[url] = index
            }
        }

        // Restore tab input states
        webViewManager.restoreTabInputStates(savedState.tabInputs)
        webViewManager.restoreTabPromptHistories(savedState.tabPromptHistories)
        webViewManager.restoreTabPromptHistoryOverrides(savedState.tabPromptHistoryEnabledOverrides)

        // Restore open tabs
        for (svcURL, sessions) in savedState.openTabs {
            guard let service = services.first(where: { $0.url == svcURL }) else { continue }
            
            var secureSessions = sessions
            if service.isEncrypted && EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: service.id).appendingPathComponent("quiper_tabs.json")
                if let data = try? Data(contentsOf: stateURL),
                   let secureState = try? JSONDecoder().decode(SecureTabState.self, from: data) {
                    secureSessions = secureState.openTabs
                    if let secureInputs = secureState.tabInputs {
                        webViewManager.restoreTabInputStates([service.url: secureInputs])
                    }
                    if let secureHistories = secureState.tabPromptHistories {
                        webViewManager.restoreTabPromptHistories([service.url: secureHistories])
                    }
                    if let secureOverrides = secureState.tabPromptHistoryEnabledOverrides {
                        webViewManager.restoreTabPromptHistoryOverrides([service.url: secureOverrides])
                    }
                }
            }
            
            for (sessionIndex, urlString) in secureSessions {
                // Pre-instantiate the webview with its restored URL
                _ = webViewManager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea, targetURL: urlString)

                // Set up observers
                if let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) {
                    setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
                }
            }
        }

        // Restore active service selection
        if let activeURL = savedState.activeServiceURL,
           services.contains(where: { $0.url == activeURL }) {
            currentServiceURL = activeURL
            if let index = services.firstIndex(where: { $0.url == activeURL }) {
                currentServiceName = services[index].name
            }
        }

        refreshInstantiationState()
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
        serviceSel.middleClickHandler = { [weak self] index in
            self?.handleServiceMiddleClick(at: index)
        }
        serviceSel.alwaysShowTooltips = false
        serviceSel.selectorDelegate = self
        serviceSel.showInstantiationState = true

        serviceSel.segmentCount = services.count
        for (index, service) in services.enumerated() {
            serviceSel.setLabel(service.name, forSegment: index)
            serviceSel.setImage(nil, forSegment: index)
            serviceSel.setToolTip(service.name, forSegment: index)
        }
        serviceSel.customLockedStates = services.map { $0.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: $0.id) }
        serviceSel.customLabels = services.map { $0.name }
        serviceSel.setAccessibilityIdentifier("ServiceSelector")
        drag.addSubview(serviceSel)
        serviceSelector = serviceSel

        // Service Selector (Collapsible)
        let collapsibleServiceSel = CollapsibleSelector()
        collapsibleServiceSel.enableDragReorder = true
        collapsibleServiceSel.target = self
        collapsibleServiceSel.action = #selector(serviceChanged(_:))
        collapsibleServiceSel.delegate = self
        collapsibleServiceSel.showInstantiationState = true
        collapsibleServiceSel.mouseDownSegmentHandler = serviceSel.mouseDownSegmentHandler
        collapsibleServiceSel.dragBeganHandler = serviceSel.dragBeganHandler
        collapsibleServiceSel.dragChangedHandler = serviceSel.dragChangedHandler
        collapsibleServiceSel.dragEndedHandler = serviceSel.dragEndedHandler
        collapsibleServiceSel.middleClickHandler = serviceSel.middleClickHandler
        collapsibleServiceSel.alwaysShowTooltips = false
        collapsibleServiceSel.setItems(services.map { $0.name })
        collapsibleServiceSel.placeholderLabel = "Engines"
        collapsibleServiceSel.emptyStateAlignment = .right
        collapsibleServiceSel.setContentHuggingPriority(.required, for: .horizontal)
        collapsibleServiceSel.setContentCompressionResistancePriority(.required, for: .horizontal)
        collapsibleServiceSel.setAccessibilityIdentifier("CollapsibleServiceSelector")
        drag.addSubview(collapsibleServiceSel)
        collapsibleServiceSelector = collapsibleServiceSel

        // Session Selector (Static)
        let sessionSel = SegmentedControl(frame: .zero)
        sessionSel.trackingMode = .selectOne
        sessionSel.segmentCount = 10
        sessionSel.customLabels = (0..<10).map { "\($0 == 9 ? 0 : $0 + 1)" }
        for i in 0..<10 {
            sessionSel.setLabel("\(i == 9 ? 0 : i + 1)", forSegment: i)
        }
        
        sessionSel.target = self
        sessionSel.action = #selector(sessionChanged(_:))
        sessionSel.selectorDelegate = self
        sessionSel.showInstantiationState = true
        sessionSel.middleClickHandler = { [weak self] segmentIndex in
            self?.handleSessionMiddleClick(at: segmentIndex)
        }
        sessionSel.sizeToFit()
        sessionSel.setAccessibilityIdentifier("SessionSelector")
        drag.addSubview(sessionSel)
        sessionSelector = sessionSel

        // Session Selector (Collapsible)
        let collapsibleSessionSel = CollapsibleSelector()
        collapsibleSessionSel.target = self
        collapsibleSessionSel.action = #selector(sessionChanged(_:))
        collapsibleSessionSel.setItems((0..<10).map { "\($0 == 9 ? 0 : $0 + 1)" })
        collapsibleSessionSel.placeholderLabel = "Sessions"
        collapsibleSessionSel.emptyStateAlignment = .left
        collapsibleSessionSel.delegate = self
        collapsibleSessionSel.showInstantiationState = true
        collapsibleSessionSel.middleClickHandler = { [weak self] segmentIndex in
            self?.handleSessionMiddleClick(at: segmentIndex)
        }
        collapsibleSessionSel.setContentHuggingPriority(.required, for: .horizontal)
        collapsibleSessionSel.setContentCompressionResistancePriority(.required, for: .horizontal)
        collapsibleSessionSel.setAccessibilityIdentifier("CollapsibleSessionSelector")
        drag.addSubview(collapsibleSessionSel)
        collapsibleSessionSelector = collapsibleSessionSel
        
        updateSelectorsMode()

        // Title Label
        let title = HoverTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.alignment = .center
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        drag.addSubview(title)
        titleLabel = title

        // Back/Forward Navigation Button Group
        let navGroup = NavigationButtonGroup()
        navGroup.isHidden = true
        navGroup.onBack = { [weak self] in self?.currentWebView()?.goBack() }
        navGroup.onForward = { [weak self] in self?.currentWebView()?.goForward() }
        navGroup.onLongPressBack = { [weak self] in
            guard let wv = self?.currentWebView() else { return [] }
            return wv.backForwardList.backList.reversed().map { ($0.title ?? "", $0.url) }
        }
        navGroup.onLongPressForward = { [weak self] in
            guard let wv = self?.currentWebView() else { return [] }
            return wv.backForwardList.forwardList.map { ($0.title ?? "", $0.url) }
        }
        navGroup.onNavigateToBackItem = { [weak self] (index: Int) in
            guard let wv = self?.currentWebView() else { return }
            let backList = Array(wv.backForwardList.backList.reversed())
            guard index < backList.count else { return }
            wv.go(to: backList[index])
        }
        navGroup.onNavigateToForwardItem = { [weak self] (index: Int) in
            guard let wv = self?.currentWebView() else { return }
            let forwardList = wv.backForwardList.forwardList
            guard index < forwardList.count else { return }
            wv.go(to: forwardList[index])
        }
        drag.addSubview(navGroup)
        navigationButtonGroup = navGroup
        
        // Trash Button Y & Size config
        let buttonIconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        
        // Prompt History Button
        let historyImage = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Prompt History")!
            .withSymbolConfiguration(buttonIconConfig)!
        let historyBtn = HoverIconButton(image: historyImage, target: self, action: #selector(promptHistoryButtonTapped(_:)))
        historyBtn.toolTip = "Prompt History"
        drag.addSubview(historyBtn)
        promptHistoryButton = historyBtn
        
        // Refresh/Stop Button
        let rsButton = RefreshStopButton()
        rsButton.target = self
        rsButton.action = #selector(refreshStopTapped(_:))
        drag.addSubview(rsButton)
        refreshStopButton = rsButton

        // Trash Button
        let trashImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Close Current Session")!.withSymbolConfiguration(buttonIconConfig)!
        let trashBtn = HoverIconButton(image: trashImage, target: self, action: #selector(closeSessionTapped(_:)))
        trashBtn.toolTip = "Close Current Session"
        drag.addSubview(trashBtn)
        trashSessionButton = trashBtn

        // Loading Border View
        let borderView = LoadingBorderView(frame: .zero)
        borderView.isHidden = true
        drag.addSubview(borderView, positioned: .below, relativeTo: title)
        loadingBorderView = borderView
        
        title.hitTestView = borderView
        
        title.shouldShowTooltip = { [weak self] event in
            guard let self = self,
                  let sessionSel = self.collapsibleSessionSelector,
                  let mainWindow = self.window else { return true }
            
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
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let actionsImage = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Session Actions")!.withSymbolConfiguration(iconConfig)!
        let actionsBtn = HoverIconButton(image: actionsImage, target: self, action: #selector(sessionActionsButtonTapped(_:)))
        actionsBtn.toolTip = "Session Actions"
        drag.addSubview(actionsBtn)
        sessionActionsButton = actionsBtn

        // Manual Lock Button
        let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock Engine")!.withSymbolConfiguration(iconConfig)!
        let lockBtn = HoverIconButton(image: lockImage, target: self, action: #selector(manualLockTapped(_:)))
        lockBtn.toolTip = "Lock Engine"
        drag.addSubview(lockBtn)
        manualLockButton = lockBtn

        layoutSelectors()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDockVisibilityChanged), name: .dockVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSelectorDisplayModeChanged), name: .selectorDisplayModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(topBarVisibilityChanged), name: .topBarVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dragAreaPositionChanged), name: .dragAreaPositionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowAppearanceChanged), name: .windowAppearanceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationStatusChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationStatusChanged), name: NSApplication.didResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWorkspaceWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleColorSchemeChanged), name: .colorSchemeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowOnAllSpacesChanged), name: .showOnAllSpacesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowSettings), name: .settingsWindowDidOpen, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseSettings), name: .settingsWindowDidClose, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleServicesIconsUpdated), name: .servicesIconsUpdated, object: nil)
        
        if let window = self.window {
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowDidResize), name: NSWindow.didResizeNotification, object: window)
            window.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        }
        
        applyColorScheme()
    }

    @objc func serviceChanged(_ sender: Any?) {
        let selectedIndex: Int
        if let control = sender as? SegmentedControl {
            selectedIndex = control.selectedSegment
        } else if let collapsible = sender as? CollapsibleSelector {
            selectedIndex = collapsible.selectedSegment
        } else {
            return
        }
        selectService(at: selectedIndex)
    }

    @objc func sessionChanged(_ sender: Any?) {
        let selectedIndex: Int
        if let control = sender as? SegmentedControl {
            selectedIndex = control.selectedSegment
        } else if let collapsible = sender as? CollapsibleSelector {
            selectedIndex = collapsible.selectedSegment
        } else {
            return
        }
        let targetSession = sessionIndex(forSegment: selectedIndex)
        switchSession(to: targetSession)
    }

    @objc private func handleApplicationStatusChanged(_ notification: Notification) {
        if notification.name == NSApplication.didBecomeActiveNotification {
            checkInactivityLock()
        } else if notification.name == NSApplication.didResignActiveNotification {
            isModifiersForHeaderDown = false
            collapsibleSessionSelector?.collapse()
            collapsibleServiceSelector?.collapse()
        }
        updateHeaderVisibility(animated: true)
    }

    @objc private func handleWorkspaceWake(_ notification: Notification) {
        checkInactivityLock()
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
    
    @objc private func handleServicesIconsUpdated(_ notification: Notification) {
        refreshServiceSegments()
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

    @objc func handleServiceDragBegan(from sourceIndex: Int) {
        draggingServiceIndex = sourceIndex
    }

    @objc func handleServiceDragChanged(to destinationIndex: Int) {
        guard let sourceIndex = draggingServiceIndex, sourceIndex != destinationIndex else { return }
        
        var updated = services
        let removed = updated.remove(at: sourceIndex)
        updated.insert(removed, at: destinationIndex)
        
        services = updated
        draggingServiceIndex = destinationIndex
        
        Settings.shared.services = updated
        Settings.shared.saveSettings()
        NotificationCenter.default.post(name: .servicesOrderUpdated, object: nil)
        
        if let idx = services.firstIndex(where: { $0.url == currentServiceURL }) {
            serviceSelector?.selectedSegment = idx
            collapsibleServiceSelector?.selectedSegment = idx
        }
    }

    @objc func handleServiceDragEnded() {
        draggingServiceIndex = nil
        refreshServiceSegments()
        layoutSelectors()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen else { return frameSize }
        let screenFrame = screen.frame
        return NSSize(width: min(frameSize.width, screenFrame.width),
                      height: min(frameSize.height, screenFrame.height))
    }

    func windowDidResize(_ notification: Notification) {
        updateWindowMarginAndLayout()
        layoutSelectors()
        updateHeaderTrackingArea()
    }

    func windowShouldBecomeKey(_ sender: NSWindow) -> Bool {
        if AppDelegate.sharedSettingsWindow.isVisible {
            return false
        }
        if let updateWindow = UpdatePromptWindowController.shared.window, updateWindow.isVisible {
            return false
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let settingsWindow = AppDelegate.sharedSettingsWindow
        if settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let updateWindow = UpdatePromptWindowController.shared.window, updateWindow.isVisible {
            updateWindow.makeKeyAndOrderFront(nil)
            return
        }

        let otherChildWindows = window?.childWindows?.filter {
            $0 != settingsWindow &&
            $0 != UpdatePromptWindowController.shared.window &&
            $0 != blurWindow &&
            $0 != findBarViewController?.panel
        } ?? []
        if !otherChildWindows.isEmpty {
            return
        }
        
        focusInputInActiveWebviewWithFallback()
        
        GhostOnboardingManager.shared.start(in: self)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if let keyWindow = NSApp.keyWindow,
           window?.childWindows?.contains(keyWindow) == true {
            return
        }
        if !GhostOnboardingManager.shared.isActive {
            collapsibleServiceSelector?.collapse()
            collapsibleSessionSelector?.collapse()
        }
        GhostOnboardingManager.shared.windowDidResignKey()
        hideModifierHUD()
        saveTabsState()
    }
}

extension MainWindowController {
    func showOnboardingHUD(step: Int, title: String, text: String, target: NSView?) {
        guard let contentView = window?.contentView else { return }
        
        if onboardingHUD == nil {
            let hud = GhostOnboardingHUDView()
            hud.frame = contentView.bounds
            hud.autoresizingMask = [.width, .height]
            contentView.addSubview(hud, positioned: .above, relativeTo: nil)
            onboardingHUD = hud
            
            hud.onNextHandler = {
                GhostOnboardingManager.shared.advanceStep()
            }
        }
        
        onboardingHUD?.update(step: step, title: title, text: text, target: target)
        
        if let hud = onboardingHUD {
            window?.makeFirstResponder(hud)
        }
    }
    
    func hideOnboardingHUD() {
        onboardingHUD?.removeFromSuperview()
        onboardingHUD = nil
    }

    func showQuitOverlay() {
        guard let contentView = window?.contentView else { return }
        
        let overlay = QuitOverlayView(frame: contentView.bounds)
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        
        window?.standardWindowButton(.closeButton)?.isEnabled = false
        window?.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window?.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}

