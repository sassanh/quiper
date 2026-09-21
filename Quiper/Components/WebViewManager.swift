import AppKit
import WebKit
import Combine

@MainActor
protocol WebViewManagerDelegate: AnyObject {
    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView)
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView)
    func webViewDidUpdateFullscreenState(_ state: WKWebView.FullscreenState, for webView: WKWebView)
    func webViewDidFinishNavigation(_ webView: WKWebView)
    func engineDidUnlock(serviceID: UUID)
    func inputStateRequestSave()
    /// The user chose Suggest Selector in the webview context menu.
    /// `viewPoint` is in the webview's own coordinates at click time.
    func webViewDidRequestSelectorSuggest(_ webView: WKWebView, at viewPoint: NSPoint)
}

@MainActor
final class WebViewWrapperView: NSView {
    enum RenderMode: Equatable {
        case webContent
        case error
    }

    weak var interactiveOverlayView: NSView?
    private weak var managedWebView: WKWebView?
    private weak var errorView: WebLoadErrorView?

    private(set) var renderMode: RenderMode = .webContent {
        didSet { renderSurface() }
    }

    var isShowingError: Bool { renderMode == .error }

    func install(webView: WKWebView, errorView: WebLoadErrorView) {
        managedWebView = webView
        self.errorView = errorView
        renderSurface()
    }

    func showWebContent() {
        renderMode = .webContent
    }

    func showError(_ error: WebLoadError, retryAvailable: Bool) {
        errorView?.configure(error: error, retryAvailable: retryAvailable)
        renderMode = .error
    }

    func focusError() {
        errorView?.focus()
    }

    func detachSessionSurface() {
        errorView?.removeFromSuperview()
        managedWebView = nil
        errorView = nil
        renderMode = .webContent
    }

    private func renderSurface() {
        guard let managedWebView, let errorView else { return }

        let showsError = renderMode == .error
        managedWebView.isHidden = showsError
        errorView.setVisible(showsError)
        assert(managedWebView.isHidden != errorView.isHidden, "A session must render exactly one content surface.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinates (AppKit contract).
        // Convert to our own coordinates to test against the overlay's frame.
        if let overlay = interactiveOverlayView, !overlay.isHidden, overlay.superview === self {
            let pointInSelf: NSPoint
            if let parent = superview {
                pointInSelf = convert(point, from: parent)
            } else {
                // No superview (isolated unit test): assume the point is already local.
                pointInSelf = point
            }
            if overlay.frame.contains(pointInSelf),
               let hitView = overlay.hitTest(pointInSelf) {
                return hitView
            }
        }

        return super.hitTest(point)
    }
}

@MainActor
final class WebViewManager: NSObject {
    weak var delegate: WebViewManagerDelegate?

    /// Identity of one restorable popup: owning session plus normalized URL.
    /// Count-based (not boolean) so legit same-URL duplicates survive.
    private struct PopupOwnerURL: Hashable, Sendable {
        let serviceID: UUID
        let sessionIndex: Int
        let url: String
    }
    
    // Storage
    var webviewsByID: [UUID: [Int: WKWebView]] = [:]
    private var wrappersByID: [UUID: [Int: NSView]] = [:]
    private var serviceIDsByWebView: [ObjectIdentifier: UUID] = [:]
    // Session-owned popups: each popup webview maps to the tab that opened
    // it (or the owner inherited from a parent popup). The window registry
    // holds the windows until their close path unregisters them.
    private var popupOwnerByToken: [ObjectIdentifier: TabIdentifier] = [:]
    private var popupWindowsByToken: [ObjectIdentifier: ModalPopupWindow] = [:]
    private var popupCreationOrder: [ObjectIdentifier: Int] = [:]
    private var popupCreationCounter = 0
    private var popupFindBars: [ObjectIdentifier: FindBarViewController] = [:]
    // Intended URL (normalized) for restored popups whose load has not
    // committed yet: consulted by snapshot and dedup until the live URL
    // takes over. Cleared on commit, failure, or close.
    private var popupPendingURLByToken: [ObjectIdentifier: String] = [:]
    private var pendingLazyLoadURLs: [ObjectIdentifier: String] = [:]
    private var lastKnownTitlesByWebView: [ObjectIdentifier: String] = [:]
    private var activeRequestURLsByWebView: [ObjectIdentifier: URL] = [:]
    private var failedRequestURLsByWebView: [ObjectIdentifier: URL] = [:]
    private var processTerminationRetryStates: [ObjectIdentifier: WebProcessTerminationRetryState] = [:]
    private var activeDownloads: [Any] = []
    
    // State needed for logic
    private var services: [Service] = []
    private var zoomLevels: [UUID: CGFloat] = [:]
    private(set) var windowHasFocus = true
    
    // Dependencies
    private weak var containerView: NSView?
    private weak var dragArea: NSView? // for positioning below
    private var currentContentFrame: NSRect?
    
    // Test support
    private var navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var initialLoadAwaitingFocus = Set<ObjectIdentifier>()
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]
    private var tabInputStates: [UUID: [Int: TabInputState]] = [:]
    private var tabPromptHistories: [UUID: [Int: [PromptHistoryEntry]]] = [:]
    private var tabPromptHistoryEnabledOverrides: [UUID: [Int: Bool]] = [:]
    // MARK: - Temporary-state tracking
    // Hard-temporary state is owned entirely by Quiper: a tab is temporary
    // exactly when it runs on an isolated ephemeral store. Creation seeds the
    // flag; removal clears it. Page scripts never participate, and ephemeral
    // tabs receive no injected scripts or handlers, so websites cannot detect
    // Quiper through them.
    private var tabQuiperPrivateStores: [UUID: [Int: Bool]] = [:]
    private var approvedURLs = Set<URL>()
    private var cancellables = Set<AnyCancellable>()

    init(containerView: NSView) {
        self.containerView = containerView
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(webDataClearedNotification(_:)), name: .webDataCleared, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(promptHistoryLimitChangedNotification(_:)), name: .promptHistoryLimitChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(engineCustomCSSChangedNotification(_:)), name: .engineCustomCSSChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enginePromptSelectorChangedNotification(_:)), name: .enginePromptSelectorChanged, object: nil)
        Settings.shared.$enablePromptHistory
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllRecordingIndicators()
            }
            .store(in: &cancellables)
        Settings.shared.$promptRecordingIndicatorStyle
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllRecordingIndicators()
            }
            .store(in: &cancellables)
    }
    
    func updateServices(_ newServices: [Service]) {
        // Commit-only: engine deletes and encryption flips destroy live tabs,
        // so the callers that mutate settings (Settings delete/erase/migrate
        // flows) warn through TabCloseGate before reaching this.
        let incomingIDs = Set(newServices.map { $0.id })
        let existingIDs = Set(webviewsByID.keys)

        let removedIDs = existingIDs.subtracting(incomingIDs)
        for id in removedIDs {
            closePopups(forServiceID: id)
            if let removedWebviews = webviewsByID[id] {
                removedWebviews.values.forEach { tearDownWebView($0) }
            }
            webviewsByID.removeValue(forKey: id)
            wrappersByID.removeValue(forKey: id)
        }

        // Also check if any existing service has changed its encryption status
        // or engine type. Both change what a session loads: encryption swaps
        // the backing store, and the engine type swaps the session URLs, so
        // live webviews would otherwise keep serving stale addresses.
        for newService in newServices {
            if let existingWebviews = webviewsByID[newService.id] {
                if let oldService = self.services.first(where: { $0.id == newService.id }),
                   oldService.isEncrypted != newService.isEncrypted
                    || oldService.engineType != newService.engineType {
                    NSLog("[WebViewManager] Engine configuration changed for service %@. Tearing down existing webviews.", newService.name)
                    closePopups(forServiceID: newService.id)
                    existingWebviews.values.forEach { tearDownWebView($0) }
                    webviewsByID[newService.id] = [:]
                    wrappersByID[newService.id] = [:]
                }
            }
        }
        
        for service in newServices where webviewsByID[service.id] == nil {
            webviewsByID[service.id] = [:]
            wrappersByID[service.id] = [:]
        }
        
        self.services = newServices
        let incomingServiceIDs = Set(newServices.map { $0.id })

        for serviceID in tabInputStates.keys {
            if !incomingServiceIDs.contains(serviceID) {
                tabInputStates.removeValue(forKey: serviceID)
            }
        }
        for serviceID in tabPromptHistories.keys {
            if !incomingServiceIDs.contains(serviceID) {
                tabPromptHistories.removeValue(forKey: serviceID)
            }
        }
        for serviceID in tabPromptHistoryEnabledOverrides.keys {
            if !incomingServiceIDs.contains(serviceID) {
                tabPromptHistoryEnabledOverrides.removeValue(forKey: serviceID)
            }
        }
        for serviceID in tabQuiperPrivateStores.keys {
            if !incomingServiceIDs.contains(serviceID) {
                tabQuiperPrivateStores.removeValue(forKey: serviceID)
            }
        }
    }
    
    func updateZoomLevels(_ levels: [UUID: CGFloat]) {
        self.zoomLevels = levels
        for service in services {
            if let level = levels[service.id], let sessionMap = webviewsByID[service.id] {
                sessionMap.values.forEach { $0.pageZoom = level }
            }
        }
    }
    
    func applyZoom(_ level: CGFloat, for serviceID: UUID) {
        zoomLevels[serviceID] = level
        for service in services where service.id == serviceID {
            if let sessionMap = webviewsByID[service.id] {
                sessionMap.values.forEach { $0.pageZoom = level }
            }
        }
    }

    /// Single gate for engine stylesheet changes: rebuilds the creation-time
    /// user scripts so later navigations start with the current CSS, and
    /// pushes it into every live session by updating the tagged style
    /// element. Callers never care why it changed (user edit, Hide, template
    /// sync toggle): persisting posts `.engineCustomCSSChanged`, which lands
    /// here. Ephemeral tabs are skipped: their pages stay marker-free.
    func refreshCustomCSS(for serviceID: UUID) {
        guard let sessionMap = webviewsByID[serviceID] else { return }
        sessionMap.values.forEach { webView in
            syncEngineUserScripts(to: webView)
            applyCurrentCustomCSS(to: webView)
        }
    }

    /// Rebuilds the webview's creation-time user scripts with the current
    /// stylesheet and prompt selector. User scripts are captured at creation,
    /// so without this the next navigation replays stale CSS until `didFinish`
    /// patches the live page — the visible flash of unhidden elements.
    private func syncEngineUserScripts(to webView: WKWebView) {
        guard let (snapshotService, sessionIndex) = findServiceAndSession(for: webView),
              !isQuiperPrivateTab(serviceID: snapshotService.id, sessionIndex: sessionIndex),
              let service = Self.authoritativeService(for: snapshotService.id, snapshot: services)
        else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        Self.addEngineUserScripts(to: controller, service: service)
        notificationBridges[ObjectIdentifier(webView)]?.reinstall()
    }

    /// Single source for engine page scripts: the custom stylesheet plus the
    /// input tracking and context-menu scripts. Creation and CSS/selector
    /// refreshes both go through here so later navigations never replay stale
    /// content.
    private static func addEngineUserScripts(to controller: WKUserContentController, service: Service) {
        let cssToInject = Settings.shared.customCSS(for: service)
        if !cssToInject.isEmpty {
            let userScript = WKUserScript(source: WebScripts.makeCustomCSSInjectionScript(css: cssToInject), injectionTime: .atDocumentStart, forMainFrameOnly: false)
            controller.addUserScript(userScript)
        }

        // Inject input setter interceptor script at document start
        let startScript = WebScripts.makeValueSetterInterceptorScript()
        controller.addUserScript(startScript)

        // Inject input state tracking user script
        let inputScript = WebScripts.makeInputStateTrackerScript(
            selector: Settings.shared.promptInputSelector(for: service),
            initiallyActive: false
        )
        controller.addUserScript(inputScript)

        // Record right-click points for context-menu direct picking
        controller.addUserScript(WebScripts.makeContextMenuRecorderScript())
    }

    /// Pushes the webview's engine stylesheet into its live page. Idempotent:
    /// the tagged node is created or updated, never duplicated. Also runs on
    /// every finished navigation, since loads re-run the creation-time script
    /// with whatever CSS was current at webview creation.
    private func applyCurrentCustomCSS(to webView: WKWebView) {
        guard let (snapshotService, sessionIndex) = findServiceAndSession(for: webView),
              !isQuiperPrivateTab(serviceID: snapshotService.id, sessionIndex: sessionIndex),
              let service = Self.authoritativeService(for: snapshotService.id, snapshot: services)
        else { return }
        webView.evaluateJavaScript(
            WebScripts.makeCustomCSSInjectionScript(css: Settings.shared.customCSS(for: service)),
            completionHandler: nil
        )
    }

    /// Fresh settings record by ID, falling back to the snapshot. Manager
    /// snapshots lag Settings mutations (e.g. a template-synced engine going
    /// custom), and resolving CSS from stale flags pushes the wrong
    /// stylesheet — typically the bare template on the first change.
    static func authoritativeService(for serviceID: UUID, snapshot: [Service]) -> Service? {
        Settings.shared.services.first(where: { $0.id == serviceID })
            ?? snapshot.first(where: { $0.id == serviceID })
    }
    
    func getWebView(for service: Service, sessionIndex: Int) -> WKWebView? {
        webviewsByID[service.id]?[sessionIndex]
    }

    // Authoritative element-fullscreen signal: WebKit reports the fullscreen state
    // directly on the webview, so no window/space inference is involved.
    func webViewInFullScreen() -> WKWebView? {
        for sessionMap in webviewsByID.values {
            for webView in sessionMap.values {
                if webView.fullscreenState == .inFullscreen || webView.fullscreenState == .enteringFullscreen {
                    return webView
                }
            }
        }
        return nil
    }

    func sessionTitle(for service: Service, sessionIndex: Int) -> String? {
        guard let webView = getWebView(for: service, sessionIndex: sessionIndex) else { return nil }
        let token = ObjectIdentifier(webView)
        return Self.normalizedTitle(webView.title) ?? lastKnownTitlesByWebView[token]
    }
    
    func getOpenSessions(for service: Service) -> [(sessionIndex: Int, title: String)] {
        guard let sessionMap = webviewsByID[service.id] else { return [] }
        return sessionMap.map { (idx, _) in
            let displayTitle = sessionTitle(for: service, sessionIndex: idx) ?? "Session \(idx + 1)"
            return (sessionIndex: idx, title: displayTitle)
        }
        .sorted { $0.sessionIndex < $1.sessionIndex }
    }
    
    func removeWebView(for service: Service, sessionIndex: Int) {
        removeWebView(for: service.id, sessionIndex: sessionIndex)
    }

    /// Commit-only primitive behind `TabCloseGate` (`TabCloseGate.swift`):
    /// destroying a webview drops whatever page state it holds, so callers
    /// must confirm `beforeunload` through `requestCloseTabs` (or a
    /// pre-confirmed settings/quit flow) before reaching this.
    func removeWebView(for serviceID: UUID, sessionIndex: Int) {
        // Close owned popups first: the tab's popups must go even when the
        // webview itself is already gone (early return below).
        closePopups(for: TabIdentifier(serviceID: serviceID, sessionIndex: sessionIndex))
        guard let webView = webviewsByID[serviceID]?[sessionIndex] else { return }
        tearDownWebView(webView)
        webviewsByID[serviceID]?.removeValue(forKey: sessionIndex)
        wrappersByID[serviceID]?.removeValue(forKey: sessionIndex)
        tabInputStates[serviceID]?.removeValue(forKey: sessionIndex)
        tabPromptHistories[serviceID]?.removeValue(forKey: sessionIndex)
        tabPromptHistoryEnabledOverrides[serviceID]?.removeValue(forKey: sessionIndex)
        tabQuiperPrivateStores[serviceID]?.removeValue(forKey: sessionIndex)
    }

    func getOpenSessionTitlesState() -> [UUID: [Int: String]] {
        var state: [UUID: [Int: String]] = [:]

        for service in services {
            guard let sessionIndices = webviewsByID[service.id]?.keys else { continue }
            let titles = sessionIndices.reduce(into: [Int: String]()) { result, sessionIndex in
                // Temporary tabs never persist, so their titles stay out of saved state.
                guard !isTemporaryTab(serviceID: service.id, sessionIndex: sessionIndex) else { return }
                if let title = sessionTitle(for: service, sessionIndex: sessionIndex) {
                    result[sessionIndex] = title
                }
            }
            if !titles.isEmpty {
                state[service.id] = titles
            }
        }

        return state
    }

    func getOpenSessionsState() -> [UUID: [Int: String]] {
        var state: [UUID: [Int: String]] = [:]
        let currentSavedState = Settings.shared.persistedTabState?.openTabs

        for service in services {
            // Pinned-tab URLs live in the engine definition and never persist.
            guard !service.isPinnedTabs else { continue }
            guard let sessionMap = webviewsByID[service.id] else { continue }
            var sessionURLs: [Int: String] = [:]
            for (idx, webView) in sessionMap {
                // Temporary tabs never persist: no URL reaches disk.
                guard !isTemporaryTab(serviceID: service.id, sessionIndex: idx) else { continue }
                if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
                    sessionURLs[idx] = urlString
                } else if let previouslySavedURL = currentSavedState?[service.id]?[idx], !previouslySavedURL.isEmpty {
                    sessionURLs[idx] = previouslySavedURL
                } else {
                    sessionURLs[idx] = service.url
                }
            }
            if !sessionURLs.isEmpty {
                state[service.id] = sessionURLs
            }
        }
        return state
    }

    // MARK: - Temporary-state record
    //
    // A tab is temporary exactly when it runs on an isolated ephemeral store.
    // Creation seeds the flag; removal clears it. Nothing else writes it.

    /// Whether the tab is a hard-temporary ephemeral tab. Never persists.
    func isTemporaryTab(serviceID: UUID, sessionIndex: Int) -> Bool {
        isQuiperPrivateTab(serviceID: serviceID, sessionIndex: sessionIndex)
    }

    /// Whether the tab runs on an isolated ephemeral store created for
    /// hard-temporary use. Never flips in place by design.
    func isQuiperPrivateTab(serviceID: UUID, sessionIndex: Int) -> Bool {
        tabQuiperPrivateStores[serviceID]?[sessionIndex] ?? false
    }

    /// Seeds the creation flag. Normal tabs record false; ephemeral tabs true.
    private func seedTemporaryState(isQuiperPrivate: Bool, for serviceID: UUID, sessionIndex: Int) {
        if tabQuiperPrivateStores[serviceID] == nil {
            tabQuiperPrivateStores[serviceID] = [:]
        }
        tabQuiperPrivateStores[serviceID]?[sessionIndex] = isQuiperPrivate
    }

    func getOpenSessionsInputState() -> [UUID: [Int: TabInputState]] {
        // Temporary tabs never persist; keep their live input out of saved state.
        var filtered: [UUID: [Int: TabInputState]] = [:]
        for (serviceID, sessions) in tabInputStates {
            let kept = sessions.filter { !isTemporaryTab(serviceID: serviceID, sessionIndex: $0.key) }
            if !kept.isEmpty {
                filtered[serviceID] = kept
            }
        }
        return filtered
    }

    func getTabInputState(for serviceID: UUID, sessionIndex: Int) -> TabInputState? {
        return tabInputStates[serviceID]?[sessionIndex]
    }

    func setTabInputState(_ state: TabInputState, for serviceID: UUID, sessionIndex: Int) {
        if tabInputStates[serviceID] == nil {
            tabInputStates[serviceID] = [:]
        }
        tabInputStates[serviceID]?[sessionIndex] = state
    }

    func restoreTabInputStates(_ states: [UUID: [Int: TabInputState]]) {
        for (id, sessionMap) in states {
            if self.tabInputStates[id] == nil {
                self.tabInputStates[id] = [:]
            }
            for (idx, state) in sessionMap {
                self.tabInputStates[id]?[idx] = state
            }
        }
    }

    func getOpenSessionsPromptHistories() -> [UUID: [Int: [PromptHistoryEntry]]] {
        var filtered: [UUID: [Int: [PromptHistoryEntry]]] = [:]
        for (serviceID, sessions) in tabPromptHistories {
            let kept = sessions.filter { !isTemporaryTab(serviceID: serviceID, sessionIndex: $0.key) }
            if !kept.isEmpty {
                filtered[serviceID] = kept
            }
        }
        return filtered
    }

    func getOpenSessionsPromptHistoryOverrides() -> [UUID: [Int: Bool]] {
        var filtered: [UUID: [Int: Bool]] = [:]
        for (serviceID, sessions) in tabPromptHistoryEnabledOverrides {
            let kept = sessions.filter { !isTemporaryTab(serviceID: serviceID, sessionIndex: $0.key) }
            if !kept.isEmpty {
                filtered[serviceID] = kept
            }
        }
        return filtered
    }

    func restoreTabPromptHistories(_ states: [UUID: [Int: [PromptHistoryEntry]]]) {
        for (id, sessionMap) in states {
            if self.tabPromptHistories[id] == nil {
                self.tabPromptHistories[id] = [:]
            }
            for (idx, history) in sessionMap {
                self.tabPromptHistories[id]?[idx] = Self.trimmedPromptHistory(history)
            }
        }
    }

    func restoreTabPromptHistoryOverrides(_ states: [UUID: [Int: Bool]]) {
        for (id, sessionMap) in states {
            if self.tabPromptHistoryEnabledOverrides[id] == nil {
                self.tabPromptHistoryEnabledOverrides[id] = [:]
            }
            for (idx, override) in sessionMap {
                self.tabPromptHistoryEnabledOverrides[id]?[idx] = override
            }
        }
    }

    func getPromptHistory(for serviceID: UUID, sessionIndex: Int) -> [PromptHistoryEntry] {
        return tabPromptHistories[serviceID]?[sessionIndex] ?? []
    }

    func addPromptHistoryEntry(_ entry: PromptHistoryEntry, for serviceID: UUID, sessionIndex: Int) {
        if tabPromptHistories[serviceID] == nil {
            tabPromptHistories[serviceID] = [:]
        }
        if tabPromptHistories[serviceID]?[sessionIndex] == nil {
            tabPromptHistories[serviceID]?[sessionIndex] = []
        }
        
        tabPromptHistories[serviceID]?[sessionIndex]?.removeAll(where: { $0.text == entry.text })
        
        tabPromptHistories[serviceID]?[sessionIndex]?.append(entry)
        trimPromptHistory(for: serviceID, sessionIndex: sessionIndex)
    }

    private static func trimmedPromptHistory(_ history: [PromptHistoryEntry]) -> [PromptHistoryEntry] {
        let limit = Settings.clampedPromptHistoryLimit(Settings.shared.promptHistoryLimit)
        guard history.count > limit else { return history }
        return Array(history.suffix(limit))
    }

    private func trimPromptHistory(for serviceID: UUID, sessionIndex: Int) {
        guard let history = tabPromptHistories[serviceID]?[sessionIndex] else { return }
        tabPromptHistories[serviceID]?[sessionIndex] = Self.trimmedPromptHistory(history)
    }

    private func trimAllPromptHistories() {
        for serviceID in tabPromptHistories.keys {
            guard let sessionMap = tabPromptHistories[serviceID] else { continue }
            for sessionIndex in sessionMap.keys {
                trimPromptHistory(for: serviceID, sessionIndex: sessionIndex)
            }
        }
    }

    func clearPromptHistory(for serviceID: UUID, sessionIndex: Int) {
        tabPromptHistories[serviceID]?.removeValue(forKey: sessionIndex)
    }

    func deletePromptHistoryEntry(_ entry: PromptHistoryEntry, for serviceID: UUID, sessionIndex: Int) {
        guard var history = tabPromptHistories[serviceID]?[sessionIndex] else { return }
        if let idx = history.firstIndex(of: entry) {
            history.remove(at: idx)
            tabPromptHistories[serviceID]?[sessionIndex] = history
        }
    }

    func isPromptHistoryEnabled(for serviceID: UUID, sessionIndex: Int) -> Bool {
        guard Settings.shared.enablePromptHistory else {
            return false
        }
        if let override = tabPromptHistoryEnabledOverrides[serviceID]?[sessionIndex] {
            return override
        }
        return true
    }

    func setPromptHistoryEnabled(_ enabled: Bool, for serviceID: UUID, sessionIndex: Int) {
        if tabPromptHistoryEnabledOverrides[serviceID] == nil {
            tabPromptHistoryEnabledOverrides[serviceID] = [:]
        }
        tabPromptHistoryEnabledOverrides[serviceID]?[sessionIndex] = enabled
        if let service = services.first(where: { $0.id == serviceID }),
           let webView = webviewsByID[service.id]?[sessionIndex] {
            pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
        }
    }

    /// Whether the composer should show the recording indicator for this session.
    func shouldShowRecordingIndicator(for service: Service, sessionIndex: Int) -> Bool {
        Settings.shared.promptRecordingIndicatorStyle != .off
            && service.preservePrompt
            && isPromptHistoryEnabled(for: service.id, sessionIndex: sessionIndex)
    }

    func pushRecordingIndicatorState(to webView: WKWebView) {
        guard let (service, sessionIndex) = findServiceAndSession(for: webView),
              !isQuiperPrivateTab(serviceID: service.id, sessionIndex: sessionIndex) else { return }
        pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
    }

    func pushRecordingIndicatorState(to webView: WKWebView, service: Service, sessionIndex: Int) {
        guard !isQuiperPrivateTab(serviceID: service.id, sessionIndex: sessionIndex) else { return }
        applyRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
        // Re-evaluate rather than replaying stale state if visibility/settings change during the delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.applyRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
        }
    }

    private func applyRecordingIndicatorState(to webView: WKWebView, service: Service, sessionIndex: Int) {
        let isVisible = webView.superview?.isHidden == false
        let enabled = isVisible && shouldShowRecordingIndicator(for: service, sessionIndex: sessionIndex)
        let style: String
        switch Settings.shared.promptRecordingIndicatorStyle {
        case .glow:
            style = "glow"
        case .dashed:
            style = "dashed"
        case .off:
            style = "off"
        }
        let focusValue = windowHasFocus ? "true" : "false"
        let js = """
        window.__quiperRecordingIndicatorStyle = "\(style)";
        window.__quiperRecordingEnabled = \(enabled ? "true" : "false");
        document.documentElement.dataset.quiperFocus = "\(focusValue)";
        if (typeof window.__quiperUpdateRecordingIndicator === 'function') {
            window.__quiperUpdateRecordingIndicator();
        } else {
            // Script not ready yet (document still loading); retry shortly.
            setTimeout(function() {
                if (typeof window.__quiperUpdateRecordingIndicator === 'function') {
                    window.__quiperUpdateRecordingIndicator();
                }
            }, 400);
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Makes web content see-through when the focus-loss effect is active,
    /// so focus loss reads through the page itself. Clicks are still caught
    /// by the focus shield above the wrappers, never by the page.
    private var lastContentTransparent = false
    func setContentTransparent(_ transparent: Bool) {
        guard lastContentTransparent != transparent else { return }
        lastContentTransparent = transparent
        let alpha: CGFloat = transparent ? 0.5 : 1.0
        for wrapperMap in wrappersByID.values {
            for wrapper in wrapperMap.values {
                wrapper.alphaValue = alpha
            }
        }
    }

    /// Pushes window focus to every managed webview so the composer recording
    /// indicator can hide its animations while unfocused. Ephemeral tabs are
    /// skipped: they carry no Quiper markers and must stay marker-free.
    func setWindowHasFocus(_ focused: Bool) {
        guard windowHasFocus != focused else { return }
        windowHasFocus = focused
        // Re-evaluate indicator visibility against the new focus state.
        // applyRecordingIndicatorState stamps the dataset, covering pages
        // whose document was replaced since the last push.
        refreshAllRecordingIndicators()
    }

    func refreshAllRecordingIndicators() {
        for service in services {
            guard let sessions = webviewsByID[service.id] else { continue }
            for (sessionIndex, webView) in sessions {
                pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
            }
        }
    }

    func didReceiveInputTrackerReadyMessage(_ message: WKScriptMessage) {
        guard message.name == "quiperInputTrackerReady",
              message.frameInfo.isMainFrame,
              let webView = message.webView,
              let (service, sessionIndex) = findServiceAndSession(for: webView) else {
            return
        }

        let isActive = webView.superview?.isHidden == false
        webView.evaluateJavaScript(
            "window.__quiperInputTrackerActive = \(isActive ? "true" : "false");",
            completionHandler: nil
        )
        pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
    }

    func didReceiveInputStateMessage(_ message: WKScriptMessage) {
        NSLog("[Quiper] didReceiveInputStateMessage: name=\(message.name)")
        guard message.name == "quiperInputState" else {
            NSLog("[Quiper] [Error] message name mismatch: \(message.name)")
            return
        }
        
        guard let payload = message.body as? [String: Any] else {
            NSLog("[Quiper] [Error] message body is not a dictionary: \(String(describing: message.body))")
            return
        }

        let parsed = InputStatePayload(payload)

        NSLog("[Quiper] [Payload] Received input state payload: textLength=\(parsed.text.count), wasSent=\(parsed.wasSent), sentTextLength=\(parsed.wasSentText.count), clearType=\(parsed.clearType)")

        guard let webView = message.webView,
              let (service, sessionIndex) = findServiceAndSession(for: webView) else {
            NSLog("[Quiper] [Error] webView or service/sessionIndex not found in mapping")
            return
        }

        NSLog("[Quiper] [State] Target service: \(service.name), sessionIndex: \(sessionIndex), preservePrompt: \(service.preservePrompt)")

        guard service.preservePrompt else {
            return
        }

        if parsed.wasSent {
            let clearType = parsed.clearType
            var shouldRecord = false
            if clearType == "submit" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSubmit
            } else if clearType == "cmdBackspace" {
                shouldRecord = Settings.shared.promptHistoryRecordOnCmdBackspace
            } else if clearType == "selectionClear" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSelectionClear
            }

            NSLog("[Quiper] [History] wasSent is true. Text length: \(parsed.wasSentText.count), clearType: \(clearType), shouldRecord: \(shouldRecord)")

            if shouldRecord {
                let trimmedCount = parsed.wasSentText.trimmingCharacters(in: .whitespacesAndNewlines).count
                if let newEntry = PromptHistoryPolicy.makeEntryIfEligible(submittedText: parsed.wasSentText),
                   isPromptHistoryEnabled(for: service.id, sessionIndex: sessionIndex) {
                    addPromptHistoryEntry(newEntry, for: service.id, sessionIndex: sessionIndex)
                    acknowledgePromptSaved(in: webView, service: service, sessionIndex: sessionIndex)
                    NSLog("[Quiper] [History] Successfully added entry to session \(sessionIndex) prompt history")
                    self.delegate?.inputStateRequestSave()
                } else {
                    NSLog("[Quiper] [History] Entry ignored. Trimmed length: \(trimmedCount), enabled: \(isPromptHistoryEnabled(for: service.id, sessionIndex: sessionIndex))")
                }
            }
        }

        let inputState = TabInputState(text: parsed.text, isContentEditable: parsed.isContentEditable, start: parsed.start, end: parsed.end)
        setTabInputState(inputState, for: service.id, sessionIndex: sessionIndex)

        if parsed.wasSent {
            self.delegate?.inputStateRequestSave()
        }
    }

    private func acknowledgePromptSaved(in webView: WKWebView, service: Service, sessionIndex: Int) {
        guard shouldShowRecordingIndicator(for: service, sessionIndex: sessionIndex) else {
            return
        }
        webView.evaluateJavaScript(
            """
            if (typeof window.__quiperAcknowledgePromptSaved === 'function') {
                window.__quiperAcknowledgePromptSaved();
            }
            """,
            completionHandler: nil
        )
    }

    func findServiceAndSession(for webView: WKWebView) -> (Service, Int)? {
        for service in services {
            if let map = webviewsByID[service.id] {
                for (idx, wv) in map {
                    if wv == webView {
                        return (service, idx)
                    }
                }
            }
        }
        return nil
    }
    
    #if DEBUG
    func mockReceiveInputStateMessage(payload: [String: Any], service: Service, sessionIndex: Int) {
        let parsed = InputStatePayload(payload)

        guard service.preservePrompt else {
            return
        }

        if parsed.wasSent {
            let clearType = parsed.clearType
            var shouldRecord = false
            if clearType == "submit" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSubmit
            } else if clearType == "cmdBackspace" {
                shouldRecord = Settings.shared.promptHistoryRecordOnCmdBackspace
            } else if clearType == "selectionClear" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSelectionClear
            }

            if shouldRecord {
                if let newEntry = PromptHistoryPolicy.makeEntryIfEligible(submittedText: parsed.wasSentText),
                   isPromptHistoryEnabled(for: service.id, sessionIndex: sessionIndex) {
                    addPromptHistoryEntry(newEntry, for: service.id, sessionIndex: sessionIndex)
                }
            }
        }

        let inputState = TabInputState(text: parsed.text, isContentEditable: parsed.isContentEditable, start: parsed.start, end: parsed.end)
        setTabInputState(inputState, for: service.id, sessionIndex: sessionIndex)
    }
    #endif

    @objc private func promptHistoryLimitChangedNotification(_ notification: Notification) {
        trimAllPromptHistories()
    }

    @objc private func engineCustomCSSChangedNotification(_ notification: Notification) {
        guard let serviceID = notification.object as? UUID else { return }
        refreshCustomCSS(for: serviceID)
    }

    /// Prompt selector edits take effect on the next navigation, never the
    /// live page: unlike CSS there is no live patch, and unlike iOS there is
    /// no reload, since reloading would drop form and scroll state. Focus
    /// paths already resolve the fresh selector, so only the background input
    /// tracker lags until navigation.
    @objc private func enginePromptSelectorChangedNotification(_ notification: Notification) {
        guard let serviceID = notification.object as? UUID,
              let sessionMap = webviewsByID[serviceID] else { return }
        sessionMap.values.forEach(syncEngineUserScripts(to:))
    }

    
    private func resolvedService(for service: Service) -> Service {
        Settings.shared.services.first(where: { $0.id == service.id }) ?? service
    }

    func getOrCreateWebView(for inputService: Service, sessionIndex: Int, dragArea: NSView?, targetURL: String? = nil, restoredTitle: String? = nil, loadImmediately: Bool = true, isQuiperPrivate: Bool = false) -> WKWebView {
        let service = resolvedService(for: inputService)
        if let dragArea = dragArea {
            self.dragArea = dragArea
        }
        
        if let existing = webviewsByID[service.id]?[sessionIndex] {
            retainTitle(restoredTitle, for: existing)
            return existing
        }
        
        guard let contentView = containerView else {
            fatalError("WebViewManager containerView is nil")
        }
        
        // Calculate frame - use current content frame if available (e.g. border expansion active)
        let frame: NSRect
        if let contentFrame = currentContentFrame {
            frame = contentFrame
        } else {
            let isHeaderHidden = Settings.shared.topBarVisibility == .hidden
            let dragHeight = isHeaderHidden ? 0 : (self.dragArea?.bounds.height ?? 0)
            let availableHeight = contentView.bounds.height - dragHeight
            let isBottom = Settings.shared.dragAreaPosition == .bottom
            frame = NSRect(
                x: 0,
                y: isBottom ? dragHeight : 0,
                width: contentView.bounds.width,
                height: availableHeight
            )
        }
        
        // Wrapper View (Holds WebView + Docked Inspector)
        let wrapperView = WebViewWrapperView(frame: frame)
        wrapperView.autoresizingMask = []
        wrapperView.wantsLayer = true
        wrapperView.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        updateMaskedCorners(for: wrapperView)
        wrapperView.layer?.masksToBounds = true
        wrapperView.isHidden = true
        
        let isUnlocked = !service.isEncrypted || EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        
        // WebView inside Wrapper (ephemeral/non-persistent if locked, persistent if unlocked).
        // Quiper-private temporary tabs always use an isolated ephemeral store
        // and seed the temporary assumption; they never flip in place.
        let webview = createWebViewInstance(
            for: service,
            sessionIndex: sessionIndex,
            bounds: wrapperView.bounds,
            isPersistent: isUnlocked && !isQuiperPrivate,
            isQuiperPrivate: isQuiperPrivate
        )
        wrapperView.addSubview(webview)
        installErrorView(for: webview, in: wrapperView)

        // Add Wrapper to Container
        if let dragArea = self.dragArea {
            contentView.addSubview(wrapperView, positioned: .below, relativeTo: dragArea)
        } else {
            contentView.addSubview(wrapperView)
        }
        
        if webviewsByID[service.id] == nil {
            webviewsByID[service.id] = [:]
        }
        webviewsByID[service.id]?[sessionIndex] = webview
        
        if wrappersByID[service.id] == nil {
            wrappersByID[service.id] = [:]
        }
        wrappersByID[service.id]?[sessionIndex] = wrapperView
        
        serviceIDsByWebView[ObjectIdentifier(webview)] = service.id
        seedTemporaryState(isQuiperPrivate: isQuiperPrivate, for: service.id, sessionIndex: sessionIndex)
        
        let token = ObjectIdentifier(webview)
        retainTitle(restoredTitle, for: webview)
        initialLoadAwaitingFocus.insert(token)
        
        // Clean up any existing LockOverlayView from previous states
        for subview in wrapperView.subviews {
            if subview is LockOverlayView {
                subview.removeFromSuperview()
            }
        }
        
        // Ephemeral tabs must not identify Quiper: our referral never loads.
        // Pinned-tab engines always resolve the session's pinned URL from the
        // engine definition; saved or passed-in addresses are never trusted.
        let pinnedURLString = service.pinnedURL(for: sessionIndex)
        let requestedURLString: String
        if service.isPinnedTabs {
            let pinned = pinnedURLString ?? ""
            requestedURLString = isQuiperPrivate
                ? DefaultEngineDefinitions.urlStringWithoutQuiperReferral(pinned)
                : pinned
        } else {
            requestedURLString = isQuiperPrivate
                ? DefaultEngineDefinitions.urlStringWithoutQuiperReferral(targetURL ?? service.url)
                : (targetURL ?? service.url)
        }

        // Load initial URL with encryption check
        if service.isEncrypted {
            if EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                if loadImmediately {
                    let activeURLString = requestedURLString
                    if let url = URL(string: activeURLString) {
                        if url.isFileURL {
                            webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                        } else {
                            webview.load(URLRequest(url: url))
                        }
                    } else {
                        showLoadError(WebLoadError(kind: .invalidURL), for: webview)
                    }
                } else {
                    pendingLazyLoadURLs[token] = requestedURLString
                }
            } else {
                // Show LockOverlayView on top of wrapper
                let serviceId = service.id
                let requestedURL = targetURL
                
                var lockOverlayRef: LockOverlayView? = nil
                let lockOverlay = LockOverlayView(frame: wrapperView.bounds, serviceName: service.name) { [weak self, weak webview, weak wrapperView] context in
                    NSLog("[LockOverlay] onUnlock closure entered")
                    guard let self = self else {
                        NSLog("[LockOverlay] self (WebViewManager) is nil, aborting")
                        return
                    }
                    guard let webview = webview else {
                        NSLog("[LockOverlay] webview is nil, aborting")
                        return
                    }
                    guard let wrapperView = wrapperView else {
                        NSLog("[LockOverlay] wrapperView is nil, aborting")
                        return
                    }
                    
                    guard let overlay = lockOverlayRef else { return }
                    
                    overlay.startLoading()
                    
                    NSLog("[LockOverlay] All references valid, starting Task")
                    Task { @MainActor in
                        do {
                            overlay.updateStatus("Authenticating...")
                            NSLog("[LockOverlay] Retrieving key from Keychain for service %@", serviceId.uuidString)
                            let key = try await SecureStorageManager.shared.retrieveKeyFromKeychain(for: serviceId, context: context)
                            NSLog("[LockOverlay] Key retrieved successfully")
                            
                            overlay.updateStatus("Mounting encrypted volume...")
                            if !EncryptedVolumeManager.shared.bundleExists(for: serviceId) {
                                NSLog("[LockOverlay] Creating new volume")
                                try await EncryptedVolumeManager.shared.createVolume(for: serviceId, passphrase: key)
                            }
                            NSLog("[LockOverlay] Mounting volume")
                            try await EncryptedVolumeManager.shared.mountVolume(for: serviceId, passphrase: key)
                            
                            // Metadata migration: move engine metadata from settings into secure bundle
                            if let currentService = Settings.shared.services.first(where: { $0.id == serviceId }),
                               EngineMetadataMigrationManager.shared.hasLegacyMetadata(for: currentService) {
                                overlay.updateStatus("Migrating engine metadata...")
                                do {
                                    try await EngineMetadataMigrationManager.shared.migrateMetadata(for: serviceId, context: context)
                                } catch {
                                    NSLog("[MetadataMigration] Migration failed for %@: %@", serviceId.uuidString, error.localizedDescription)
                                }
                            }
                            
                            // Refresh the authoritative service model before creating the
                            // persistent webview. The locked webview captured a pre-unlock
                            // Service value, which intentionally omits migrated metadata.
                            let unlockedService = try EngineMetadataMigrationManager.shared.loadMetadataForUnlockedService(serviceId)
                            self.updateServices(Settings.shared.services)
                            
                            overlay.updateStatus("Loading secure session...")
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            
                            // Remove non-persistent webview and clean observers
                            webview.removeObserver(self, forKeyPath: "title")
                            webview.removeObserver(self, forKeyPath: "loading")
                            webview.removeObserver(self, forKeyPath: "fullscreenState")
                            let oldToken = ObjectIdentifier(webview)
                            self.initialLoadAwaitingFocus.remove(oldToken)
                            self.serviceIDsByWebView.removeValue(forKey: oldToken)
                            wrapperView.detachSessionSurface()
                            self.removeLoadState(for: oldToken)
                            webview.configuration.userContentController.removeAllUserScripts()
                            webview.removeFromSuperview()
                            
                            // Remove lock overlay
                            for subview in wrapperView.subviews {
                                if subview is LockOverlayView {
                                    subview.removeFromSuperview()
                                }
                            }
                            
                            // Create the real persistent webview
                            let realWebView = self.createWebViewInstance(for: unlockedService, sessionIndex: sessionIndex, bounds: wrapperView.bounds, isPersistent: true)
                            wrapperView.addSubview(realWebView)
                            self.installErrorView(for: realWebView, in: wrapperView)
                            
                            // Update maps
                            self.webviewsByID[unlockedService.id]?[sessionIndex] = realWebView
                            self.serviceIDsByWebView[ObjectIdentifier(realWebView)] = unlockedService.id
                            self.seedTemporaryState(isQuiperPrivate: false, for: unlockedService.id, sessionIndex: sessionIndex)
                            
                            // Load real URL
                            var targetURLString: String
                            if unlockedService.isPinnedTabs {
                                targetURLString = unlockedService.pinnedURL(for: sessionIndex) ?? ""
                            } else {
                                targetURLString = requestedURL ?? unlockedService.url
                            }
                            if Settings.shared.tabSurvivalPolicy != .never {
                                let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceId).appendingPathComponent("quiper_tabs.json")
                                if let data = try? Data(contentsOf: stateURL),
                                   let state = try? JSONDecoder().decode(MainWindowController.SecureTabState.self, from: data) {
                                    // Pinned-tab URLs come from the engine
                                    // definition; saved addresses never win.
                                    if !unlockedService.isPinnedTabs, let saved = state.openTabs[sessionIndex] {
                                        targetURLString = saved
                                    }
                                    if let secureInputs = state.tabInputs {
                                        self.restoreTabInputStates([unlockedService.id: secureInputs])
                                    }
                                    if let secureHistories = state.tabPromptHistories {
                                        self.restoreTabPromptHistories([unlockedService.id: secureHistories])
                                    }
                                    if let secureOverrides = state.tabPromptHistoryEnabledOverrides {
                                        self.restoreTabPromptHistoryOverrides([unlockedService.id: secureOverrides])
                                    }
                                }
                            }
                            
                            if let url = URL(string: targetURLString) {
                                NSLog("[LockOverlay] Loading URL: %@", targetURLString)
                                if url.isFileURL {
                                    realWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                                } else {
                                    realWebView.load(URLRequest(url: url))
                                }
                            } else {
                                self.showLoadError(WebLoadError(kind: .invalidURL), for: realWebView)
                            }
                            
                            overlay.stopLoading()
                            
                            NSLog("[LockOverlay] Unlock complete")
                            self.delegate?.engineDidUnlock(serviceID: serviceId)
                        } catch {
                            NSLog("[LockOverlay] Error: %@", error.localizedDescription)
                            let errString = error.localizedDescription
                            if errString.contains("Canceled") || errString.contains("cancel") || errString.contains("denied") {
                                // User cancelled biometric prompt
                                overlay.stopLoading()
                                return
                            }
                            
                            overlay.showError(error.localizedDescription)
                        }
                    }
                }
                lockOverlayRef = lockOverlay
                wrapperView.addSubview(lockOverlay)
            }
        } else {
            // Unencrypted path: clear any leftover symlinks
            let fileManager = FileManager.default
            if let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                let targetLinkURL = libraryURL
                    .appendingPathComponent("WebKit")
                    .appendingPathComponent("WebsiteData")
                    .appendingPathComponent("Custom")
                    .appendingPathComponent(service.id.uuidString)
                
                if fileManager.fileExists(atPath: targetLinkURL.path) {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: targetLinkURL.path, isDirectory: &isDir) {
                        let attrs = try? fileManager.attributesOfItem(atPath: targetLinkURL.path)
                        if attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
                            try? fileManager.removeItem(at: targetLinkURL)
                        }
                    }
                }
            }
            
            if loadImmediately {
                let activeURLString = requestedURLString
                if let url = URL(string: activeURLString) {
                    if url.isFileURL {
                        webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                    } else {
                        webview.load(URLRequest(url: url))
                    }
                } else {
                    showLoadError(WebLoadError(kind: .invalidURL), for: webview)
                }
            } else {
                pendingLazyLoadURLs[token] = requestedURLString
            }
        }
        
        return webview
    }
    
    private func createWebViewInstance(for service: Service, sessionIndex: Int, bounds: NSRect, isPersistent: Bool, isQuiperPrivate: Bool = false) -> WKWebView {
        let userContentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let isRunningTests = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
        if isPersistent && !isRunningTests {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }

        if !isQuiperPrivate {
            Self.addEngineUserScripts(to: userContentController, service: service)

            let inputHandler = InputStateScriptMessageHandler(manager: self)
            userContentController.add(inputHandler, name: "quiperInputState")
            userContentController.add(inputHandler, name: "quiperInputTrackerReady")
        }
        NSLog(
            "[Quiper][Temporary] webview created for %@ session %d with %d scripts (private=%d)",
            service.name,
            sessionIndex,
            userContentController.userScripts.count,
            isQuiperPrivate ? 1 : 0
        )

        let webview = ContextMenuWebView(frame: bounds, configuration: config)
        webview.setValue(false, forKey: "drawsBackground")
        webview.autoresizingMask = [.width, .height]
        webview.uiDelegate = self
        webview.navigationDelegate = self
        webview.contextMenuDelegate = self
        webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webview.pageZoom = zoomLevels[service.id] ?? 1.0
        
        // Ephemeral tabs get no notification bridge either: any page-visible
        // handler name lets websites detect Quiper.
        if !isQuiperPrivate {
            attachNotificationBridge(to: webview, service: service, sessionIndex: sessionIndex)
        }
        
        // Add observers
        webview.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        webview.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
        webview.addObserver(self, forKeyPath: "fullscreenState", options: .new, context: nil)
        
        return webview
    }

    private func installErrorView(for webView: WKWebView, in wrapper: WebViewWrapperView) {
        let errorView = WebLoadErrorView(frame: wrapper.bounds)
        errorView.autoresizingMask = [.width, .height]
        errorView.onRetry = { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.retryFailedNavigation(for: webView)
        }
        wrapper.addSubview(errorView, positioned: .above, relativeTo: nil)
        wrapper.install(webView: webView, errorView: errorView)
    }

    private func beginMainFrameNavigation(_ webView: WKWebView, to url: URL) {
        let token = ObjectIdentifier(webView)
        let wrapper = webView.superview as? WebViewWrapperView
        let errorHadFocus = wrapper?.isShowingError == true && wrapper?.isHidden == false
        failedRequestURLsByWebView.removeValue(forKey: token)
        wrapper?.showWebContent()
        activeRequestURLsByWebView[token] = url
        if errorHadFocus {
            webView.window?.makeFirstResponder(webView)
        }
    }

    private func showLoadError(_ error: WebLoadError, for webView: WKWebView, fallbackURL: URL? = nil) {
        let token = ObjectIdentifier(webView)
        if let url = error.url ?? fallbackURL ?? activeRequestURLsByWebView[token] {
            failedRequestURLsByWebView[token] = url
        }
        let wrapper = webView.superview as? WebViewWrapperView
        wrapper?.showError(error, retryAvailable: failedRequestURLsByWebView[token] != nil)
        if wrapper?.isHidden == false {
            wrapper?.focusError()
        }
    }

    private func clearLoadError(for webView: WKWebView) {
        let token = ObjectIdentifier(webView)
        failedRequestURLsByWebView.removeValue(forKey: token)
        (webView.superview as? WebViewWrapperView)?.showWebContent()
    }

    private func handleNavigationFailure(_ error: Error, for webView: WKWebView) {
        guard !WebLoadError.isCancellation(error),
              !WebLoadError.isFrameLoadInterrupted(error) else { return }

        let nsError = error as NSError
        NSLog("[Quiper] Page load failed: domain=%@ code=%d url=%@",
              nsError.domain,
              nsError.code,
              (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? "nil")

        let token = ObjectIdentifier(webView)
        let loadError = WebLoadError(error: error, fallbackURL: activeRequestURLsByWebView[token])
        showLoadError(loadError, for: webView)
    }

    private func retryFailedNavigation(for webView: WKWebView) {
        let token = ObjectIdentifier(webView)
        guard let url = failedRequestURLsByWebView[token] else { return }

        load(url, in: webView)
    }

    /// Performs a fresh main-frame load of `url` in `webView`, resetting any
    /// visible load-error state first. All programmatic navigations must go
    /// through here so the error-view bookkeeping stays in one place.
    func load(_ url: URL, in webView: WKWebView) {
        beginMainFrameNavigation(webView, to: url)
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func stopLoading(_ webView: WKWebView) {
        webView.stopLoading()
    }

    func hasVisibleLoadError(for webView: WKWebView) -> Bool {
        (webView.superview as? WebViewWrapperView)?.isShowingError == true
    }

    func focusLoadError(for webView: WKWebView) {
        (webView.superview as? WebViewWrapperView)?.focusError()
    }

    func hideAll() {
        webviewsByID.values.forEach { sessionMap in
            sessionMap.values.forEach { webView in
                if let wrapper = webView.superview {
                    wrapper.isHidden = true
                    webView.evaluateJavaScript(
                        """
                        window.__quiperInputTrackerActive = false;
                        window.__quiperRecordingEnabled = false;
                        if (typeof window.__quiperUpdateRecordingIndicator === 'function') {
                            window.__quiperUpdateRecordingIndicator();
                        }
                        """,
                        completionHandler: nil
                    )
                }
            }
        }
    }
    

    /// Sets the unified inner content frame (cached for future session switches) and resizes all wrapper views.
    func setContentFrame(_ rect: NSRect, animated: Bool = false) {
        currentContentFrame = rect
        updateLayout(animated: animated)
    }
    
    /// Updates the layout of all webview wrapper frames.
    /// Uses the cached `currentContentFrame` if set, otherwise falls back to a calculated container-bounds frame.
    func updateLayout(animated: Bool = false) {
        guard let container = containerView else { return }
        
        let frame: NSRect
        if let savedFrame = currentContentFrame {
            frame = savedFrame
        } else {
            assertionFailure("[WebViewManager] updateLayout called before setContentFrame was initialized.")
            let isHeaderHidden = Settings.shared.topBarVisibility == .hidden
            let dragHeight = isHeaderHidden ? 0 : (self.dragArea?.bounds.height ?? 0)
            let availableHeight = container.bounds.height - dragHeight
            
            if Settings.shared.dragAreaPosition == .top {
                frame = NSRect(
                    x: 0,
                    y: 0,
                    width: container.bounds.width,
                    height: availableHeight
                )
            } else {
                frame = NSRect(
                    x: 0,
                    y: dragHeight,
                    width: container.bounds.width,
                    height: availableHeight
                )
            }
        }
        
        for sessionMap in webviewsByID.values {
            for webView in sessionMap.values {
                if let wrapper = webView.superview {
                    // Ensure no autoresizing conflicts with manual layout
                    wrapper.autoresizingMask = []
                    if animated {
                        wrapper.animator().frame = frame
                    } else {
                        wrapper.frame = frame
                    }
                    updateMaskedCorners(for: wrapper)
                    // After element-fullscreen, WebKit leaves the webView sized to
                    // the fullscreen window. The wrapper itself is already the
                    // correct (small) size, so autoresizing does not fire and the
                    // web process keeps a fullscreen viewport (innerWidth stays at
                    // screen width, media queries stay desktop). Force the webView
                    // back to the wrapper bounds so the viewport recomputes.
                    if webView.frame != wrapper.bounds {
                        webView.frame = wrapper.bounds
                    }
                }
            }
        }
        // Wrappers whose webView is currently hosted in the WebKit fullscreen
        // window have no superview link at this moment; ensure the wrapper
        // itself is still at the correct size so the webView has a correct
        // target to be restored into on didExit.
        for wrapperMap in wrappersByID.values {
            for wrapper in wrapperMap.values {
                if wrapper.superview != nil, wrapper.frame != frame {
                    wrapper.frame = frame
                    updateMaskedCorners(for: wrapper)
                }
            }
        }
    }
    
    private func updateMaskedCorners(for wrapper: NSView) {
        let isHeaderHidden = Settings.shared.topBarVisibility == .hidden
        if isHeaderHidden {
            wrapper.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            if Settings.shared.dragAreaPosition == .top {
                // Top bar is at the top, so we want the bottom corners of the webview to be rounded
                wrapper.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else {
                // Top bar is at the bottom, so we want the top corners of the webview to be rounded
                wrapper.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
    }

    /// Forces every visible webView's viewport to recompute after the WebKit
    /// element-fullscreen exit. WebKit re-parents the webView from the
    /// fullscreen window back to its wrapper but leaves the webView's frame
    /// at fullscreen size; `updateLayout()` above corrects the frame, and a
    /// synthetic resize event forces media queries / JS listeners to reflow.
    func refreshViewportAfterFullscreenExit() {
        updateLayout()
        containerView?.needsLayout = true
        containerView?.layoutSubtreeIfNeeded()
        for sessionMap in webviewsByID.values {
            for webView in sessionMap.values {
                webView.superview?.needsLayout = true
                webView.superview?.layoutSubtreeIfNeeded()
                webView.needsLayout = true
                // Dispatch resize in the web process; harmless for background tabs.
                webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
            }
        }
    }
    
    func showSession(_ webView: WKWebView) {
        guard let wrapper = webView.superview else {
            NSLog("[WebViewManager] showSession failed: webView has no superview!")
            return
        }
        
        wrapper.isHidden = false
        webView.evaluateJavaScript("window.__quiperInputTrackerActive = true", completionHandler: nil)
        pushRecordingIndicatorState(to: webView)
        
        if let container = containerView, wrapper.superview != container {
            if let dragArea = self.dragArea {
                container.addSubview(wrapper, positioned: .below, relativeTo: dragArea)
            } else {
                container.addSubview(wrapper)
            }
        }
        
        let token = ObjectIdentifier(webView)
        if let targetURLString = pendingLazyLoadURLs.removeValue(forKey: token) {
            if let url = URL(string: targetURLString) {
                NSLog("[WebViewManager] Lazy loading background session webview: %@", targetURLString)
                if url.isFileURL {
                    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                } else {
                    webView.load(URLRequest(url: url))
                }
            } else {
                showLoadError(WebLoadError(kind: .invalidURL), for: webView)
            }
        }
        
        updateLayout()
    }
    
    func serviceURL(for webView: WKWebView) -> URL? {
        service(for: webView).flatMap { URL(string: $0.url) }
    }

    func service(for webView: WKWebView) -> Service? {
        guard let serviceID = serviceIDsByWebView[ObjectIdentifier(webView)] else {
            return nil
        }
        return services.first(where: { $0.id == serviceID })
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
    
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView else { return }
        
        MainActor.assumeIsolated {
            if keyPath == "title" {
                retainTitle(webView.title, for: webView)
                delegate?.webViewDidUpdateTitle(webView.title ?? "", for: webView)
            } else if keyPath == "loading" {
                delegate?.webViewDidUpdateLoading(webView.isLoading, for: webView)
            } else if keyPath == "fullscreenState" {
                delegate?.webViewDidUpdateFullscreenState(webView.fullscreenState, for: webView)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func tearDownWebView(_ webView: WKWebView) {
        // Stop any in-progress loading to signal WebKit to release the content process
        let token = ObjectIdentifier(webView)
        var wrapper = webView.superview as? WebViewWrapperView
        // When the webView is fullscreen its superview is the WebKit fullscreen
        // window's contentView, not its wrapper. Look up the wrapper via the
        // service/session maps so we can remove it correctly and avoid leaving
        // a ghost wrapper that shows the fullscreen webView as a background
        // behind the overlay's transparent areas.
        if wrapper == nil, let serviceID = serviceIDsByWebView[token],
           let sessionMap = webviewsByID[serviceID] {
            for (sessionIndex, candidate) in sessionMap where candidate === webView {
                if let found = wrappersByID[serviceID]?[sessionIndex] as? WebViewWrapperView {
                    wrapper = found
                    break
                }
            }
        }
        // If the webView is currently hosted in a different window than its
        // wrapper (the WebKit element-fullscreen window), close that window.
        // This prevents the fullscreen window from lingering as a ghost
        // background behind the overlay's transparent regions after the lock
        // tears the webView down. The close will trigger
        // NSWindow.willExitFullScreenNotification and clear MainWindowController
        // state via handleWindowWillExitWebFullScreen.
        if let currentWindow = webView.window,
           let wrapperWindow = wrapper?.window ?? containerView?.window,
           currentWindow !== wrapperWindow {
            currentWindow.close()
        }
        webView.stopLoading()
 
        // Nil delegates to prevent callbacks during/after deallocation
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
 
        detachNotificationBridge(from: webView)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quiperInputState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quiperInputTrackerReady")
 
        // Resume and clear any pending navigation continuation to prevent CheckedContinuation leaks
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        initialLoadAwaitingFocus.remove(token)
        serviceIDsByWebView.removeValue(forKey: token)
        pendingLazyLoadURLs.removeValue(forKey: token)
        lastKnownTitlesByWebView.removeValue(forKey: token)
        wrapper?.detachSessionSurface()
        removeLoadState(for: token)
 
        // Clean user content controller to break configuration references
        webView.configuration.userContentController.removeAllUserScripts()
 
        webView.removeObserver(self, forKeyPath: "title")
        webView.removeObserver(self, forKeyPath: "loading")
        webView.removeObserver(self, forKeyPath: "fullscreenState")

        // Remove the wrapper view (parent) from the view hierarchy, then the webview
        webView.removeFromSuperview()
        wrapper?.removeFromSuperview()
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    private func retainTitle(_ title: String?, for webView: WKWebView) {
        guard let title = Self.normalizedTitle(title) else { return }
        lastKnownTitlesByWebView[ObjectIdentifier(webView)] = title
    }

    private func removeLoadState(for token: ObjectIdentifier) {
        activeRequestURLsByWebView.removeValue(forKey: token)
        failedRequestURLsByWebView.removeValue(forKey: token)
        processTerminationRetryStates.removeValue(forKey: token)
    }

    private func attachNotificationBridge(to webView: WKWebView, service: Service, sessionIndex: Int) {
        let identifier = ObjectIdentifier(webView)
        notificationBridges[identifier] = WebNotificationBridge(
            webView: webView,
            serviceID: service.id,
            serviceName: service.name,
            sessionIndex: sessionIndex,
            iconProvider: {
                Settings.shared.services.first(where: { $0.id == service.id })?
                    .iconBase64.flatMap { Data(base64Encoded: $0) }
            }
        )
    }

    private func detachNotificationBridge(from webView: WKWebView) {
        let identifier = ObjectIdentifier(webView)
        notificationBridges[identifier]?.invalidate()
        notificationBridges.removeValue(forKey: identifier)
    }
    
    @MainActor
    private func openInPopup(url: URL, service: Service, configuration: WKWebViewConfiguration, parentWindow: NSWindow, opener: WKWebView) {
        let popupWebView = makePopupWebView(for: service, configuration: configuration, parentWindow: parentWindow, opener: opener)
        popupWebView.load(URLRequest(url: url))
    }

    /// Single gate for every popup webview: assigns the routing delegates and
    /// registers the service association so links inside popups go through the
    /// same `RoutingResolver` path as main-window webviews.
    ///
    /// The popup is owned by the tab that opened it (`opener`): popups opened
    /// from inside another popup inherit that popup's owner, so the whole
    /// chain hides and shows with the originating session. Ownership is the
    /// single source for session-scoped visibility in
    /// `syncPopupVisibility(forActiveTab:)`; callers never manage popup
    /// windows directly.
    @MainActor
    private func makePopupWebView(for service: Service, configuration: WKWebViewConfiguration, parentWindow: NSWindow, opener: WKWebView? = nil, restoredOwner: TabIdentifier? = nil, restoredFrame: NSRect? = nil, startHidden: Bool = false) -> WKWebView {
        configuration.preferences.isElementFullscreenEnabled = true
        // Nest under the opener's window: AppKit pins a child above its
        // parent, so a popup opened from another popup stays above its
        // opener even when the opener is clicked.
        let popupWindow = ModalPopupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            parentWindow: parentWindow
        )
        if let restoredFrame {
            popupWindow.setFrame(restoredFrame, display: false)
        } else {
            popupWindow.center()
            // Cascade: a newly opened popup shifts right and down from
            // center per live sibling, so it never lands exactly over them.
            popupWindow.setFrameOrigin(
                cascadedPopupOrigin(centeredFrame: popupWindow.frame, siblingCount: popupWindowsByToken.count)
            )
        }

        let popupWebView = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
        popupWebView.autoresizingMask = [.width, .height]
        popupWebView.uiDelegate = self
        popupWebView.navigationDelegate = self

        let token = ObjectIdentifier(popupWebView)
        serviceIDsByWebView[token] = service.id
        if let restoredOwner {
            popupOwnerByToken[token] = restoredOwner
        } else if let opener, let owner = ownerTab(for: opener) {
            popupOwnerByToken[token] = owner
        }
        popupWindowsByToken[token] = popupWindow
        popupCreationCounter += 1
        popupCreationOrder[token] = popupCreationCounter
        popupWindow.hostedWebView = popupWebView
        popupWindow.onClose = { [weak self] in
            self?.unregisterPopupWebView(token: token)
        }

        popupWindow.observeWebViewTitle(popupWebView, fallbackTitle: service.name)

        popupWindow.contentView?.addSubview(popupWebView)
        if startHidden {
            // Relaunch restore: stay ordered out until the session switch /
            // overlay show path syncs visibility for the active tab.
            popupWindow.setSessionHidden(true)
        } else {
            popupWindow.makeKeyAndOrderFront(nil)
            // Composite immediately so opener chains attach to displayed
            // parents even when the whole tree shows at once.
            popupWindow.display()
        }

        return popupWebView
    }

    /// Resolves the owning session for a new popup opened from `opener`.
    /// Popups opened from inside another popup inherit that popup's owner so
    /// the whole chain stays bound to the originating session.
    @MainActor
    private func ownerTab(for opener: WKWebView) -> TabIdentifier? {
        let openerToken = ObjectIdentifier(opener)
        if let inherited = popupOwnerByToken[openerToken] {
            return inherited
        }
        if let (service, sessionIndex) = findServiceAndSession(for: opener) {
            return TabIdentifier(serviceID: service.id, sessionIndex: sessionIndex)
        }
        return nil
    }

    /// Whether `window` is one of this manager's session popup windows.
    /// Single source for popup identity: callers (e.g. the shortcut modal
    /// gate) never sniff window classes directly.
    @MainActor
    func isPopupWindow(_ window: NSWindow) -> Bool {
        popupWindowsByToken.values.contains { $0 === window }
    }

    /// The popup webview hosted by `window`, or nil when `window` is not a
    /// session popup. Single gate for popup content: callers never reach
    /// into popup windows directly.
    @MainActor
    func popupWebView(for window: NSWindow) -> WKWebView? {
        for popupWindow in popupWindowsByToken.values where popupWindow === window {
            return popupWindow.hostedWebView
        }
        return nil
    }

    /// Single gate for a popup's find bar. Each popup webview owns one
    /// `FindBarViewController` (same class as main-window tabs, so find
    /// semantics never drift), attached to the popup's content view.
    @MainActor
    func findBarController(forPopupWebView webView: WKWebView) -> FindBarViewController? {
        let token = ObjectIdentifier(webView)
        guard popupWindowsByToken[token] != nil else { return nil }
        popupFindBars = popupFindBars.filter { $0.value.webView != nil }
        if let existing = popupFindBars[token], existing.webView === webView {
            return existing
        }
        guard let hostView = webView.superview else { return nil }
        let controller = FindBarViewController()
        if let findDelegate = delegate as? FindBarDelegate {
            controller.delegate = findDelegate
        }
        controller.attach(to: webView, in: hostView)
        popupFindBars[token] = controller
        return controller
    }

    /// Hides every popup whose owner is not `active` and re-shows (at its
    /// preserved frame) every popup owned by `active`. Popups without a known
    /// owner stay visible for every session, preserving the pre-scoping
    /// behavior for unresolvable openers. Visibility is driven only from the
    /// session switch path and the overlay show path (AppKit re-shows
    /// ordered-out children on parent show, so the show path must re-hide
    /// inactive ones).
    @MainActor
    func syncPopupVisibility(forActiveTab active: TabIdentifier) {
        // Two passes so a show can never be buried by a later hide, and
        // restores follow creation order so the stacking matches before.
        let orderedTokens = popupWindowsByToken.keys.sorted {
            (popupCreationOrder[$0] ?? 0) < (popupCreationOrder[$1] ?? 0)
        }
        for token in orderedTokens {
            if let owner = popupOwnerByToken[token], owner != active {
                popupWindowsByToken[token]?.setSessionHidden(true)
            }
        }
        for token in orderedTokens {
            if popupOwnerByToken[token] == nil {
                popupWindowsByToken[token]?.setSessionHidden(false)
            } else if popupOwnerByToken[token] == active {
                popupWindowsByToken[token]?.setSessionHidden(false)
            }
        }
    }

    /// Hides every session-owned popup without closing it. Used when the
    /// overlay has no active session (empty state).
    @MainActor
    func hideAllSessionPopups() {
        for popupWindow in popupWindowsByToken.values {
            popupWindow.setSessionHidden(true)
        }
    }

    /// Snapshots open popups for tab survival, oldest first so restores
    /// reproduce stacking. Only popups with a known owner, a live owning
    /// session, and a real http(s) URL persist; ownerless popups, temporary
    /// tabs' popups, and blank pages stay in-memory only. URLs are stored
    /// normalized (lowercased host, no trailing slash or fragment) so
    /// redirect-canonicalized addresses dedup stably. A still-loading
    /// restored popup contributes its pending URL until the load commits.
    @MainActor
    func getPopupSnapshotState() -> [PersistedPopupState] {
        let orderedTokens = popupWindowsByToken.keys.sorted {
            (popupCreationOrder[$0] ?? 0) < (popupCreationOrder[$1] ?? 0)
        }
        return orderedTokens.compactMap { token in
            guard let popupWindow = popupWindowsByToken[token],
                  let owner = popupOwnerByToken[token],
                  !isTemporaryTab(serviceID: owner.serviceID, sessionIndex: owner.sessionIndex),
                  webviewsByID[owner.serviceID]?[owner.sessionIndex] != nil,
                  let rawURL = popupWindow.hostedWebView?.url?.absoluteString,
                  let urlString = Self.normalizedPopupURLString(rawURL) ?? popupPendingURLByToken[token],
                  !urlString.isEmpty
            else { return nil }
            let frame = popupWindow.frame
            return PersistedPopupState(
                serviceID: owner.serviceID,
                sessionIndex: owner.sessionIndex,
                url: urlString,
                frameX: frame.origin.x,
                frameY: frame.origin.y,
                frameWidth: frame.size.width,
                frameHeight: frame.size.height
            )
        }
    }

    /// Recreates persisted popups in stored (creation) order so stacking
    /// matches the previous run. Each popup reloads its URL in its session's
    /// configuration (same store/process pool as its owner); `window.opener`
    /// links, history, and POST state are inherently unrestorable. Popups
    /// whose owner has no live session are skipped. Callers sync visibility
    /// for the active tab afterwards (late arrivals self-show when their
    /// owner is displayed).
    @MainActor
    func restorePopups(_ popups: [PersistedPopupState]) {
        var occurrenceByKey: [PopupOwnerURL: Int] = [:]
        let baseline = livePopupCountsByOwnerURL()
        for popup in popups {
            guard let normalizedURL = Self.normalizedPopupURLString(popup.url) else { continue }
            let key = PopupOwnerURL(serviceID: popup.serviceID, sessionIndex: popup.sessionIndex, url: normalizedURL)
            let occurrence = (occurrenceByKey[key] ?? 0) + 1
            occurrenceByKey[key] = occurrence
            restoreOnePopup(popup, key: key, occurrence: occurrence, baseline: baseline)
        }
    }

    /// Creates one persisted popup now. The k-th persisted entry for an
    /// owner+URL is skipped while k live ones already cover it, making
    /// repeat restores idempotent without collapsing legit same-URL
    /// duplicates. Nests under the owner's newest live popup to rebuild
    /// opener chains, and shows immediately when its owner is displayed.
    @MainActor
    private func restoreOnePopup(_ popup: PersistedPopupState, key: PopupOwnerURL, occurrence: Int, baseline: [PopupOwnerURL: Int]) {
        guard let service = services.first(where: { $0.id == popup.serviceID }),
              let sessionWebView = webviewsByID[service.id]?[popup.sessionIndex],
              !isTemporaryTab(serviceID: service.id, sessionIndex: popup.sessionIndex),
              !isLockedPlaceholder(sessionWebView),
              let overlayWindow = containerView?.window ?? sessionWebView.window
        else { return }
        let liveNow = livePopupCountsByOwnerURL()[key] ?? 0
        guard liveNow < (baseline[key] ?? 0) + occurrence else { return }
        guard let url = URL(string: key.url) else { return }
        let frame = NSRect(
            x: popup.frameX, y: popup.frameY,
            width: popup.frameWidth, height: popup.frameHeight
        )
        let shouldShow = sessionWebView.superview?.isHidden == false && overlayWindow.isVisible
        let popupWebView = makePopupWebView(
            for: service,
            configuration: sessionWebView.configuration,
            parentWindow: newestLivePopupWindow(for: popup.owner) ?? overlayWindow,
            restoredOwner: popup.owner,
            restoredFrame: validatedRestoredFrame(frame),
            startHidden: !shouldShow
        )
        popupPendingURLByToken[ObjectIdentifier(popupWebView)] = key.url
        popupWebView.load(URLRequest(url: url))
    }

    /// Newest live popup window for an owner, used to rebuild opener chains
    /// at restore time without tracking order across passes.
    @MainActor
    private func newestLivePopupWindow(for owner: TabIdentifier) -> NSWindow? {
        popupOwnerByToken.compactMap { token, existingOwner -> (Int, NSWindow)? in
            guard existingOwner == owner, let window = popupWindowsByToken[token] else { return nil }
            return (popupCreationOrder[token] ?? 0, window)
        }.max(by: { $0.0 < $1.0 })?.1
    }

    /// Cascade origin for a newly opened popup: centered frame shifted right
    /// and down one step per live sibling, wrapping every 8 so long chains
    /// stay on screen. Falls back to center when the shift would leave all
    /// screens.
    @MainActor
    private func cascadedPopupOrigin(centeredFrame: NSRect, siblingCount: Int) -> NSPoint {
        let step = CGFloat(siblingCount % 8)
        let origin = NSPoint(x: centeredFrame.origin.x + step * 26, y: centeredFrame.origin.y - step * 22)
        let shifted = NSRect(origin: origin, size: centeredFrame.size)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(shifted) }) else {
            return centeredFrame.origin
        }
        return origin
    }

    /// Keeps a persisted frame only when it is sanely sized and at least
    /// partially on a current screen; otherwise nil falls back to centering.
    @MainActor
    private func validatedRestoredFrame(_ frame: NSRect) -> NSRect? {
        guard frame.width >= 300, frame.height >= 200,
              frame.width <= 4000, frame.height <= 3000,
              NSScreen.screens.contains(where: { $0.frame.intersects(frame) })
        else { return nil }
        return frame
    }

    /// Canonical popup URL for persistence and dedup: http(s) only, with
    /// lowercased host, no trailing slash, and no fragment, so
    /// redirect-canonicalized addresses match their persisted form.
    private static func normalizedPopupURLString(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.lowercased()
        components.port = url.port
        components.path = path
        components.query = url.query
        guard let normalized = components.string, !normalized.isEmpty else { return nil }
        return normalized
    }

    /// Live (or still-loading) popup counts per owner+URL, backing
    /// idempotent restores.
    @MainActor
    private func livePopupCountsByOwnerURL() -> [PopupOwnerURL: Int] {
        var counts: [PopupOwnerURL: Int] = [:]
        for (token, owner) in popupOwnerByToken {
            let rawURL = popupWindowsByToken[token]?.hostedWebView?.url?.absoluteString
            let normalized = rawURL.flatMap(Self.normalizedPopupURLString) ?? popupPendingURLByToken[token]
            guard let normalized else { continue }
            let key = PopupOwnerURL(serviceID: owner.serviceID, sessionIndex: owner.sessionIndex, url: normalized)
            counts[key, default: 0] += 1
        }
        return counts
    }

    /// Whether the session is still behind its lock overlay (encrypted engine
    /// not yet unlocked): its placeholder webview must not sprout popups.
    @MainActor
    private func isLockedPlaceholder(_ sessionWebView: WKWebView) -> Bool {
        sessionWebView.superview?.subviews.contains(where: { $0 is LockOverlayView }) == true
    }

    /// Closes every popup owned by `tab`. Called when the owning session is
    /// destroyed; the window's close path unregisters it.
    @MainActor
    private func closePopups(for tab: TabIdentifier) {
        let tokens = popupOwnerByToken.filter { $0.value == tab }.map(\.key)
        for token in tokens {
            if let popupWindow = popupWindowsByToken[token] {
                popupWindow.close()
            } else {
                unregisterPopupWebView(token: token)
            }
        }
    }

    /// Closes every popup associated with `serviceID`, owned or global.
    @MainActor
    private func closePopups(forServiceID serviceID: UUID) {
        var tokens = Set(popupOwnerByToken.filter { $0.value.serviceID == serviceID }.map(\.key))
        tokens.formUnion(serviceIDsByWebView.filter { $0.value == serviceID }.map(\.key).filter { popupWindowsByToken[$0] != nil })
        for token in tokens {
            if let popupWindow = popupWindowsByToken[token] {
                popupWindow.close()
            } else {
                unregisterPopupWebView(token: token)
            }
        }
    }

    @MainActor
    private func unregisterPopupWebView(token: ObjectIdentifier) {
        if let window = popupWindowsByToken[token] {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        }
        serviceIDsByWebView.removeValue(forKey: token)
        popupOwnerByToken.removeValue(forKey: token)
        popupWindowsByToken.removeValue(forKey: token)
        popupCreationOrder.removeValue(forKey: token)
        popupPendingURLByToken.removeValue(forKey: token)
        popupFindBars.removeValue(forKey: token)
        removeLoadState(for: token)
    }

    @MainActor
    private func routingContext(for webView: WKWebView, service: Service) -> (serviceURL: URL?, pinnedURL: URL?) {
        if service.isPinnedTabs,
           let (_, sessionIndex) = findServiceAndSession(for: webView),
           let pinned = RoutingResolver.pinnedURL(for: service, sessionIndex: sessionIndex) {
            return (pinned, pinned)
        }
        return (URL(string: service.url), nil)
    }

    @MainActor
    private func presentRoutingPrompt(for url: URL, service: Service, webView: WKWebView, completion: @escaping @MainActor @Sendable (RoutingResolver.Decision, Bool) -> Void) {
        guard let window = webView.window else {
            completion(.openExternal, false)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Security & Routing"
        alert.informativeText = "How would you like to open this link?\n\(url.absoluteString)"

        // Pinned tabs never navigate in place, so the prompt offers only
        // new-window or external choices.
        let offersOpenHere = !service.isPinnedTabs
        if offersOpenHere {
            alert.addButton(withTitle: "Open Here")
        }
        alert.addButton(withTitle: "Open in New Window")
        alert.addButton(withTitle: "Open Externally")
        let cancelBtn = alert.addButton(withTitle: "Cancel")
        cancelBtn.keyEquivalent = "\u{1b}" // Escape key

        let checkbox = NSButton(checkboxWithTitle: "Remember my choice for this domain", target: nil, action: nil)
        checkbox.font = .systemFont(ofSize: 11)
        alert.accessoryView = checkbox

        alert.beginSheetModal(for: window) { response in
            let action: RoutingResolver.Decision
            if offersOpenHere {
                switch response {
                case .alertFirstButtonReturn:
                    action = .openHere
                case .alertSecondButtonReturn:
                    action = .openNewWindow
                case .alertThirdButtonReturn:
                    action = .openExternal
                default:
                    action = .cancel
                }
            } else {
                switch response {
                case .alertFirstButtonReturn:
                    action = .openNewWindow
                case .alertSecondButtonReturn:
                    action = .openExternal
                default:
                    action = .cancel
                }
            }
            let remember = checkbox.state == .on
            completion(action, remember)
        }
    }

    @MainActor
    private func rememberDecision(for host: String, action: RoutingResolver.Decision, service: Service) {
        guard !host.isEmpty else { return }
        
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == service.id }) else { return }

        let routingAction: RoutingAction
        switch action {
        case .openHere:
            // Pinned tabs never navigate in place; remember the popup form.
            routingAction = Settings.shared.services[index].isPinnedTabs ? .popup : .internalStay
        case .openNewWindow:
            routingAction = .popup
        case .openExternal:
            routingAction = .external
        default:
            return
        }
        
        Settings.shared.services[index] = RoutingResolver.applyingRememberedRule(host: host, action: routingAction, to: Settings.shared.services[index])
        Settings.shared.saveSettings()
    }
    
    /// Commit-only primitive behind `TabCloseGate`: see `removeWebView(for:)`.
    func tearDownAllWebViews(for service: Service) {
        guard let sessionMap = webviewsByID[service.id] else { return }
        for sessionIndex in Array(sessionMap.keys) {
            removeWebView(for: service, sessionIndex: sessionIndex)
        }
    }
}

// MARK: - WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate

@MainActor
private final class ModalPopupWindow: NSWindow, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?
    weak var hostedWebView: WKWebView?
    private var shield: InteractionShieldView?
    private weak var parentWin: NSWindow?
    private var isCleaningUp = false
    private var titleObservation: NSKeyValueObservation?

    /// Whether the window is inside its close path. Children check their
    /// parent's flag before handing focus back, so closing an opener does
    /// not re-show it via a child's deferred activation.
    var isClosing: Bool { isCleaningUp }
    
    init(contentRect: NSRect, parentWindow: NSWindow) {
        self.parentWin = parentWindow
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        
        self.level = .floating
        self.collectionBehavior = Settings.shared.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
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
    
    func observeWebViewTitle(_ webView: WKWebView, fallbackTitle: String) {
        self.title = fallbackTitle
        let fallback = fallbackTitle
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let newTitle = change.newValue as? String, !newTitle.isEmpty {
                    self.title = "\(newTitle) - \(fallback)"
                } else {
                    self.title = fallback
                }
            }
        }
    }

    /// Session-scoped hide/show. Hiding orders the window out (preserving its
    /// frame for an exact restore) and hides its modal shield so the newly
    /// active session stays interactive. Showing restores the shield and, when
    /// the Quiper window itself is visible, re-orders the popup front at its
    /// preserved frame. When Quiper is hidden the reorder is deferred to the
    /// overlay show path, which re-syncs visibility after AppKit restores
    /// child windows.
    func setSessionHidden(_ hidden: Bool) {
        if hidden {
            shield?.isHidden = true
            orderOut(nil)
        } else {
            shield?.isHidden = false
            guard parentWin?.isVisible == true else { return }
            if isVisible {
                // Re-assert creation-order position: AppKit's own reshow of
                // a hidden tree does not reliably restore child stacking.
                orderFront(nil)
            } else {
                makeKeyAndOrderFront(nil)
            }
            // Commit the mapping before younger siblings show, so opener
            // chains pin even when the whole tree shows at once.
            CATransaction.flush()
            display()
        }
    }
    
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        // Close child popups first so none outlive their parent as detached
        // orphans. Copied: closing detaches each child from this window.
        for child in childWindows?.compactMap({ $0 as? ModalPopupWindow }) ?? [] {
            child.close()
        }
        
        titleObservation?.invalidate()
        titleObservation = nil
        
        // 1. Remove only this popup's shield: other sessions' popups keep
        // their own shields so the newly active session's modality survives.
        shield?.removeFromSuperview()
        shield = nil
        
        // 2. Nil out webview delegates to avoid crashes from WebKit callbacks during deallocation
        contentView?.subviews.forEach {
            if let webView = $0 as? WKWebView {
                webView.uiDelegate = nil
                webView.navigationDelegate = nil
                webView.stopLoading()
                webView.configuration.userContentController.removeAllUserScripts()
                webView.removeFromSuperview()
            }
        }
        
        // 3. Detach from parent
        if let parent = parentWin {
            parent.removeChildWindow(self)
            
            // 4. Asynchronously restore focus to avoid AppKit re-entrancy issues.
            // Skipped when the parent is itself closing (cascade close),
            // whose own cleanup hands focus upward.
            DispatchQueue.main.async { [weak parent] in
                guard let parent, (parent as? ModalPopupWindow)?.isClosing != true else { return }
                parent.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        
        // 5. Break self-delegate cycle to allow deallocation
        self.delegate = nil

        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
    
    func windowWillClose(_ notification: Notification) {
        cleanup()
    }
}

@MainActor
fileprivate final class PopupUIDelegate: NSObject, WKUIDelegate {
    static let shared = PopupUIDelegate()

    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
    }

    @MainActor
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        
        if #available(macOS 10.13.4, *) {
            if parameters.allowsDirectories {
                openPanel.canChooseDirectories = true
            }
        }

        guard let window = webView.window else {
            completionHandler(nil)
            return
        }

        openPanel.beginSheetModal(for: window) { response in
            if response == .OK {
                completionHandler(openPanel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\u{1b}"
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    @available(macOS 12.0, *)
    @MainActor
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        Task { @MainActor in
            let granted = await MediaCapturePermission.ensureAccess(for: type)
            decisionHandler(granted ? .grant : .deny)
        }
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
              let service = service(for: webView) else {
            if let url = navigationAction.request.url {
                 NSWorkspace.shared.open(url)
            }
            return nil
        }
        // Explicit new-window requests (context-menu "Open Link in New
        // Window", target=_blank, window.open) always open a Quiper popup.
        // Link routing decides plain left-clicks in decidePolicyFor; applying
        // it here sent the same menu item to Safari or a prompt depending on
        // hidden rules. The approval carries the initial load through the
        // popup's own decidePolicyFor pass.
        guard let parentWindow = webView.window else { return nil }
        approvedURLs.insert(url)
        return makePopupWebView(for: service, configuration: configuration, parentWindow: parentWindow, opener: webView)
    }

    @MainActor
    func webViewDidClose(_ webView: WKWebView) {
        // `window.close()` from JS must only ever dismiss a popup. Main-window
        // webviews are owned by the overlay and never close this way.
        if let popupWindow = webView.window, isPopupWindow(popupWindow) {
            popupWindow.close()
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        PopupUIDelegate.shared.webView(webView, runOpenPanelWith: parameters, initiatedByFrame: frame, completionHandler: completionHandler)
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        PopupUIDelegate.shared.webView(webView, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler)
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        PopupUIDelegate.shared.webView(webView, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler)
    }

    @MainActor
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        PopupUIDelegate.shared.webView(webView, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText, initiatedByFrame: frame, completionHandler: completionHandler)
    }

    @available(macOS 12.0, *)
    @MainActor
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        PopupUIDelegate.shared.webView(webView, requestMediaCapturePermissionFor: origin, initiatedByFrame: frame, type: type, decisionHandler: decisionHandler)
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
        }

        let targetFrameIsMain = navigationAction.targetFrame?.isMainFrame ?? true
        // New-window requests (targetFrame == nil) are owned by
        // createWebViewWith, which always opens a Quiper popup for explicit
        // gestures. Let them through so routing cannot divert the same
        // gesture to Safari here before the popup is created.
        if navigationAction.targetFrame == nil {
            let allowWithoutAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowWithoutAppLink)
            return
        }
        if targetFrameIsMain, let requestURL = navigationAction.request.url {
            beginMainFrameNavigation(webView, to: requestURL)
        }

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let service = service(for: webView) else {
            decisionHandler(.allow)
            return
        }
        let (serviceURL, pinnedURL) = routingContext(for: webView, service: service)
        guard let serviceURL else {
            decisionHandler(.allow)
            return
        }

        // Only route in-place main-frame navigations. New windows
        // (targetFrame == nil) are handled above by the popup path.
        if !targetFrameIsMain {
            decisionHandler(.allow)
            return
        }

        // Loop prevention check
        if approvedURLs.contains(url) {
            approvedURLs.remove(url)
            let allowWithoutAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowWithoutAppLink)
            return
        }

        let optionPressed = navigationAction.modifierFlags.contains(.option)
        var action = RoutingResolver.route(for: url, service: service, serviceURL: serviceURL, pinnedURL: pinnedURL)
        if action == .openExternal && optionPressed {
            action = .showPrompt
        }
        
        switch action {
        case .openHere:
            let allowWithoutAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowWithoutAppLink)
            
        case .openNewWindow:
            if let parentWindow = webView.window {
                openInPopup(url: url, service: service, configuration: webView.configuration, parentWindow: parentWindow, opener: webView)
            }
            decisionHandler(.cancel)
            
        case .openExternal:
            if service.isPinnedTabs, navigationAction.navigationType != .linkActivated {
                // Pinned tabs never navigate in place, even for form submits
                // and redirects. The popup shares the engine's store, so
                // sessions set during auth bounces survive; Safari would
                // strand them outside Quiper.
                if let parentWindow = webView.window {
                    openInPopup(url: url, service: service, configuration: webView.configuration, parentWindow: parentWindow, opener: webView)
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
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
            
        case .showPrompt:
            decisionHandler(.cancel)
            presentRoutingPrompt(for: url, service: service, webView: webView) { [weak self] chosenAction, remember in
                guard let self = self else { return }
                if remember {
                    let host = url.host ?? ""
                    self.rememberDecision(for: host, action: chosenAction, service: service)
                }
                
                switch chosenAction {
                case .openHere:
                    self.approvedURLs.insert(url)
                    webView.load(URLRequest(url: url))
                case .openNewWindow:
                    if let parentWindow = webView.window {
                        self.openInPopup(url: url, service: service, configuration: webView.configuration, parentWindow: parentWindow, opener: webView)
                    }
                case .openExternal:
                    NSWorkspace.shared.open(url)
                case .showPrompt, .cancel:
                    break
                }
            }
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        // Server responses — including 4xx/5xx error pages — render natively:
        // the site's own error content is almost always more useful than a
        // generic panel, and cancelling here would strand policy-interrupted
        // navigations with a misleading failure.
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

    @MainActor
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        ServerAuthenticationCoordinator.shared.handle(
            challenge,
            serviceName: service(for: webView)?.name,
            completionHandler: completionHandler
        ) { [weak self] prompt, respond in
            guard let self else {
                respond(.cancel)
                return
            }
            self.presentAuthenticationPrompt(prompt, for: webView, completion: respond)
        }
    }

    @MainActor
    private func presentAuthenticationPrompt(_ prompt: ServerAuthenticationPrompt, for webView: WKWebView, completion: @escaping (ServerAuthenticationDecision) -> Void) {
        guard let window = webView.window else {
            completion(.cancel)
            return
        }

        let alert = NSAlert()
        if let serviceName = prompt.serviceName, !serviceName.isEmpty {
            alert.messageText = "Sign in to \(serviceName)"
        } else {
            alert.messageText = "Sign in to \(prompt.displayHost)"
        }
        var details: [String] = []
        if prompt.serviceName != nil {
            details.append(prompt.displayHost)
        }
        if prompt.isRetry {
            details.append("The previous user name or password was incorrect.")
        }
        if prompt.showsUnencryptedWarning {
            details.append("Your password will be sent unencrypted.")
        }
        alert.informativeText = details.joined(separator: "\n")

        let usernameField = NSTextField()
        usernameField.placeholderString = "User Name"
        usernameField.stringValue = prompt.suggestedUsername
        let passwordField = NSSecureTextField()
        passwordField.placeholderString = "Password"
        let rememberCheckbox = NSButton(checkboxWithTitle: "Remember this password", target: nil, action: nil)
        rememberCheckbox.font = .systemFont(ofSize: 11)
        // NSAlert doesn't size stack-based accessories reliably (overlap/clipping),
        // so lay the form out in an explicitly framed container instead.
        let formWidth: CGFloat = 300
        let fieldHeight: CGFloat = 24
        let checkboxHeight: CGFloat = 18
        let fieldSpacing: CGFloat = 8
        let checkboxSpacing: CGFloat = 10
        let formHeight = fieldHeight * 2 + checkboxHeight + fieldSpacing + checkboxSpacing
        passwordField.frame = NSRect(x: 0, y: checkboxHeight + checkboxSpacing, width: formWidth, height: fieldHeight)
        usernameField.frame = NSRect(
            x: 0,
            y: checkboxHeight + checkboxSpacing + fieldHeight + fieldSpacing,
            width: formWidth,
            height: fieldHeight
        )
        rememberCheckbox.frame = NSRect(x: 0, y: 0, width: formWidth, height: checkboxHeight)
        let formView = NSView(frame: NSRect(x: 0, y: 0, width: formWidth, height: formHeight))
        formView.addSubview(usernameField)
        formView.addSubview(passwordField)
        formView.addSubview(rememberCheckbox)
        alert.accessoryView = formView

        alert.addButton(withTitle: "Sign In")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}" // Escape key
        let signInButton = alert.buttons[0]
        signInButton.isEnabled = !usernameField.stringValue.isEmpty && !passwordField.stringValue.isEmpty

        var observation: NSObjectProtocol?
        observation = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            signInButton.isEnabled = !usernameField.stringValue.isEmpty && !passwordField.stringValue.isEmpty
        }

        alert.window.initialFirstResponder = prompt.suggestedUsername.isEmpty ? usernameField : passwordField
        alert.beginSheetModal(for: window) { response in
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
            guard response == .alertFirstButtonReturn else {
                completion(.cancel)
                return
            }
            completion(.signIn(
                username: usernameField.stringValue,
                password: passwordField.stringValue,
                remember: rememberCheckbox.state == .on
            ))
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
        let token = ObjectIdentifier(webView)
        var retryState = processTerminationRetryStates[token] ?? WebProcessTerminationRetryState()
        if retryState.shouldRetry() {
            processTerminationRetryStates[token] = retryState
            if let url = webView.url ?? activeRequestURLsByWebView[token] {
                beginMainFrameNavigation(webView, to: url)
                webView.reload()
            } else {
                showLoadError(WebLoadError(kind: .contentProcessTerminated), for: webView)
            }
        } else {
            showLoadError(
                WebLoadError(kind: .contentProcessTerminated, url: webView.url ?? activeRequestURLsByWebView[token]),
                for: webView
            )
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // We handle loading state via KVO and delegates, so mostly nothing needed here
        // Except explicit reset calls if needed
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let token = ObjectIdentifier(webView)
        processTerminationRetryStates[token]?.reset()
        clearLoadError(for: webView)
        activeRequestURLsByWebView[token] = webView.url ?? activeRequestURLsByWebView[token]
        // Loads re-run the creation-time stylesheet, so re-apply whatever is
        // current (covers lazy tabs and post-edit navigations).
        applyCurrentCustomCSS(to: webView)
        // A restored popup's load committed: the live URL takes over from
        // the pending one in snapshots and dedup.
        popupPendingURLByToken.removeValue(forKey: token)
        
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        
        delegate?.webViewDidFinishNavigation(webView)
        
        if initialLoadAwaitingFocus.contains(token) {
            initialLoadAwaitingFocus.remove(token)
            delegate?.webViewDidFinishNavigation(webView) 
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        popupPendingURLByToken.removeValue(forKey: ObjectIdentifier(webView))
        handleNavigationFailure(error, for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        popupPendingURLByToken.removeValue(forKey: ObjectIdentifier(webView))
        handleNavigationFailure(error, for: webView)
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

    @objc private func webDataClearedNotification(_ notification: Notification) {
        guard let serviceID = notification.object as? UUID else { return }
        handleWebDataCleared(for: serviceID)
    }

    /// Drops the engine's persisted popups so the clear-triggered unlock
    /// cannot resurrect pre-clear popup URLs over fresh sessions.
    private func stripSecurePopups(for serviceID: UUID) {
        guard EncryptedVolumeManager.shared.isUnlocked(for: serviceID) else { return }
        let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID).appendingPathComponent("quiper_tabs.json")
        guard let data = try? Data(contentsOf: stateURL),
              var secureState = try? JSONDecoder().decode(MainWindowController.SecureTabState.self, from: data),
              secureState.popups != nil else { return }
        secureState.popups = nil
        if let updated = try? JSONEncoder().encode(secureState) {
            try? updated.write(to: stateURL, options: .atomic)
        }
    }

    /// Commit-only: the web-data reset flow warns through TabCloseGate
    /// before clearing the store and posting `.webDataCleared`.
    private func handleWebDataCleared(for serviceID: UUID) {
        NSLog("[WebViewManager] Handling web data cleared for service: %@", serviceID.uuidString)
        
        // 1. Find all active session indices for this service ID
        guard let sessionMap = webviewsByID[serviceID] else { return }
        let sessionIndices = Array(sessionMap.keys)

        // 2. Tear down the old webviews (and their session-owned popups)
        closePopups(forServiceID: serviceID)
        stripSecurePopups(for: serviceID)
        sessionMap.values.forEach { tearDownWebView($0) }
        webviewsByID[serviceID] = [:]
        wrappersByID[serviceID] = [:]
        
        // 3. Recreate them cleanly
        guard let service = services.first(where: { $0.id == serviceID }) else { return }
        for index in sessionIndices {
            _ = getOrCreateWebView(for: service, sessionIndex: index, dragArea: self.dragArea)
        }
        
        // 4. Update the delegate so it sets up layout correctly
        self.delegate?.engineDidUnlock(serviceID: serviceID)
    }
}

private final class InputStateScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var manager: WebViewManager?

    init(manager: WebViewManager) {
        self.manager = manager
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let mgr = manager
        Task { @MainActor in
            switch message.name {
            case "quiperInputState":
                mgr?.didReceiveInputStateMessage(message)
            case "quiperInputTrackerReady":
                mgr?.didReceiveInputTrackerReadyMessage(message)
            default:
                break
            }
        }
    }
}

// MARK: - Webview context menu
//
// WebKit exposes no delegate API for its context menu on macOS, but the
// native menu passes through `NSView.willOpenMenu`, where
// `ContextMenuWebView` inserts Suggest Selector on top of what WebKit built.
// The manager only forwards the resulting action.

@MainActor
extension WebViewManager: WebViewContextMenuDelegate {
    func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {
        delegate?.webViewDidRequestSelectorSuggest(webView, at: point)
    }

    func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool {
        guard let (service, sessionIndex) = findServiceAndSession(for: webView) else { return false }
        return !isQuiperPrivateTab(serviceID: service.id, sessionIndex: sessionIndex)
    }
}
