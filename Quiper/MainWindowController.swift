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
    typealias CGSSpaceID = UInt64
    typealias CGSSetWindowBackgroundBlurRadiusFunc = @convention(c) (CGSConnectionID, CGSWindowID, Int32) -> Int32
    typealias CGSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID
    typealias CGSCopySpacesForWindowsFunc = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias CGSMoveWindowsToManagedSpaceFunc = @convention(c) (CGSConnectionID, CFArray, CGSSpaceID) -> Int32
    typealias CGSManagedDisplayGetCurrentSpaceFunc = @convention(c) (CGSConnectionID, CFString) -> CGSSpaceID

    static var getMainConnection: CGSMainConnectionIDFunc?
    static var setBlurRadius: CGSSetWindowBackgroundBlurRadiusFunc?
    static var copySpacesForWindows: CGSCopySpacesForWindowsFunc?
    static var moveWindowsToManagedSpace: CGSMoveWindowsToManagedSpaceFunc?
    static var managedDisplayGetCurrentSpace: CGSManagedDisplayGetCurrentSpaceFunc?
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

            if let copySpacesSym = dlsym(validHandle, "SLSCopySpacesForWindows") ?? dlsym(validHandle, "CGSCopySpacesForWindows") {
                copySpacesForWindows = unsafeBitCast(copySpacesSym, to: CGSCopySpacesForWindowsFunc.self)
            }

            if let moveWindowsSym = dlsym(validHandle, "SLSMoveWindowsToManagedSpace") ?? dlsym(validHandle, "CGSMoveWindowsToManagedSpace") {
                moveWindowsToManagedSpace = unsafeBitCast(moveWindowsSym, to: CGSMoveWindowsToManagedSpaceFunc.self)
            }

            if let currentSpaceSym = dlsym(validHandle, "SLSManagedDisplayGetCurrentSpace") ?? dlsym(validHandle, "CGSManagedDisplayGetCurrentSpace") {
                managedDisplayGetCurrentSpace = unsafeBitCast(currentSpaceSym, to: CGSManagedDisplayGetCurrentSpaceFunc.self)
            }
        }
        initialized = true
    }

    static func activeSpace(for screen: NSScreen?) -> CGSSpaceID? {
        initialize()
        guard let screen,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let displayUUID = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(displayNumber.uint32Value))?.takeRetainedValue(),
              let displayUUIDString = CFUUIDCreateString(nil, displayUUID),
              let getMainConnection,
              let managedDisplayGetCurrentSpace else {
            return nil
        }

        let space = managedDisplayGetCurrentSpace(getMainConnection(), displayUUIDString)
        return space == 0 ? nil : space
    }

    static func spaces(for window: NSWindow) -> [CGSSpaceID] {
        initialize()
        guard window.windowNumber > 0,
              let getMainConnection,
              let copySpacesForWindows else {
            return []
        }

        let windowIDs = [NSNumber(value: UInt32(window.windowNumber))] as CFArray
        guard let spaces = copySpacesForWindows(getMainConnection(), 0x7, windowIDs)?.takeRetainedValue() else {
            return []
        }

        return (spaces as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
    }

    static func move(_ windows: [NSWindow], to space: CGSSpaceID) -> Bool {
        initialize()
        guard let getMainConnection,
              let moveWindowsToManagedSpace else {
            return false
        }

        let windowIDs = windows.compactMap { window -> NSNumber? in
            guard window.windowNumber > 0 else { return nil }
            return NSNumber(value: UInt32(window.windowNumber))
        }
        guard !windowIDs.isEmpty else { return false }

        return moveWindowsToManagedSpace(
            getMainConnection(),
            windowIDs as CFArray,
            space
        ) == 0
    }
}

@MainActor
final class PassthroughBannerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let jsTools: [String: String] = [
        "waitFor": """
        function waitFor(check, timeoutMs = 1000) {
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
    var sessionTitleObservations: [TabIdentifier: NSKeyValueObservation] = [:]
    var services: [Service] = []
    var currentServiceName: String?
    var currentServiceID: UUID?
    var webViewManager: WebViewManager!
    var emptyStateView: EmptyStateView!
    var findBarViewController: FindBarViewController!
    var findBarViewControllers: [ObjectIdentifier: FindBarViewController] = [:]
    var draggingServiceIndex: Int?
    var activeIndicesByID: [UUID: Int] = [:]
    
    // MARK: - Tab History & MRU Navigation
    var tabHistory: [TabIdentifier] = []
    var lastActiveTab: TabIdentifier?
    var isCyclingHistory = false
    var cyclingHistoryIndex = 0
    var cyclingStartTab: TabIdentifier?
    var historyCyclingTimer: Timer?
    var historyDebounceTimer: Timer?
    var highlightedTab: TabIdentifier?
    var lastHistorySwitchTime: Date?
    var isGraveKeyHeld = false
    var isCyclingForward = true
    var historyRepeatTimer: Timer?
    var isExecutingHistoryNavigation = false
    var tabHistoryHUDView: TabHistoryHUDView?
    var tabHistoryHUDWindow: NSWindow?
    var promptHistoryHUDWindow: NSWindow?
    var modifierHUDWindow: NSWindow?
    var locationBarHUDWindow: NSWindow?
    var tabPreviews: [TabIdentifier: NSImage] = [:]

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
    var isHeaderForcedVisibleForLocationBar = false
    var isUpdatingHeaderVisibility = false
    var isWindowBeingDragged = false
    var selectorCursorMonitor: Timer?
    var lastCommandPressedTime: TimeInterval = 0
    var lastCommandReleasedTime: TimeInterval = 0
    var wasBothCmdsDown = false
    var modifierHUDView: ModifierHUDView?
    var promptHistoryHUDView: PromptHistoryHUDView?
    var locationBarHUDView: LocationBarHUDView?
    var onboardingHUD: GhostOnboardingHUDView?

    private var isCompactMode = false
    private var previousWindowFrame: NSRect?
    var isWebContentFullscreen = false
    private weak var webFullScreenWindow: NSWindow?
    private var webFullScreenBannerView: NSView?
    private var webFullScreenBannerTimer: Timer?

    // True only when web content is fullscreen AND its fullscreen window is on
    // the active space. Quiper may still show in a non-fullscreen space; it must
    // only be blocked while the user is actually looking at the fullscreen space.
    // During transitions the fullscreen window may be briefly unidentifiable; in
    // that case stay conservative and block the show rather than risk revealing
    // the overlay inside the fullscreen space.
    var isActiveSpaceWebFullscreen: Bool {
        guard isWebContentFullscreen else { return false }
        guard let fullScreenWindow = webFullScreenWindow else { return true }
        return fullScreenWindow.isOnActiveSpace
    }

    private var elementFullscreenWebView: WKWebView?
    private var elementFullscreenOriginSpace: CGSFuncs.CGSSpaceID?
    private var shouldRestoreCollectionBehaviorAfterElementFullscreen = false

    /// The Space currently owned by a fullscreen element of Quiper's own web
    /// content, if any. Quiper's own overlay must never open inside it —
    /// doing so corrupts the overlay's Space state when the element exits.
    /// Fullscreen Spaces owned by *other* applications are unaffected.
    var ownedElementFullscreenSpace: CGSFuncs.CGSSpaceID? {
        guard let webFullScreenWindow else { return nil }
        return CGSFuncs.spaces(for: webFullScreenWindow).first
    }

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
            if let hw = tabHistoryHUDWindow {
                win?.removeChildWindow(hw)
                hw.orderOut(nil)
                hw.close()
            }
            if let phw = promptHistoryHUDWindow {
                win?.removeChildWindow(phw)
                phw.orderOut(nil)
                phw.close()
            }
            if let mhw = modifierHUDWindow {
                win?.removeChildWindow(mhw)
                mhw.orderOut(nil)
                mhw.close()
            }
            if let lbhw = locationBarHUDWindow {
                win?.removeChildWindow(lbhw)
                lbhw.orderOut(nil)
                lbhw.close()
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
        // Settings.shared already loads from disk in its initializer; avoid a second loadSettings()
        // that can re-stamp migration state mid-launch.
        let initialServices = services ?? Settings.shared.services
        
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
            self.activeIndicesByID[service.id] = sessionIndex
            self.selectService(at: svcIndex)
        }
        emptyStateView.onWindowDragBegan = { [weak self] in
            self?.isWindowBeingDragged = true
        }
        emptyStateView.onWindowDragEnded = { [weak self] in
            self?.isWindowBeingDragged = false
            self?.updateHeaderVisibility()
        }
        emptyStateView.isHidden = true
        contentView.addSubview(emptyStateView)
        
        self.services = initialServices
        webViewManager.updateServices(initialServices)
        
        self.services.forEach { service in
            activeIndicesByID[service.id] = 0
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
    var activeServiceID: UUID? { currentService()?.id }
    var activeSessionIndex: Int {
        guard let service = currentService() else { return 0 }
        return activeIndicesByID[service.id] ?? 0
    }

    var activeWebView: WKWebView? {
        guard let manager = webViewManager else { return nil }
        guard let service = currentService(),
              let index = activeIndicesByID[service.id] else {
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
        let selector = Settings.shared.promptInputSelector(for: service)
        guard !selector.isEmpty else { return }
        guard let webView = currentWebView() else { return }
        let sessionIdx = activeIndicesByID[service.id] ?? 0
        let shouldRestore = service.preservePrompt
        let inputState = shouldRestore ? webViewManager?.getTabInputState(for: service.id, sessionIndex: sessionIdx) : nil

        let hasSaved = inputState != nil
        let text = inputState?.text ?? ""
        let start = inputState?.start ?? 0
        let end = inputState?.end ?? 0
        let jsString = WebScripts.makeFocusInputScript(
            selector: selector,
            hasSaved: hasSaved,
            text: text,
            start: start,
            end: end
        )
        
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
        if action.id == DefaultEngineDefinitions.openSettingsActionID {
            presentEngineSettingsShortcutNoticeIfNeeded()
        }
        let effectiveService = Settings.shared.services.first(where: { $0.id == service.id }) ?? service
        let storedScript = Settings.shared.actionScript(for: effectiveService, action: action)
        let rawScript = storedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let script: String
        if rawScript.isEmpty {
            script = WebScripts.makeActionFallbackScript(actionName: action.name, serviceName: service.name)
            playErrorSound()
        } else {
            script = rawScript
        }

        let wrappedScript = WebScripts.makeActionRunnerScript(script: script)

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
    
    private func presentEngineSettingsShortcutNoticeIfNeeded() {
        guard !AppController.isRunningTests,
              !Constants.LaunchMode.shouldSuppressInterferenceUI,
              !Settings.shared.hasDismissedEngineSettingsShortcutNotice,
              let window else { return }

        let alert = NSAlert()
        alert.messageText = "Cmd+,"
        alert.informativeText = "Cmd+, now opens the Settings of the engine you're using, not Quiper's Settings. To change Quiper's Settings, use Cmd+Shift+,."

        let checkbox = NSButton(checkboxWithTitle: "Don't show this again", target: nil, action: nil)
        checkbox.font = .systemFont(ofSize: 11)
        alert.accessoryView = checkbox

        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { _ in
            if checkbox.state == .on {
                Settings.shared.hasDismissedEngineSettingsShortcutNotice = true
            }
        }
    }
    
    func playErrorSound() {
        NSSound.beep()
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("QuiperTestBeep"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    var isEmptyStateActive: Bool {
        return emptyStateView != nil && !emptyStateView.isHidden
    }

    func currentWebView() -> WKWebView? {
        guard let manager = webViewManager else { return nil }
        guard let service = currentService(),
              let index = activeIndicesByID[service.id] else {
            return nil
        }
        return manager.getWebView(for: service, sessionIndex: index)
    }

    func show() {
        guard !isActiveSpaceWebFullscreen else {
            showWebFullScreenBanner()
            return
        }
        if let fullscreenWindow = webFullScreenWindow {
            showWebFullScreenBanner()
            NSApp.activate(ignoringOtherApps: true)
            fullscreenWindow.makeKeyAndOrderFront(nil)
            return
        }
        checkInactivityLock()
        var didTeleport = false
        if let window = window {
            // Session-aware: during an element-fullscreen session this keeps
            // canJoinAllSpaces off so the overlay cannot appear in the owned
            // fullscreen Space.
            updateCollectionBehaviorForVisibilityState()
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
        if !didTeleport && ownedElementFullscreenSpace == nil {
            updateCollectionBehaviorForVisibilityState()
        }
        NotificationCenter.default.post(name: .windowDidShow, object: nil)
    }

    func hide() {
        NSLog("[HideBlock] hide: isFS=%d fsWindow=%d isOnActiveSpace=%d owned=%@ active=%@ overlayVisible=%d",
              isWebContentFullscreen ? 1 : 0,
              webFullScreenWindow != nil ? 1 : 0,
              isActiveSpaceWebFullscreen ? 1 : 0,
              ownedElementFullscreenSpace.map(String.init(describing:)) ?? "nil",
              window.flatMap { CGSFuncs.activeSpace(for: $0.screen) }.map(String.init(describing:)) ?? "nil",
              window?.isVisible == true ? 1 : 0)
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet, returnCode: .cancel)
        }
        window?.orderOut(nil)
        
        updateCollectionBehaviorForVisibilityState()
        
        findBarViewController?.hide()
        setShortcutsEnabled(false)
        hideModifierHUD()
        hideLocationBarHUD()
        NotificationCenter.default.post(name: .windowDidHide, object: nil)
    }

    func handleElementFullscreenStateChange(
        _ state: WKWebView.FullscreenState,
        for webView: WKWebView
    ) {
        switch state {
        case .enteringFullscreen:
            elementFullscreenWebView = webView
            isWebContentFullscreen = true
            shouldRestoreCollectionBehaviorAfterElementFullscreen = false
            if let window {
                elementFullscreenOriginSpace = CGSFuncs.activeSpace(for: window.screen)
                    ?? CGSFuncs.spaces(for: window).first
            }
        case .inFullscreen:
            elementFullscreenWebView = webView
            isWebContentFullscreen = true
        case .exitingFullscreen:
            guard elementFullscreenWebView === webView, let window else { return }

            let wasHidden = !window.isVisible
            guard let originSpace = elementFullscreenOriginSpace,
                  let fullscreenSpace = CGSFuncs.activeSpace(for: webView.window?.screen),
                  originSpace != fullscreenSpace,
                  wasHidden || CGSFuncs.spaces(for: window).contains(fullscreenSpace) else {
                return
            }

            shouldRestoreCollectionBehaviorAfterElementFullscreen = true
            let windowsToMove = [window] + (window.childWindows ?? [])
            if !CGSFuncs.move(windowsToMove, to: originSpace) {
                NSLog("[Quiper] Could not move the window out of the exiting fullscreen Space")
            }
            if wasHidden {
                window.makeKeyAndOrderFront(nil)
                setShortcutsEnabled(true)
            }
        case .notInFullscreen:
            if elementFullscreenWebView === webView {
                clearElementFullscreenState()
            }
        @unknown default:
            break
        }
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
        if locationBarHUDWindow?.isVisible == true {
            alignLocationBarHUDWindow()
        }
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
        
        activeIndicesByID.removeAll()
        for service in services {
            activeIndicesByID[service.id] = 0
        }
        webViewManager.updateServices(services)

        restoreTabsState()

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
    var tabTitles: [Int: String]?
    var tabInputs: [Int: TabInputState]?
    var tabPromptHistories: [Int: [PromptHistoryEntry]]?
    var tabPromptHistoryEnabledOverrides: [Int: Bool]?

    enum CodingKeys: String, CodingKey {
        case activeIndex
        case openTabs
        case tabTitles
        case tabInputs
        case tabPromptHistories
        case tabPromptHistoryEnabledOverrides
    }

    init(activeIndex: Int, openTabs: [Int: String], tabTitles: [Int: String]?, tabInputs: [Int: TabInputState]?, tabPromptHistories: [Int: [PromptHistoryEntry]]?, tabPromptHistoryEnabledOverrides: [Int: Bool]?) {
        self.activeIndex = activeIndex
        self.openTabs = openTabs
        self.tabTitles = tabTitles
        self.tabInputs = tabInputs
        self.tabPromptHistories = tabPromptHistories
        self.tabPromptHistoryEnabledOverrides = tabPromptHistoryEnabledOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeIndex = try container.decode(Int.self, forKey: .activeIndex)
        openTabs = try container.decode([Int: String].self, forKey: .openTabs)
        tabTitles = try container.decodeIfPresent([Int: String].self, forKey: .tabTitles)
        tabInputs = try container.decodeIfPresent([Int: TabInputState].self, forKey: .tabInputs)
        tabPromptHistories = try container.decodeIfPresent([Int: [PromptHistoryEntry]].self, forKey: .tabPromptHistories)
        tabPromptHistoryEnabledOverrides = try container.decodeIfPresent([Int: Bool].self, forKey: .tabPromptHistoryEnabledOverrides)
    }
}

    func saveTabsState() {
        guard Settings.shared.tabSurvivalPolicy != .never else { return }

        var state = PersistedTabState()
        
        // Filter out encrypted engines from the global active Service URL
        if let currentID = currentServiceID,
           let svc = services.first(where: { $0.id == currentID }),
           svc.isEncrypted {
            state.activeServiceID = nil
        } else {
            state.activeServiceID = currentService()?.id
        }
        
        // Filter out encrypted engines from global active indices
        var unencryptedIndices = activeIndicesByID
        for svc in services where svc.isEncrypted {
            unencryptedIndices.removeValue(forKey: svc.id)
        }
        state.activeIndicesByID = unencryptedIndices
        state.tabHistory = tabHistory

        if let manager = webViewManager {
            var allOpenTabs = manager.getOpenSessionsState()
            var allTabTitles = manager.getOpenSessionTitlesState()
            var allTabInputs = manager.getOpenSessionsInputState()
            var allPromptHistories = manager.getOpenSessionsPromptHistories()
            var allPromptHistoryOverrides = manager.getOpenSessionsPromptHistoryOverrides()
            
            // Filter out services with preservePrompt disabled
            for svc in services {
                if !svc.preservePrompt {
                    allTabInputs.removeValue(forKey: svc.id)
                }
            }
            
            // Extract and save encrypted services securely
            for svc in services where svc.isEncrypted {
                if let sessions = allOpenTabs[svc.id] {
                    // Only save to secure storage if it's currently unlocked
                    if EncryptedVolumeManager.shared.isUnlocked(for: svc.id) {
                        let activeIdx = activeIndicesByID[svc.id] ?? 0
                        let secureTitles = allTabTitles[svc.id]
                        let secureInputs = allTabInputs[svc.id]
                        let secureHistories = allPromptHistories[svc.id]
                        let secureOverrides = allPromptHistoryOverrides[svc.id]
                        let secureState = SecureTabState(
                            activeIndex: activeIdx,
                            openTabs: sessions,
                            tabTitles: secureTitles,
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
                allOpenTabs.removeValue(forKey: svc.id)
                allTabTitles.removeValue(forKey: svc.id)
                allTabInputs.removeValue(forKey: svc.id)
                allPromptHistories.removeValue(forKey: svc.id)
                allPromptHistoryOverrides.removeValue(forKey: svc.id)
            }
            state.openTabs = allOpenTabs
            state.tabTitles = allTabTitles
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

        if let history = savedState.tabHistory {
            tabHistory = history
            if let last = history.first {
                lastActiveTab = last
            }
        }

        // Restore activeIndicesByID
        for (svcID, index) in savedState.activeIndicesByID {
            if services.contains(where: { $0.id == svcID }) {
                activeIndicesByID[svcID] = index
            }
        }

        // Restore tab input states
        webViewManager.restoreTabInputStates(savedState.tabInputs)
        webViewManager.restoreTabPromptHistories(savedState.tabPromptHistories)
        webViewManager.restoreTabPromptHistoryOverrides(savedState.tabPromptHistoryEnabledOverrides)

        // Restore open tabs
        for (svcID, sessions) in savedState.openTabs {
            guard let service = services.first(where: { $0.id == svcID }) else { continue }
            
            var secureSessions = sessions
            var restoredTitles = savedState.tabTitles[svcID] ?? [:]
            if service.isEncrypted && EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: service.id).appendingPathComponent("quiper_tabs.json")
                if let data = try? Data(contentsOf: stateURL),
                   let secureState = try? JSONDecoder().decode(SecureTabState.self, from: data) {
                    secureSessions = secureState.openTabs
                    restoredTitles = secureState.tabTitles ?? [:]
                    if let secureInputs = secureState.tabInputs {
                        webViewManager.restoreTabInputStates([service.id: secureInputs])
                    }
                    if let secureHistories = secureState.tabPromptHistories {
                        webViewManager.restoreTabPromptHistories([service.id: secureHistories])
                    }
                    if let secureOverrides = secureState.tabPromptHistoryEnabledOverrides {
                        webViewManager.restoreTabPromptHistoryOverrides([service.id: secureOverrides])
                    }
                }
            }
            
            let activeIndex = activeIndicesByID[service.id] ?? 0
            for (sessionIndex, urlString) in secureSessions {
                // Pre-instantiate the webview with its restored URL
                _ = webViewManager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea, targetURL: urlString, restoredTitle: restoredTitles[sessionIndex], loadImmediately: (sessionIndex == activeIndex))

                // Set up observers
                if let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) {
                    setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
                }
            }
        }

        // Restore active service selection
        if let activeID = savedState.activeServiceID,
           let service = services.first(where: { $0.id == activeID }) {
            currentServiceID = service.id
            currentServiceName = service.name
        }

        refreshInstantiationState()
        updateSessionSelector()
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
        drag.onWindowDragBegan = { [weak self] in
            self?.isWindowBeingDragged = true
        }
        drag.onWindowDragEnded = { [weak self] in
            self?.isWindowBeingDragged = false
            self?.updateHeaderVisibility()
        }
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
        sessionSel.segmentCount = SessionSlots.count
        sessionSel.customLabels = SessionSlots.range.map(SessionSlots.label(for:))
        for i in SessionSlots.range {
            sessionSel.setLabel(SessionSlots.label(for: i), forSegment: i)
        }
        
        sessionSel.target = self
        sessionSel.action = #selector(sessionChanged(_:))
        sessionSel.selectorDelegate = self
        sessionSel.showInstantiationState = true
        sessionSel.requiresInstantiatedSegmentForTooltip = true
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
        collapsibleSessionSel.setItems(SessionSlots.range.map(SessionSlots.label(for:)))
        collapsibleSessionSel.placeholderLabel = "Sessions"
        collapsibleSessionSel.emptyStateAlignment = .left
        collapsibleSessionSel.delegate = self
        collapsibleSessionSel.showInstantiationState = true
        collapsibleSessionSel.requiresInstantiatedSegmentForTooltip = true
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
        historyBtn.tooltipText = "Prompt History"
        historyBtn.tooltipShortcut = "⌘Y"
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
        trashBtn.tooltipText = "Close Current Session"
        trashBtn.tooltipShortcut = "⌘W"
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
        title.onClick = { [weak self] in
            self?.toggleLocationBarHUD()
        }

        // Session Actions Button
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let actionsImage = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Session Actions")!.withSymbolConfiguration(iconConfig)!
        let actionsBtn = HoverIconButton(image: actionsImage, target: self, action: #selector(sessionActionsButtonTapped(_:)))
        actionsBtn.tooltipText = "Session Actions"
        drag.addSubview(actionsBtn)
        sessionActionsButton = actionsBtn

        // Manual Lock Button
        let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock Engine")!.withSymbolConfiguration(iconConfig)!
        let lockBtn = HoverIconButton(image: lockImage, target: self, action: #selector(manualLockTapped(_:)))
        drag.addSubview(lockBtn)
        manualLockButton = lockBtn
        updateLockButtonToolTip()

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowEnteredWebFullScreen), name: NSWindow.didEnterFullScreenNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowWillExitWebFullScreen), name: NSWindow.willExitFullScreenNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowDidExitWebFullScreen), name: NSWindow.didExitFullScreenNotification, object: nil)
        
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
            hideLocationBarHUD()
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
        if Settings.shared.engineSelectorDisplayMode == .auto
            || Settings.shared.sessionSelectorDisplayMode == .auto {
            updateSelectorsMode()
            layoutSelectors()
        }
        updateWindowMarginAndLayout()
        updateHeaderTrackingArea()
    }
    
    @objc private func handleServicesIconsUpdated(_ notification: Notification) {
        refreshServiceSegments()
    }
    
    @objc private func handleWindowEnteredWebFullScreen(_ notification: Notification) {
        // The notification's window is WebKit's element-fullscreen window (it is
        // the only non-overlay window in the app that can enter fullscreen). Use
        // it directly for identity; the webview read has a small timing lag.
        guard let window = notification.object as? NSWindow, window !== self.window else { return }
        webFullScreenWindow = window
        isWebContentFullscreen = true

        // The element's fullscreen Space is now owned by Quiper's own web
        // content, and a visible overlay would be dragged into it by
        // `.moveToActiveSpace` on the Space switch. Hide it for the duration
        // of the session — the exitingFullscreen handler brings it back to
        // its origin Space afterwards.
        self.window?.orderOut(nil)
        NSLog("[FullSpace] entered: fsWindowSpaces=\(CGSFuncs.spaces(for: window).map(String.init(describing:)).joined(separator: ",")) overlaySpaces=\(self.window.map { CGSFuncs.spaces(for: $0).map(String.init(describing:)).joined(separator: ",") } ?? "nil")")
    }
    
    @objc private func handleWindowWillExitWebFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === webFullScreenWindow else { return }
        clearElementFullscreenState()
    }

    @objc private func handleWindowDidExitWebFullScreen(_ notification: Notification) {
        // WebKit re-parents the webView back to its wrapper between
        // willExit and didExit. The wrapper is already at the correct
        // overlay size, but the webView is still sized to the fullscreen
        // window; force it back and dispatch a resize so media queries
        // recompute (otherwise the viewport stays at screen width and the
        // page overflows / looks zoomed-out).
        guard notification.object as? NSWindow !== self.window else { return }
        restoreWebViewLayoutAfterFullscreen()
    }

    private func clearElementFullscreenState() {
        let previousFullscreenWebView = elementFullscreenWebView
        elementFullscreenWebView = nil
        elementFullscreenOriginSpace = nil
        webFullScreenWindow = nil
        isWebContentFullscreen = false
        removeWebFullScreenBanner()

        // The fullscreen session is over: give the overlay its normal
        // all-Spaces behavior back (it was pinned to a single Space so it
        // could not bleed into the owned fullscreen Space).
        shouldRestoreCollectionBehaviorAfterElementFullscreen = false
        updateCollectionBehaviorForVisibilityState()
        // willExit fires before WebKit moves the webView back to its
        // wrapper. Schedule the viewport fix for after the re-parent, and
        // also handle the case where didExit is not delivered (e.g. the
        // window was closed programmatically).
        restoreWebViewLayoutAfterFullscreen(previousFullscreenWebView: previousFullscreenWebView)
    }

    private func restoreWebViewLayoutAfterFullscreen(previousFullscreenWebView: WKWebView? = nil) {
        // Capture the specific fullscreen webView before it is nil-ed so
        // popup windows (whose webView is not in WebViewManager) are also
        // repaired. For managed webViews the manager iteration below is
        // sufficient, but this covers the unmanaged popup case.
        let capturedPopupWebView = previousFullscreenWebView ?? elementFullscreenWebView

        func repairPopupIfNeeded() {
            guard let webView = capturedPopupWebView,
                  let superview = webView.superview else { return }
            // Popup webViews are hosted directly in a ModalPopupWindow's
            // contentView. After fullscreen WebKit leaves them sized to
            // screen dimensions; clamp back to superview bounds.
            if webView.frame != superview.bounds {
                webView.frame = superview.bounds
            }
            webView.needsLayout = true
            webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
        }

        // Immediate pass if the webView is already back in its wrapper.
        updateWindowMarginAndLayout()
        webViewManager.refreshViewportAfterFullscreenExit()
        repairPopupIfNeeded()

        // didExit re-parent can be one runloop turn later; cover it.
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowMarginAndLayout()
            self?.webViewManager.refreshViewportAfterFullscreenExit()
            repairPopupIfNeeded()
        }
        // Fullscreen exit animation is ~0.3s; a late pass catches any
        // remaining stale frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.updateWindowMarginAndLayout()
            self?.webViewManager.refreshViewportAfterFullscreenExit()
            repairPopupIfNeeded()
        }
    }

    /// Called before an encrypted service's webViews are torn down for locking.
    /// If that service owns the current element-fullscreen webView, the
    /// fullscreen window must be closed and the webView detached before the
    /// teardown, otherwise the fullscreen webView's layer can linger as a
    /// ghost background behind the overlay's transparent regions.
    func prepareForLockingEncryptedService(_ service: Service) {
        guard isWebContentFullscreen, let fullscreenWebView = elementFullscreenWebView else { return }
        guard let sessionMap = webViewManager.webviewsByID[service.id],
              sessionMap.values.contains(where: { $0 === fullscreenWebView }) else {
            return
        }
        NSLog("[FullSpace] Locking service %@ while fullscreen – cleaning up fullscreen window before teardown", service.name)
        let wasHidden = window?.isVisible == false
        webFullScreenWindow?.close()
        fullscreenWebView.removeFromSuperview()
        clearElementFullscreenState()
        if wasHidden {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            updateCollectionBehaviorForVisibilityState()
        }
    }

    // While web content is in fullscreen (a site entered the Fullscreen API),
    // Quiper stays in the space it was on and does not respond to global
    // shortcuts. If the user tries to bring Quiper up anyway, surface a banner
    // on the fullscreen window explaining how to get back.
    func showWebFullScreenBanner() {
        guard let fullScreenWindow = webFullScreenWindow, let contentView = fullScreenWindow.contentView else { return }
        removeWebFullScreenBanner()

        let pill = makeGlassPillBanner(
            iconName: "arrow.down.forward.and.arrow.up.backward",
            title: "Quiper is in fullscreen",
            caption: "Exit fullscreen to return to Quiper."
        )
        let banner = pill.view

        banner.frame = NSRect(
            x: (contentView.bounds.width - pill.size.width) / 2,
            y: contentView.bounds.height - pill.size.height - 24,
            width: pill.size.width,
            height: pill.size.height
        )
        banner.autoresizingMask = [.minYMargin, .minXMargin, .maxXMargin]

        contentView.addSubview(banner, positioned: .above, relativeTo: nil)
        webFullScreenBannerView = banner

        banner.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            banner.animator().alphaValue = 1
        }

        webFullScreenBannerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.webFullScreenBannerView === banner else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    banner.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        banner.removeFromSuperview()
                        if self.webFullScreenBannerView === banner {
                            self.webFullScreenBannerView = nil
                        }
                    }
                }
            }
        }
    }

    private func makeGlassPillBanner(iconName: String, title: String, caption: String) -> (view: PassthroughBannerView, size: NSSize) {
        let banner = PassthroughBannerView(frame: .zero)
        banner.wantsLayer = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        effect.layer?.borderWidth = 1

        let iconView = NSImageView()
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium)) {
            iconView.image = icon
        }
        iconView.contentTintColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, captionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let stack = NSStackView(views: [iconView, textStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10

        let horizontalPadding: CGFloat = 18
        let verticalPadding: CGFloat = 12
        let stackSize = stack.fittingSize
        let size = NSSize(
            width: stackSize.width + horizontalPadding * 2,
            height: max(52, stackSize.height + verticalPadding * 2)
        )
        effect.frame = NSRect(origin: .zero, size: size)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: horizontalPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -horizontalPadding),
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        banner.addSubview(effect)
        return (banner, size)
    }
    
    func removeWebFullScreenBanner() {
        webFullScreenBannerTimer?.invalidate()
        webFullScreenBannerTimer = nil
        webFullScreenBannerView?.removeFromSuperview()
        webFullScreenBannerView = nil
    }
    
    @objc private func handleShowSettings(_ notification: Notification) {
        collapsibleServiceSelector?.collapse()
        collapsibleSessionSelector?.collapse()
        updateHeaderVisibility(animated: true)
    }
    
    @objc private func handleCloseSettings(_ notification: Notification) {
        isHeaderHovered = isMouseInHeaderTrackingArea
        updateHeaderVisibility(animated: true)
        updateLockButtonToolTip()
    }

    private func updateLockButtonToolTip() {
        guard let lockBtn = manualLockButton as? HoverIconButton else { return }
        let lockShortcut = Settings.shared.appShortcutBindings.lockCurrentEngine
        lockBtn.tooltipText = "Lock Engine"
        lockBtn.tooltipShortcut = lockShortcut.isDisabled ? nil : ShortcutFormatter.string(for: lockShortcut)
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
        
        if let idx = services.firstIndex(where: { $0.id == currentServiceID }) {
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
        repositionVisibleHUDs()
    }

    func windowDidMove(_ notification: Notification) {
        repositionExpandedSelectors()
        repositionVisibleHUDs()
    }

    func repositionVisibleHUDs() {
        if let tabHW = tabHistoryHUDWindow, tabHW.isVisible {
            updateHUDWindowFrame()
        }
        if let phw = promptHistoryHUDWindow, phw.isVisible {
            alignHUDWindow(phw, width: 520, height: 480)
        }
        if let mhw = modifierHUDWindow, mhw.isVisible {
            alignHUDWindow(mhw, width: 492, height: 465)
        }
        if locationBarHUDWindow?.isVisible == true {
            alignLocationBarHUDWindow()
        }
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
        PreviousTabHotkeyManager.shared.register { [weak self] in
            self?.handleGraveKeyDown()
        } onReleaseForward: { [weak self] in
            self?.handleGraveKeyUp()
        } onPressBackward: { [weak self] in
            self?.handleGraveBackwardKeyDown()
        } onReleaseBackward: { [weak self] in
            self?.handleGraveKeyUp()
        }

        let settingsWindow = AppDelegate.sharedSettingsWindow
        if settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let updateWindow = UpdatePromptWindowController.shared.window, updateWindow.isVisible {
            updateWindow.makeKeyAndOrderFront(nil)
            return
        }

        raiseVisibleHUDs()

        let otherChildWindows = window?.childWindows?.filter {
            $0 != settingsWindow &&
            $0 != UpdatePromptWindowController.shared.window &&
            $0 != blurWindow
        } ?? []
        if !otherChildWindows.isEmpty {
            return
        }
        
        focusInputInActiveWebviewWithFallback()
        
        GhostOnboardingManager.shared.start(in: self)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Losing key status (e.g. a transient system input popup taking over)
        // strands the recent-tabs ring: the events that normally dismiss it
        // may never be delivered afterwards. Commit the gesture immediately.
        if isCyclingHistory {
            endHistoryCycling()
        }

        PreviousTabHotkeyManager.shared.unregister()
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
