import AppKit
import WebKit
import Combine

@MainActor
protocol WebViewManagerDelegate: AnyObject {
    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView)
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView)
    func webViewDidFinishNavigation(_ webView: WKWebView)
    func engineDidUnlock(serviceID: UUID)
    func inputStateRequestSave()
}

@MainActor
final class WebViewManager: NSObject {
    weak var delegate: WebViewManagerDelegate?
    
    // Storage
    var webviewsByID: [UUID: [Int: WKWebView]] = [:]
    private var wrappersByID: [UUID: [Int: NSView]] = [:]
    private var urlsByWebView: [ObjectIdentifier: String] = [:]
    private var pendingLazyLoadURLs: [ObjectIdentifier: String] = [:]
    private var lastKnownTitlesByWebView: [ObjectIdentifier: String] = [:]
    private var activeDownloads: [Any] = []
    
    // State needed for logic
    private var services: [Service] = []
    private var zoomLevels: [String: CGFloat] = [:]
    
    // Dependencies
    private weak var containerView: NSView?
    private weak var dragArea: NSView? // for positioning below
    private var currentContentFrame: NSRect?
    
    // Test support
    private var navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var initialLoadAwaitingFocus = Set<ObjectIdentifier>()
    private var notificationBridges: [ObjectIdentifier: WebNotificationBridge] = [:]
    private var tabInputStates: [String: [Int: TabInputState]] = [:]
    private var tabPromptHistories: [String: [Int: [PromptHistoryEntry]]] = [:]
    private var tabPromptHistoryEnabledOverrides: [String: [Int: Bool]] = [:]
    private var approvedURLs = Set<URL>()
    private var cancellables = Set<AnyCancellable>()

    init(containerView: NSView) {
        self.containerView = containerView
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(webDataClearedNotification(_:)), name: .webDataCleared, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(promptHistoryLimitChangedNotification(_:)), name: .promptHistoryLimitChanged, object: nil)
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
        let incomingIDs = Set(newServices.map { $0.id })
        let existingIDs = Set(webviewsByID.keys)
        
        let removedIDs = existingIDs.subtracting(incomingIDs)
        for id in removedIDs {
            if let removedWebviews = webviewsByID[id] {
                removedWebviews.values.forEach { tearDownWebView($0) }
            }
            webviewsByID.removeValue(forKey: id)
            wrappersByID.removeValue(forKey: id)
        }
        
        // Also check if any existing service has changed its encryption status!
        for newService in newServices {
            if let existingWebviews = webviewsByID[newService.id] {
                if let oldService = self.services.first(where: { $0.id == newService.id }),
                   oldService.isEncrypted != newService.isEncrypted {
                    NSLog("[WebViewManager] Encryption status changed for service %@. Tearing down existing webviews.", newService.name)
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

        let incomingURLs = Set(newServices.map { $0.url })
        for url in tabInputStates.keys {
            if !incomingURLs.contains(url) {
                tabInputStates.removeValue(forKey: url)
            }
        }
        for url in tabPromptHistories.keys {
            if !incomingURLs.contains(url) {
                tabPromptHistories.removeValue(forKey: url)
            }
        }
        for url in tabPromptHistoryEnabledOverrides.keys {
            if !incomingURLs.contains(url) {
                tabPromptHistoryEnabledOverrides.removeValue(forKey: url)
            }
        }
    }
    
    func updateZoomLevels(_ levels: [String: CGFloat]) {
        self.zoomLevels = levels
        for service in services {
            if let level = levels[service.url], let sessionMap = webviewsByID[service.id] {
                sessionMap.values.forEach { $0.pageZoom = level }
            }
        }
    }
    
    func applyZoom(_ level: CGFloat, for serviceURL: String) {
        zoomLevels[serviceURL] = level
        for service in services where service.url == serviceURL {
            if let sessionMap = webviewsByID[service.id] {
                sessionMap.values.forEach { $0.pageZoom = level }
            }
        }
    }
    
    func getWebView(for service: Service, sessionIndex: Int) -> WKWebView? {
        webviewsByID[service.id]?[sessionIndex]
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
        guard let webView = webviewsByID[service.id]?[sessionIndex] else { return }
        tearDownWebView(webView)
        webviewsByID[service.id]?.removeValue(forKey: sessionIndex)
        wrappersByID[service.id]?.removeValue(forKey: sessionIndex)
        tabInputStates[service.url]?.removeValue(forKey: sessionIndex)
        tabPromptHistories[service.url]?.removeValue(forKey: sessionIndex)
        tabPromptHistoryEnabledOverrides[service.url]?.removeValue(forKey: sessionIndex)
    }

    func getOpenSessionTitlesState() -> [String: [Int: String]] {
        var state: [String: [Int: String]] = [:]

        for service in services {
            guard let sessionIndices = webviewsByID[service.id]?.keys else { continue }
            let titles = sessionIndices.reduce(into: [Int: String]()) { result, sessionIndex in
                if let title = sessionTitle(for: service, sessionIndex: sessionIndex) {
                    result[sessionIndex] = title
                }
            }
            if !titles.isEmpty {
                state[service.url] = titles
            }
        }

        return state
    }

    func getOpenSessionsState() -> [String: [Int: String]] {
        var state: [String: [Int: String]] = [:]
        let currentSavedState = Settings.shared.persistedTabState?.openTabs

        for service in services {
            guard let sessionMap = webviewsByID[service.id] else { continue }
            var sessionURLs: [Int: String] = [:]
            for (idx, webView) in sessionMap {
                if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
                    sessionURLs[idx] = urlString
                } else if let previouslySavedURL = currentSavedState?[service.url]?[idx], !previouslySavedURL.isEmpty {
                    sessionURLs[idx] = previouslySavedURL
                } else {
                    sessionURLs[idx] = service.url
                }
            }
            if !sessionURLs.isEmpty {
                state[service.url] = sessionURLs
            }
        }
        return state
    }

    func getOpenSessionsInputState() -> [String: [Int: TabInputState]] {
        return tabInputStates
    }

    func getTabInputState(for serviceURL: String, sessionIndex: Int) -> TabInputState? {
        return tabInputStates[serviceURL]?[sessionIndex]
    }

    func setTabInputState(_ state: TabInputState, for serviceURL: String, sessionIndex: Int) {
        if tabInputStates[serviceURL] == nil {
            tabInputStates[serviceURL] = [:]
        }
        tabInputStates[serviceURL]?[sessionIndex] = state
    }

    func restoreTabInputStates(_ states: [String: [Int: TabInputState]]) {
        for (url, sessionMap) in states {
            if self.tabInputStates[url] == nil {
                self.tabInputStates[url] = [:]
            }
            for (idx, state) in sessionMap {
                self.tabInputStates[url]?[idx] = state
            }
        }
    }

    func getOpenSessionsPromptHistories() -> [String: [Int: [PromptHistoryEntry]]] {
        return tabPromptHistories
    }

    func getOpenSessionsPromptHistoryOverrides() -> [String: [Int: Bool]] {
        return tabPromptHistoryEnabledOverrides
    }

    func restoreTabPromptHistories(_ states: [String: [Int: [PromptHistoryEntry]]]) {
        for (url, sessionMap) in states {
            if self.tabPromptHistories[url] == nil {
                self.tabPromptHistories[url] = [:]
            }
            for (idx, history) in sessionMap {
                self.tabPromptHistories[url]?[idx] = Self.trimmedPromptHistory(history)
            }
        }
    }

    func restoreTabPromptHistoryOverrides(_ states: [String: [Int: Bool]]) {
        for (url, sessionMap) in states {
            if self.tabPromptHistoryEnabledOverrides[url] == nil {
                self.tabPromptHistoryEnabledOverrides[url] = [:]
            }
            for (idx, override) in sessionMap {
                self.tabPromptHistoryEnabledOverrides[url]?[idx] = override
            }
        }
    }

    func getPromptHistory(for serviceURL: String, sessionIndex: Int) -> [PromptHistoryEntry] {
        return tabPromptHistories[serviceURL]?[sessionIndex] ?? []
    }

    func addPromptHistoryEntry(_ entry: PromptHistoryEntry, for serviceURL: String, sessionIndex: Int) {
        if tabPromptHistories[serviceURL] == nil {
            tabPromptHistories[serviceURL] = [:]
        }
        if tabPromptHistories[serviceURL]?[sessionIndex] == nil {
            tabPromptHistories[serviceURL]?[sessionIndex] = []
        }
        
        tabPromptHistories[serviceURL]?[sessionIndex]?.removeAll(where: { $0.text == entry.text })
        
        tabPromptHistories[serviceURL]?[sessionIndex]?.append(entry)
        trimPromptHistory(for: serviceURL, sessionIndex: sessionIndex)
    }

    private static func trimmedPromptHistory(_ history: [PromptHistoryEntry]) -> [PromptHistoryEntry] {
        let limit = Settings.clampedPromptHistoryLimit(Settings.shared.promptHistoryLimit)
        guard history.count > limit else { return history }
        return Array(history.suffix(limit))
    }

    private func trimPromptHistory(for serviceURL: String, sessionIndex: Int) {
        guard let history = tabPromptHistories[serviceURL]?[sessionIndex] else { return }
        tabPromptHistories[serviceURL]?[sessionIndex] = Self.trimmedPromptHistory(history)
    }

    private func trimAllPromptHistories() {
        for serviceURL in tabPromptHistories.keys {
            guard let sessionMap = tabPromptHistories[serviceURL] else { continue }
            for sessionIndex in sessionMap.keys {
                trimPromptHistory(for: serviceURL, sessionIndex: sessionIndex)
            }
        }
    }

    func clearPromptHistory(for serviceURL: String, sessionIndex: Int) {
        tabPromptHistories[serviceURL]?.removeValue(forKey: sessionIndex)
    }

    func deletePromptHistoryEntry(_ entry: PromptHistoryEntry, for serviceURL: String, sessionIndex: Int) {
        guard var history = tabPromptHistories[serviceURL]?[sessionIndex] else { return }
        if let idx = history.firstIndex(of: entry) {
            history.remove(at: idx)
            tabPromptHistories[serviceURL]?[sessionIndex] = history
        }
    }

    func isPromptHistoryEnabled(for serviceURL: String, sessionIndex: Int) -> Bool {
        guard Settings.shared.enablePromptHistory else {
            return false
        }
        if let override = tabPromptHistoryEnabledOverrides[serviceURL]?[sessionIndex] {
            return override
        }
        return true
    }

    func setPromptHistoryEnabled(_ enabled: Bool, for serviceURL: String, sessionIndex: Int) {
        if tabPromptHistoryEnabledOverrides[serviceURL] == nil {
            tabPromptHistoryEnabledOverrides[serviceURL] = [:]
        }
        tabPromptHistoryEnabledOverrides[serviceURL]?[sessionIndex] = enabled
        if let service = services.first(where: { $0.url == serviceURL }),
           let webView = webviewsByID[service.id]?[sessionIndex] {
            pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
        }
    }

    /// Whether the composer should show the recording indicator for this session.
    func shouldShowRecordingIndicator(for service: Service, sessionIndex: Int) -> Bool {
        Settings.shared.promptRecordingIndicatorStyle != .off
            && service.preservePrompt
            && isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIndex)
    }

    func pushRecordingIndicatorState(to webView: WKWebView) {
        guard let (service, sessionIndex) = findServiceAndSession(for: webView) else { return }
        pushRecordingIndicatorState(to: webView, service: service, sessionIndex: sessionIndex)
    }

    func pushRecordingIndicatorState(to webView: WKWebView, service: Service, sessionIndex: Int) {
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
        let js = """
        window.__quiperRecordingIndicatorStyle = "\(style)";
        window.__quiperRecordingEnabled = \(enabled ? "true" : "false");
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

        let text = payload["text"] as? String ?? ""
        let isContentEditable = payload["isContentEditable"] as? Bool ?? false
        let start = payload["start"] as? Int ?? 0
        let end = payload["end"] as? Int ?? 0
        let wasSent = payload["wasSent"] as? Bool ?? false
        let wasSentText = payload["wasSentText"] as? String ?? ""
        let clearTypeForLog = payload["clearType"] as? String ?? "submit"

        NSLog("[Quiper] [Payload] Received input state payload: textLength=\(text.count), wasSent=\(wasSent), sentTextLength=\(wasSentText.count), clearType=\(clearTypeForLog)")

        guard let webView = message.webView,
              let (service, sessionIndex) = findServiceAndSession(for: webView) else {
            NSLog("[Quiper] [Error] webView or service/sessionIndex not found in mapping")
            return
        }

        NSLog("[Quiper] [State] Target service: \(service.name), sessionIndex: \(sessionIndex), preservePrompt: \(service.preservePrompt)")

        guard service.preservePrompt else {
            return
        }

        if wasSent {
            let clearType = payload["clearType"] as? String ?? "submit"
            var shouldRecord = false
            if clearType == "submit" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSubmit
            } else if clearType == "cmdBackspace" {
                shouldRecord = Settings.shared.promptHistoryRecordOnCmdBackspace
            } else if clearType == "selectionClear" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSelectionClear
            }
            
            NSLog("[Quiper] [History] wasSent is true. Text length: \(wasSentText.count), clearType: \(clearType), shouldRecord: \(shouldRecord)")
            
            if shouldRecord {
                let trimmed = wasSentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 && isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIndex) {
                    let newEntry = PromptHistoryEntry(text: wasSentText, timestamp: Date())
                    addPromptHistoryEntry(newEntry, for: service.url, sessionIndex: sessionIndex)
                    acknowledgePromptSaved(in: webView, service: service, sessionIndex: sessionIndex)
                    NSLog("[Quiper] [History] Successfully added entry to session \(sessionIndex) prompt history")
                    self.delegate?.inputStateRequestSave()
                } else {
                    NSLog("[Quiper] [History] Entry ignored. Trimmed length: \(trimmed.count), enabled: \(isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIndex))")
                }
            }
        }

        let inputState = TabInputState(text: text, isContentEditable: isContentEditable, start: start, end: end)
        setTabInputState(inputState, for: service.url, sessionIndex: sessionIndex)
        
        if wasSent {
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
        let text = payload["text"] as? String ?? ""
        let isContentEditable = payload["isContentEditable"] as? Bool ?? false
        let start = payload["start"] as? Int ?? 0
        let end = payload["end"] as? Int ?? 0
        let wasSent = payload["wasSent"] as? Bool ?? false
        let wasSentText = payload["wasSentText"] as? String ?? ""
        
        guard service.preservePrompt else {
            return
        }

        if wasSent {
            let clearType = payload["clearType"] as? String ?? "submit"
            var shouldRecord = false
            if clearType == "submit" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSubmit
            } else if clearType == "cmdBackspace" {
                shouldRecord = Settings.shared.promptHistoryRecordOnCmdBackspace
            } else if clearType == "selectionClear" {
                shouldRecord = Settings.shared.promptHistoryRecordOnSelectionClear
            }
            
            if shouldRecord {
                let trimmed = wasSentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 && isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIndex) {
                    let newEntry = PromptHistoryEntry(text: wasSentText, timestamp: Date())
                    addPromptHistoryEntry(newEntry, for: service.url, sessionIndex: sessionIndex)
                }
            }
        }

        let inputState = TabInputState(text: text, isContentEditable: isContentEditable, start: start, end: end)
        setTabInputState(inputState, for: service.url, sessionIndex: sessionIndex)
    }
    #endif

    @objc private func promptHistoryLimitChangedNotification(_ notification: Notification) {
        trimAllPromptHistories()
    }

    private func makeInputStartScript() -> WKUserScript {
        let source = """
        (function() {
            if (window.__quiperInputStartInstalled) return;
            window.__quiperInputStartInstalled = true;

            function interceptProperty(proto, prop) {
                try {
                    const descriptor = Object.getOwnPropertyDescriptor(proto, prop);
                    if (!descriptor) return;
                    const originalSet = descriptor.set;
                    if (!originalSet) return;
                    descriptor.set = function(val) {
                        originalSet.call(this, val);
                        try {
                            this.dispatchEvent(new CustomEvent('quiper-value-set', { detail: { value: val } }));
                        } catch(e) {}
                    };
                    Object.defineProperty(proto, prop, descriptor);
                } catch (e) {
                    console.error("Quiper: failed to intercept " + prop, e);
                }
            }
            interceptProperty(HTMLTextAreaElement.prototype, 'value');
            interceptProperty(HTMLInputElement.prototype, 'value');
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private func makeInputStateTrackerScript(for service: Service) -> WKUserScript {
        let selector = Settings.shared.promptInputSelector(for: service)
        let escapedSelector = selector
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            
        let source = """
        (function() {
            if (window.__quiperInputTrackerInstalled) return;
            window.__quiperInputTrackerInstalled = true;
            window.__quiperInputTrackerActive = false;
            if (typeof window.__quiperRecordingEnabled !== 'boolean') {
                window.__quiperRecordingEnabled = false;
            }

            const selector = "\(escapedSelector)";
            window.__quiperLatestTypedText = "";
            window.__quiperLastInputWasTrustedClear = false;
            if (typeof window.__quiperRecordingIndicatorStyle !== 'string') {
                window.__quiperRecordingIndicatorStyle = "dashed";
            }
            let indicatorOverlay = null;
            let layoutInterval = null;
            let indicatedElement = null;
            const ARC_LAYER_COUNT = 18;
            const ARC_MAX_LEN = 18;
            const ARC_MIN_LEN = 2.5;
            const ARC_MIN_OPACITY = 0.04;
            const ARC_MAX_OPACITY = 0.46;
            const ARC_SPIN_SECONDS = 5;

            function ensureRecordingStyles() {
                if (document.getElementById('__quiper-recording-style')) return;
                const style = document.createElement('style');
                style.id = '__quiper-recording-style';
                const parts = [
                    '#__quiper-recording-glow {',
                    '  position: fixed;',
                    '  pointer-events: none;',
                    '  z-index: 2147483646;',
                    '  display: none;',
                    '  overflow: visible;',
                    '}',
                    '#__quiper-recording-glow svg {',
                    '  display: block;',
                    '  overflow: visible;',
                    '}',
                    '#__quiper-recording-glow rect {',
                    '  fill: none;',
                    '  stroke-linecap: round;',
                    '}',
                    '#__quiper-recording-glow .__quiper-recording-border {',
                    '  display: none;',
                    '  stroke: rgba(148, 148, 148, 0.35);',
                    '  stroke-width: 4;',
                    '  stroke-dasharray: 2 3;',
                    '}',
                    '#__quiper-recording-glow[data-style="dashed"] .__quiper-recording-border {',
                    '  display: block;',
                    '  animation: __quiper-recording-border-motion 2s linear infinite;',
                    '}',
                    '@keyframes __quiper-recording-border-motion {',
                    '  from { stroke-dashoffset: 0; }',
                    '  to { stroke-dashoffset: 5; }',
                    '}',
                    '@keyframes __quiper-recording-border-bounce {',
                    '  0% {',
                    '    stroke: rgba(148, 148, 148, 0.35);',
                    '    stroke-width: 4;',
                    '    stroke-dasharray: 2 3;',
                    '    animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);',
                    '  }',
                    '  23% {',
                    '    stroke: rgba(132, 166, 198, 0.72);',
                    '    stroke-width: 6;',
                    '    stroke-dasharray: 3 2;',
                    '    animation-timing-function: linear;',
                    '  }',
                    '  33% {',
                    '    stroke: rgba(132, 166, 198, 0.72);',
                    '    stroke-width: 6;',
                    '    stroke-dasharray: 3 2;',
                    '    animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);',
                    '  }',
                    '  100% {',
                    '    stroke: rgba(148, 148, 148, 0.35);',
                    '    stroke-width: 4;',
                    '    stroke-dasharray: 2 3;',
                    '  }',
                    '}',
                    '#__quiper-recording-glow[data-style="dashed"].__quiper-prompt-saved .__quiper-recording-border {',
                    '  animation: __quiper-recording-border-motion 2s linear infinite, __quiper-recording-border-bounce 780ms linear 1;',
                    '}',
                    '#__quiper-recording-glow .__quiper-glow-arc {',
                    '  display: none;',
                    '}',
                    '#__quiper-recording-glow .__quiper-save-ripple {',
                    '  display: none;',
                    '  stroke: rgba(96, 165, 250, 0.92);',
                    '  stroke-width: 2;',
                    '  opacity: 0;',
                    '  transform-box: fill-box;',
                    '  transform-origin: center;',
                    '}',
                    '#__quiper-recording-glow[data-style="glow"] .__quiper-save-ripple {',
                    '  display: block;',
                    '}',
                    '@keyframes __quiper-prompt-saved-ripple {',
                    '  from { opacity: 0.92; transform: scale(1); }',
                    '  to { opacity: 0; transform: scale(var(--__quiper-ripple-scale-x, 1), var(--__quiper-ripple-scale-y, 1)); }',
                    '}',
                    '#__quiper-recording-glow[data-style="glow"].__quiper-prompt-saved .__quiper-save-ripple {',
                    '  animation: __quiper-prompt-saved-ripple 520ms cubic-bezier(0.16, 1, 0.3, 1);',
                    '}',
                    '@media (prefers-reduced-motion: reduce) {',
                    '  #__quiper-recording-glow .__quiper-recording-border,',
                    '  #__quiper-recording-glow .__quiper-glow-arc {',
                    '    animation: none !important;',
                    '  }',
                    '  #__quiper-recording-glow .__quiper-save-ripple {',
                    '    animation: none !important;',
                    '    opacity: 0 !important;',
                    '  }',
                    '}'
                ];
                for (let i = 0; i < ARC_LAYER_COUNT; i++) {
                    const t = ARC_LAYER_COUNT === 1 ? 1 : i / (ARC_LAYER_COUNT - 1);
                    const ease = t * t;
                    const len = ARC_MAX_LEN - t * (ARC_MAX_LEN - ARC_MIN_LEN);
                    const base = -(ARC_MAX_LEN - len) / 2;
                    const opacity = ARC_MIN_OPACITY + ease * (ARC_MAX_OPACITY - ARC_MIN_OPACITY);
                    const width = 2.05 - t * 0.55;
                    parts.push(
                        '@keyframes __quiper-recording-spin-' + i + ' {',
                        '  from { stroke-dashoffset: ' + base.toFixed(3) + '; }',
                        '  to { stroke-dashoffset: ' + (base - 100).toFixed(3) + '; }',
                        '}',
                        '#__quiper-recording-glow[data-style="glow"] .__quiper-arc-' + i + ' {',
                        '  display: block;',
                        '  stroke: rgba(96, 165, 250, ' + opacity.toFixed(3) + ');',
                        '  stroke-width: ' + width.toFixed(2) + ';',
                        '  stroke-dasharray: ' + len.toFixed(2) + ' ' + (100 - len).toFixed(2) + ';',
                        '  animation: __quiper-recording-spin-' + i + ' ' + ARC_SPIN_SECONDS + 's linear infinite;',
                        '}'
                    );
                }
                const blurUntil = Math.min(6, ARC_LAYER_COUNT - 1);
                for (let i = 0; i < blurUntil; i++) {
                    const blur = (0.85 * (1 - i / blurUntil)).toFixed(2);
                    parts.push(
                        '#__quiper-recording-glow .__quiper-arc-' + i + ' {',
                        '  filter: blur(' + blur + 'px);',
                        '}'
                    );
                }
                style.textContent = parts.join('\\n');
                (document.head || document.documentElement).appendChild(style);
            }

            function ensureIndicatorOverlay() {
                ensureRecordingStyles();
                if (indicatorOverlay && indicatorOverlay.isConnected) return indicatorOverlay;
                indicatorOverlay = document.createElement('div');
                indicatorOverlay.id = '__quiper-recording-glow';
                indicatorOverlay.setAttribute('aria-hidden', 'true');
                const svgNamespace = 'http://www.w3.org/2000/svg';
                const svg = document.createElementNS(svgNamespace, 'svg');
                for (let i = 0; i < ARC_LAYER_COUNT; i++) {
                    const arc = document.createElementNS(svgNamespace, 'rect');
                    arc.setAttribute('class', '__quiper-glow-arc __quiper-arc-' + i);
                    arc.setAttribute('pathLength', '100');
                    svg.appendChild(arc);
                }
                const saveRipple = document.createElementNS(svgNamespace, 'rect');
                saveRipple.setAttribute('class', '__quiper-save-ripple');
                svg.appendChild(saveRipple);
                const recordingBorder = document.createElementNS(svgNamespace, 'rect');
                recordingBorder.setAttribute('class', '__quiper-recording-border');
                recordingBorder.setAttribute('pathLength', '300');
                svg.appendChild(recordingBorder);
                indicatorOverlay.appendChild(svg);
                const root = document.documentElement || document.body;
                if (root) root.appendChild(indicatorOverlay);
                return indicatorOverlay;
            }

            function stopIndicatorTracking() {
                if (layoutInterval) {
                    clearInterval(layoutInterval);
                    layoutInterval = null;
                }
                if (indicatorOverlay) {
                    indicatorOverlay.style.display = 'none';
                    indicatorOverlay.classList.remove('__quiper-prompt-saved');
                }
                indicatedElement = null;
            }

            function recordingIndicatorStyle() {
                const style = window.__quiperRecordingIndicatorStyle;
                return style === 'glow' || style === 'dashed' ? style : 'off';
            }

            function parseBorderRadius(el, width, height) {
                let rx = 12;
                try {
                    const cs = window.getComputedStyle(el);
                    if (cs && cs.borderRadius) {
                        const first = String(cs.borderRadius).split(' ')[0];
                        const n = parseFloat(first);
                        if (!isNaN(n)) {
                            rx = first.indexOf('%') >= 0 ? (n / 100) * Math.min(width, height) : n;
                        }
                    }
                } catch (e) {}
                return Math.max(0, Math.min(rx + 4, width / 2, height / 2));
            }

            function positionIndicatorOverlay() {
                const indicatorStyle = recordingIndicatorStyle();
                if (!window.__quiperRecordingEnabled || indicatorStyle === 'off') {
                    stopIndicatorTracking();
                    return;
                }
                const el = selector ? document.querySelector(selector) : null;
                if (!el) {
                    if (indicatorOverlay) indicatorOverlay.style.display = 'none';
                    indicatedElement = null;
                    return;
                }
                const ring = ensureIndicatorOverlay();
                if (!ring) return;
                const r = el.getBoundingClientRect();
                if (r.width < 2 || r.height < 2 || (r.bottom < 0 && r.top < 0)) {
                    ring.style.display = 'none';
                    return;
                }
                const pad = 4;
                const w = Math.max(8, Math.round(r.width + pad * 2));
                const h = Math.max(8, Math.round(r.height + pad * 2));
                const inset = 1.5;
                const rx = parseBorderRadius(el, w, h);
                const svg = ring.querySelector('svg');
                const rects = ring.querySelectorAll('rect');
                if (!svg || !rects.length) return;

                if (ring.dataset.style !== indicatorStyle) {
                    ring.classList.remove('__quiper-prompt-saved');
                    ring.dataset.style = indicatorStyle;
                }
                ring.style.display = 'block';
                ring.style.left = Math.round(r.left - pad) + 'px';
                ring.style.top = Math.round(r.top - pad) + 'px';
                ring.style.width = w + 'px';
                ring.style.height = h + 'px';
                svg.setAttribute('width', String(w));
                svg.setAttribute('height', String(h));
                svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);

                const rw = Math.max(1, w - inset * 2);
                const rh = Math.max(1, h - inset * 2);
                const rectRx = Math.min(rx, rw / 2, rh / 2);
                rects.forEach(function(rect) {
                    rect.setAttribute('x', String(inset));
                    rect.setAttribute('y', String(inset));
                    rect.setAttribute('width', String(rw));
                    rect.setAttribute('height', String(rh));
                    rect.setAttribute('rx', String(rectRx));
                    rect.setAttribute('ry', String(rectRx));
                });
                const saveRipple = ring.querySelector('.__quiper-save-ripple');
                if (saveRipple) {
                    const expansion = 4;
                    saveRipple.style.setProperty('--__quiper-ripple-scale-x', String((rw + expansion * 2) / rw));
                    saveRipple.style.setProperty('--__quiper-ripple-scale-y', String((rh + expansion * 2) / rh));
                }
                indicatedElement = el;
            }

            function startIndicatorTracking() {
                positionIndicatorOverlay();
                // Layout sync only (composer moves/resizes). Indicator motion is CSS-only.
                if (layoutInterval) return;
                layoutInterval = setInterval(positionIndicatorOverlay, 250);
            }

            function updateRecordingIndicator() {
                if (!window.__quiperRecordingEnabled || recordingIndicatorStyle() === 'off') {
                    stopIndicatorTracking();
                    return;
                }
                startIndicatorTracking();
            }

            function acknowledgePromptSaved() {
                if (!window.__quiperRecordingEnabled) return;

                positionIndicatorOverlay();
                const ring = indicatorOverlay;
                if (!ring || !ring.isConnected || ring.style.display !== 'block') return;

                ring.classList.remove('__quiper-prompt-saved');
                void ring.offsetWidth;
                ring.classList.add('__quiper-prompt-saved');
            }

            window.__quiperUpdateRecordingIndicator = updateRecordingIndicator;
            window.__quiperAcknowledgePromptSaved = acknowledgePromptSaved;
            window.addEventListener('resize', function() {
                if (window.__quiperRecordingEnabled) positionIndicatorOverlay();
            }, true);
            window.addEventListener('scroll', function() {
                if (window.__quiperRecordingEnabled) positionIndicatorOverlay();
            }, true);


            function getContentEditableSelection(el) {
                try {
                    const selection = window.getSelection();
                    if (!selection.rangeCount) return { start: 0, end: 0, debug: "no rangeCount" };
                    const range = selection.getRangeAt(0);
                    
                    if (!el.contains(range.startContainer)) {
                        return { start: 0, end: 0, debug: "el does not contain startContainer" };
                    }
                    
                    const preCaretRange = range.cloneRange();
                    preCaretRange.selectNodeContents(el);
                    preCaretRange.setEnd(range.startContainer, range.startOffset);
                    const startOffset = preCaretRange.toString().length;
                    preCaretRange.setEnd(range.endContainer, range.endOffset);
                    const endOffset = preCaretRange.toString().length;
                    return { start: startOffset, end: endOffset, debug: "ok" };
                } catch (e) {
                    console.error("Quiper: error getting contenteditable selection", e);
                    return { start: 0, end: 0, debug: "exception: " + e.message };
                }
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

            function getElementState(el) {
                if (!el) return null;
                const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                if (isContentEditable) {
                    const sel = getContentEditableSelection(el);
                    const text = el.innerText || "";
                    return {
                        text: text,
                        isContentEditable: true,
                        start: typeof sel.start === 'number' ? sel.start : 0,
                        end: typeof sel.end === 'number' ? sel.end : 0,
                        debug: sel.debug || ""
                    };
                } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                    let start = 0;
                    let end = 0;
                    try {
                        start = typeof el.selectionStart === 'number' ? el.selectionStart : 0;
                        end = typeof el.selectionEnd === 'number' ? el.selectionEnd : 0;
                    } catch (e) {
                        // ignore if selection is not supported by input type
                    }
                    const text = el.value || "";
                    return {
                        text: text,
                        isContentEditable: false,
                        start: start,
                        end: end,
                        debug: "input"
                    };
                }
                return null;
            }

            function getTargetElement() {
                if (!selector) return null;
                return document.querySelector(selector);
            }

            let lastSentText = null;
            let lastSentStart = null;
            let lastSentEnd = null;

            function setPendingClearType(clearType) {
                window.__quiperLastClearType = clearType;
            }

            function clearPendingClearType() {
                window.__quiperLastClearType = null;
            }

            function consumePendingClearType(defaultClearType) {
                const clearType = window.__quiperLastClearType || defaultClearType;
                clearPendingClearType();
                return clearType;
            }

            function sendState(immediate) {
                if (window.__quiperInputTrackerActive === false) return;
                const el = getTargetElement();
                if (!el) return;
                
                const hasFocus = document.hasFocus();
                const state = getElementState(el);
                if (!state) return;

                let start = state.start;
                let end = state.end;
                if (!hasFocus) {
                    start = lastSentStart !== null ? lastSentStart : state.start;
                    end = lastSentEnd !== null ? lastSentEnd : state.end;
                }

                if (!window.__quiperForceRecordPrompt && state.text && state.text.trim() !== "") {
                    window.__quiperLatestTypedText = state.text;
                }

                let wasSent = false;
                let wasSentText = "";
                let clearType = "submit";
                
                if (window.__quiperForceRecordPrompt && window.__quiperLatestTypedText && window.__quiperLatestTypedText.trim() !== "") {
                    wasSent = true;
                    wasSentText = window.__quiperLatestTypedText;
                    clearType = consumePendingClearType("submit");
                    window.__quiperForceRecordPrompt = false;
                    window.__quiperLatestTypedText = "";
                } else {
                    const isTextEmpty = !state.text || state.text.trim() === "";
                    if (isTextEmpty && window.__quiperLatestTypedText && window.__quiperLatestTypedText.trim() !== "") {
                        wasSent = true;
                        wasSentText = window.__quiperLatestTypedText;
                        clearType = consumePendingClearType("submit");
                        window.__quiperLatestTypedText = "";
                    }
                }

                if (!wasSent && state.text === lastSentText && start === lastSentStart && end === lastSentEnd) {
                    return;
                }

                lastSentText = state.text;
                lastSentStart = start;
                lastSentEnd = end;

                const payload = {
                    text: state.text,
                    isContentEditable: state.isContentEditable,
                    start: start,
                    end: end,
                    wasSent: wasSent,
                    wasSentText: wasSentText,
                    clearType: clearType,
                    debug: state.debug || ""
                };

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quiperInputState) {
                    window.webkit.messageHandlers.quiperInputState.postMessage(payload);
                }
            }

            let debounceTimer = null;
            function debouncedSend() {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    sendState(false);
                }, 150);
            }

            // User interaction tracking & clear type detection
            window.__quiperLastInteractionTime = 0;
            let selectionLengthBeforeInput = 0;
            let textLengthBeforeInput = 0;
            let textBeforeInput = "";
            let selectedTextBeforeInput = "";
            let hasCapturedBeforeState = false;
            let inputOccurredSinceLastKeydown = false;
            window.__quiperLastClearType = null;
            window.__quiperForceRecordPrompt = false;
            
            function updateInteractionTime(e) {
                window.__quiperLastInteractionTime = Date.now();
                window.__quiperHasSavedSelection = false;
            }
            document.addEventListener('mousedown', updateInteractionTime, true);
            document.addEventListener('touchstart', updateInteractionTime, true);
            
            function captureBeforeState() {
                if (hasCapturedBeforeState) return;
                const el = getTargetElement();
                if (!el) return;
                const state = getElementState(el);
                if (!state) return;
                textBeforeInput = state.text || "";
                textLengthBeforeInput = textBeforeInput.length;
                if (state.isContentEditable) {
                    const sel = window.getSelection();
                    selectedTextBeforeInput = sel ? sel.toString() : "";
                    selectionLengthBeforeInput = selectedTextBeforeInput.length;
                } else {
                    const start = (typeof el.selectionStart === 'number') ? el.selectionStart : 0;
                    const end = (typeof el.selectionEnd === 'number') ? el.selectionEnd : 0;
                    selectionLengthBeforeInput = (end - start) || 0;
                    selectedTextBeforeInput = el.value ? el.value.substring(start, end) : "";
                }
                hasCapturedBeforeState = true;
            }

            document.addEventListener('keydown', (e) => {
                updateInteractionTime(e);
                inputOccurredSinceLastKeydown = false;
                captureBeforeState();
                const el = getTargetElement();
                if (el && e.isTrusted) {
                    const isDeleteKey = e.key === 'Backspace' || e.key === 'Delete';
                    const isCmd = e.metaKey || e.ctrlKey;
                    
                    if (isDeleteKey) {
                        if (isCmd) {
                            setPendingClearType("cmdBackspace");
                        } else if (selectionLengthBeforeInput > 0) {
                            setPendingClearType("selectionClear");
                        } else {
                            setPendingClearType("normalDelete");
                        }
                    } else if ((e.key === 'x' || e.key === 'X') && isCmd) {
                        setPendingClearType("selectionClear");
                    }
                }
            }, true);

            document.addEventListener('keyup', (e) => {
                if (!inputOccurredSinceLastKeydown) {
                    clearPendingClearType();
                }
                inputOccurredSinceLastKeydown = false;
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('mouseup', (e) => {
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('cut', (e) => {
                if (e && e.isTrusted) {
                    setPendingClearType("selectionClear");
                }
            }, true);

            document.addEventListener('beforeinput', (e) => {
                if (e && e.isTrusted) {
                    captureBeforeState();
                    if (e.inputType && e.inputType.startsWith('delete')) {
                        if (window.__quiperLastClearType === null) {
                            setPendingClearType(selectionLengthBeforeInput > 0 ? "selectionClear" : "normalDelete");
                        }
                    }
                }
            }, true);

            document.addEventListener('input', (e) => {
                const el = getTargetElement();
                if (el && (el === e.target || el.contains(e.target))) {
                    inputOccurredSinceLastKeydown = true;
                    const state = getElementState(el);
                    if (state) {
                        const normSel = selectedTextBeforeInput.replace(/\\s/g, '');
                        const normFull = textBeforeInput.replace(/\\s/g, '');
                        const wasSelectAll = normSel.length > 0 && (normSel === normFull || (normFull.length > 0 && normSel.length / normFull.length >= 0.95));
                        
                        if (wasSelectAll && textBeforeInput && textBeforeInput.trim() !== "") {
                            setPendingClearType("selectionClear");
                            window.__quiperLatestTypedText = textBeforeInput;
                            window.__quiperForceRecordPrompt = true;
                            sendState(true);
                            selectedTextBeforeInput = "";
                            selectionLengthBeforeInput = 0;
                            textBeforeInput = "";
                        }
                        
                        if (state.text && state.text.trim() !== "") {
                            window.__quiperLatestTypedText = state.text;
                            clearPendingClearType();
                        }
                        
                        const isTextEmpty = !state.text || state.text.trim() === "";
                        if (isTextEmpty) {
                            sendState(true);
                        } else {
                            debouncedSend();
                        }
                    }
                }
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('selectionchange', () => {
                const el = getTargetElement();
                if (el && (document.activeElement === el || el.contains(document.activeElement))) {
                    const lastInteract = window.__quiperLastInteractionTime || 0;
                    if (Date.now() - lastInteract < 500) {
                        debouncedSend();
                    } else if (window.__quiperHasSavedSelection) {
                        const current = getElementState(el);
                        if (current && (current.start !== window.__quiperSavedStart || current.end !== window.__quiperSavedEnd)) {
                            if (current.isContentEditable) {
                                setContentEditableSelection(el, window.__quiperSavedStart, window.__quiperSavedEnd);
                            } else {
                                el.setSelectionRange(window.__quiperSavedStart, window.__quiperSavedEnd);
                            }
                        }
                    }
                }
            });

            window.addEventListener('blur', () => {
                sendState(true);
            });

            window.addEventListener('pagehide', () => {
                sendState(true);
            });

            // Listen to value updates programmatically intercepted by the document start script
            document.addEventListener('quiper-value-set', (e) => {
                const el = getTargetElement();
                if (el && (e.target === el || el.contains(e.target))) {
                    window.__quiperLastInputWasTrustedClear = false;
                    sendState(true);
                }
            }, true);

            // Setup MutationObserver on document body to find target element if it's contenteditable
            let observer = null;
            function setupMutationObserver() {
                try {
                    if (observer) observer.disconnect();
                    observer = new MutationObserver((mutations) => {
                        let structureChanged = false;
                        for (const m of mutations) {
                            if (m.type === 'childList') {
                                structureChanged = true;
                                break;
                            }
                        }
                        // SPA remounts replace the composer; keep the indicator attached.
                        if (structureChanged || (indicatedElement && !indicatedElement.isConnected)) {
                            if (window.__quiperRecordingEnabled) {
                                updateRecordingIndicator();
                            }
                        }
                        const el = getTargetElement();
                        if (el) {
                            const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                            if (isContentEditable) {
                                sendState(true);
                            }
                        }
                    });
                    observer.observe(document.body, { childList: true, characterData: true, subtree: true });
                    updateRecordingIndicator();
                } catch (e) {
                    console.error("Quiper: failed to setup MutationObserver", e);
                }
            }
            if (document.body) {
                setupMutationObserver();
            } else {
                document.addEventListener('DOMContentLoaded', setupMutationObserver);
            }
            // Re-apply if Swift already pushed recording state before this script finished installing.
            updateRecordingIndicator();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quiperInputTrackerReady) {
                window.webkit.messageHandlers.quiperInputTrackerReady.postMessage({});
            }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
    
    func getOrCreateWebView(for service: Service, sessionIndex: Int, dragArea: NSView?, targetURL: String? = nil, restoredTitle: String? = nil, loadImmediately: Bool = true) -> WKWebView {
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
        let wrapperView = NSView(frame: frame)
        wrapperView.autoresizingMask = []
        wrapperView.wantsLayer = true
        wrapperView.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        updateMaskedCorners(for: wrapperView)
        wrapperView.layer?.masksToBounds = true
        wrapperView.isHidden = true
        
        let isUnlocked = !service.isEncrypted || EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        
        // WebView inside Wrapper (ephemeral/non-persistent if locked, persistent if unlocked)
        let webview = createWebViewInstance(for: service, sessionIndex: sessionIndex, bounds: wrapperView.bounds, isPersistent: isUnlocked)
        wrapperView.addSubview(webview)

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
        
        urlsByWebView[ObjectIdentifier(webview)] = service.url
        
        let token = ObjectIdentifier(webview)
        retainTitle(restoredTitle, for: webview)
        initialLoadAwaitingFocus.insert(token)
        
        // Clean up any existing LockOverlayView from previous states
        for subview in wrapperView.subviews {
            if subview is LockOverlayView {
                subview.removeFromSuperview()
            }
        }
        
        // Load initial URL with encryption check
        if service.isEncrypted {
            if EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                if loadImmediately {
                    let activeURLString = targetURL ?? service.url
                    if let url = URL(string: activeURLString) {
                        if url.isFileURL {
                            webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                        } else {
                            webview.load(URLRequest(url: url))
                        }
                    }
                } else {
                    pendingLazyLoadURLs[token] = targetURL ?? service.url
                }
            } else {
                // Show LockOverlayView on top of wrapper
                let serviceId = service.id
                let serviceUrl = targetURL ?? service.url
                
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
                            
                            let needsMigration = service.isEncrypted
                                && EncryptedVolumeManager.shared.bundleExists(for: serviceId)
                                && !service.usesDiskutilSparseBundle
                            if needsMigration {
                                let shouldMigrate = await SparseBundleMigrationManager.shared.presentPerEngineMigrationPrompt(
                                    engineName: service.name,
                                    relativeTo: wrapperView.window
                                )
                                if shouldMigrate {
                                    overlay.updateStatus("Upgrading secure storage...")
                                    try await SparseBundleMigrationManager.shared.migrateEngine(
                                        serviceID: serviceId,
                                        passphrase: key,
                                        context: context
                                    )
                                }
                            }
                            
                            overlay.updateStatus("Mounting encrypted volume...")
                            if !EncryptedVolumeManager.shared.bundleExists(for: serviceId) {
                                NSLog("[LockOverlay] Creating new volume")
                                try await EncryptedVolumeManager.shared.createVolume(for: serviceId, passphrase: key)
                            }
                            NSLog("[LockOverlay] Mounting volume")
                            try await EncryptedVolumeManager.shared.mountVolume(for: serviceId, passphrase: key)
                            
                            overlay.updateStatus("Loading secure session...")
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            
                            // Remove non-persistent webview and clean observers
                            webview.removeObserver(self, forKeyPath: "title")
                            webview.removeObserver(self, forKeyPath: "loading")
                            let oldToken = ObjectIdentifier(webview)
                            self.initialLoadAwaitingFocus.remove(oldToken)
                            self.urlsByWebView.removeValue(forKey: oldToken)
                            webview.configuration.userContentController.removeAllUserScripts()
                            webview.removeFromSuperview()
                            
                            // Remove lock overlay
                            for subview in wrapperView.subviews {
                                if subview is LockOverlayView {
                                    subview.removeFromSuperview()
                                }
                            }
                            
                            // Create the real persistent webview
                            let realWebView = self.createWebViewInstance(for: service, sessionIndex: sessionIndex, bounds: wrapperView.bounds, isPersistent: true)
                            wrapperView.addSubview(realWebView)
                            
                            // Update maps
                            self.webviewsByID[service.id]?[sessionIndex] = realWebView
                            self.urlsByWebView[ObjectIdentifier(realWebView)] = service.url
                            
                             // Load real URL
                             var targetURLString = serviceUrl
                             if Settings.shared.tabSurvivalPolicy != .never {
                                 let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceId).appendingPathComponent("quiper_tabs.json")
                                 if let data = try? Data(contentsOf: stateURL),
                                    let state = try? JSONDecoder().decode(MainWindowController.SecureTabState.self, from: data) {
                                     if let saved = state.openTabs[sessionIndex] {
                                         targetURLString = saved
                                     }
                                     if let secureInputs = state.tabInputs {
                                         self.restoreTabInputStates([service.url: secureInputs])
                                     }
                                     if let secureHistories = state.tabPromptHistories {
                                         self.restoreTabPromptHistories([service.url: secureHistories])
                                     }
                                     if let secureOverrides = state.tabPromptHistoryEnabledOverrides {
                                         self.restoreTabPromptHistoryOverrides([service.url: secureOverrides])
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
                let activeURLString = targetURL ?? service.url
                if let url = URL(string: activeURLString) {
                    if url.isFileURL {
                        webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                    } else {
                        webview.load(URLRequest(url: url))
                    }
                }
            } else {
                pendingLazyLoadURLs[token] = targetURL ?? service.url
            }
        }
        
        return webview
    }
    
    private func createWebViewInstance(for service: Service, sessionIndex: Int, bounds: NSRect, isPersistent: Bool) -> WKWebView {
        let userContentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let isRunningTests = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
        if isPersistent && !isRunningTests {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }

        let cssToInject = Settings.shared.customCSS(for: service)
        if !cssToInject.isEmpty {
            let cssScript = """
            const style = document.createElement('style');
            style.textContent = `/* Custom CSS */
            \(cssToInject)`;
            document.head.appendChild(style);
            """
            let userScript = WKUserScript(source: cssScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
        }

        // Inject input setter interceptor script at document start
        let startScript = makeInputStartScript()
        userContentController.addUserScript(startScript)

        // Inject input state tracking user script
        let inputScript = makeInputStateTrackerScript(for: service)
        userContentController.addUserScript(inputScript)
        
        let inputHandler = InputStateScriptMessageHandler(manager: self)
        userContentController.add(inputHandler, name: "quiperInputState")
        userContentController.add(inputHandler, name: "quiperInputTrackerReady")

        let webview = WKWebView(frame: bounds, configuration: config)
        webview.setValue(false, forKey: "drawsBackground")
        webview.autoresizingMask = [.width, .height]
        webview.uiDelegate = self
        webview.navigationDelegate = self
        webview.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webview.pageZoom = zoomLevels[service.url] ?? 1.0
        
        attachNotificationBridge(to: webview, service: service, sessionIndex: sessionIndex)
        
        // Add observers
        webview.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        webview.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
        
        return webview
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
        if let targetURLString = pendingLazyLoadURLs.removeValue(forKey: token), let url = URL(string: targetURLString) {
            NSLog("[WebViewManager] Lazy loading background session webview: %@", targetURLString)
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        
        updateLayout()
    }
    
    func serviceURL(for webView: WKWebView) -> URL? {
        if let urlString = urlsByWebView[ObjectIdentifier(webView)] {
            return URL(string: urlString)
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
    
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView else { return }
        
        MainActor.assumeIsolated {
            if keyPath == "title" {
                retainTitle(webView.title, for: webView)
                delegate?.webViewDidUpdateTitle(webView.title ?? "", for: webView)
            } else if keyPath == "loading" {
                delegate?.webViewDidUpdateLoading(webView.isLoading, for: webView)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func tearDownWebView(_ webView: WKWebView) {
        // Stop any in-progress loading to signal WebKit to release the content process
        webView.stopLoading()
 
        // Nil delegates to prevent callbacks during/after deallocation
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
 
        detachNotificationBridge(from: webView)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quiperInputState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quiperInputTrackerReady")
 
        // Resume and clear any pending navigation continuation to prevent CheckedContinuation leaks
        let token = ObjectIdentifier(webView)
        if let continuation = navigationContinuations.removeValue(forKey: token) {
            continuation.resume()
        }
        initialLoadAwaitingFocus.remove(token)
        urlsByWebView.removeValue(forKey: token)
        pendingLazyLoadURLs.removeValue(forKey: token)
        lastKnownTitlesByWebView.removeValue(forKey: token)
 
        // Clean user content controller to break configuration references
        webView.configuration.userContentController.removeAllUserScripts()
 
        webView.removeObserver(self, forKeyPath: "title")
        webView.removeObserver(self, forKeyPath: "loading")
 
        // Remove the wrapper view (parent) from the view hierarchy, then the webview
        let wrapper = webView.superview
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
    
    enum DomainRoutingAction {
        case openHere
        case openNewWindow
        case openExternal
        case showPrompt
        case cancel
    }

    private func matchesPattern(targetString: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(location: 0, length: targetString.utf16.count)
        return regex.firstMatch(in: targetString, options: [], range: range) != nil
    }

    private func determineRouting(for url: URL, service: Service, serviceURL: URL) -> DomainRoutingAction {
        // 1. Same-origin check (Absolute priority: always open here)
        let targetHost = url.host?.lowercased()
        let serviceHost = serviceURL.host?.lowercased()
        if let tHost = targetHost, let sHost = serviceHost {
            if tHost == sHost {
                return .openHere
            }
            let rootServiceHost = sHost.hasPrefix("www.") ? String(sHost.dropFirst(4)) : sHost
            if tHost == rootServiceHost || tHost.hasSuffix("." + rootServiceHost) {
                return .openHere
            }
        } else if url.scheme?.lowercased() == serviceURL.scheme?.lowercased() && (url.isFileURL || url.scheme == "data") {
            return .openHere
        } else if url.isFileURL && ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return .openHere
        }
        
        let targetString = url.absoluteString
        
        // 2. Evaluate top-to-bottom routing rules
        for rule in service.routingRules {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pattern.isEmpty && matchesPattern(targetString: targetString, pattern: pattern) {
                switch rule.action {
                case .internalStay:
                    return .openHere
                case .popup:
                    return .openNewWindow
                case .prompt:
                    return .showPrompt
                case .external:
                    return .openExternal
                }
            }
        }
        
        return .openExternal
    }

    @MainActor
    private func openInPopup(url: URL, service: Service, configuration: WKWebViewConfiguration, parentWindow: NSWindow) {
        let popupWindow = ModalPopupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            parentWindow: parentWindow
        )
        popupWindow.center()
        
        let popupWebView = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
        popupWebView.autoresizingMask = [.width, .height]
        popupWebView.uiDelegate = PopupUIDelegate.shared
        
        popupWindow.observeWebViewTitle(popupWebView, fallbackTitle: service.name)
        
        popupWindow.contentView?.addSubview(popupWebView)
        popupWindow.makeKeyAndOrderFront(nil)
        
        popupWebView.load(URLRequest(url: url))
    }

    @MainActor
    private func presentRoutingPrompt(for url: URL, service: Service, webView: WKWebView, completion: @escaping @MainActor @Sendable (DomainRoutingAction, Bool) -> Void) {
        guard let window = webView.window else {
            completion(.openExternal, false)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Security & Routing"
        alert.informativeText = "How would you like to open this link?\n\(url.absoluteString)"
        
        alert.addButton(withTitle: "Open Here")
        alert.addButton(withTitle: "Open in New Window")
        alert.addButton(withTitle: "Open Externally")
        let cancelBtn = alert.addButton(withTitle: "Cancel")
        cancelBtn.keyEquivalent = "\u{1b}" // Escape key
        
        let checkbox = NSButton(checkboxWithTitle: "Remember my choice for this domain", target: nil, action: nil)
        checkbox.font = .systemFont(ofSize: 11)
        alert.accessoryView = checkbox
        
        alert.beginSheetModal(for: window) { response in
            let action: DomainRoutingAction
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
            let remember = checkbox.state == .on
            completion(action, remember)
        }
    }

    @MainActor
    private func rememberDecision(for host: String, action: DomainRoutingAction, service: Service) {
        guard !host.isEmpty else { return }
        
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == service.id }) else { return }
        
        var updated = Settings.shared.services[index]
        
        // Remove any existing rule matching this exact host (case-insensitive)
        updated.routingRules.removeAll { rule in
            rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == host.lowercased()
        }
        
        let routingAction: RoutingAction
        switch action {
        case .openHere:
            routingAction = .internalStay
        case .openNewWindow:
            routingAction = .popup
        case .openExternal:
            routingAction = .external
        default:
            return
        }
        
        let newRule = RoutingRule(pattern: host, action: routingAction)
        updated.routingRules.insert(newRule, at: 0) // Insert at top of list
        
        Settings.shared.services[index] = updated
        Settings.shared.saveSettings()
    }
    
    func tearDownAllWebViews(for service: Service) {
        guard let sessionMap = webviewsByID[service.id] else { return }
        for sessionIndex in Array(sessionMap.keys) {
            removeWebView(for: service, sessionIndex: sessionIndex)
        }
    }
}

// MARK: - WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate

private final class ModalPopupWindow: NSWindow, NSWindowDelegate {
    private var shield: InteractionShieldView?
    private weak var parentWin: NSWindow?
    private var isCleaningUp = false
    private var titleObservation: NSKeyValueObservation?
    private var fallbackTitle: String = ""
    
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
        self.fallbackTitle = fallbackTitle
        self.title = fallbackTitle
        
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, change in
            guard let self = self else { return }
            if let newTitle = change.newValue as? String, !newTitle.isEmpty {
                self.title = "\(newTitle) - \(self.fallbackTitle)"
            } else {
                self.title = self.fallbackTitle
            }
        }
    }
    
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        titleObservation?.invalidate()
        titleObservation = nil
        
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
                webView.configuration.userContentController.removeAllUserScripts()
                webView.removeFromSuperview()
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
        
        // 5. Break self-delegate cycle to allow deallocation
        self.delegate = nil
    }
    
    func windowWillClose(_ notification: Notification) {
        cleanup()
    }
}

@MainActor
fileprivate final class PopupUIDelegate: NSObject, WKUIDelegate {
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
        decisionHandler(.grant)
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
        
        let optionPressed = navigationAction.modifierFlags.contains(.option)
        var action = determineRouting(for: url, service: service, serviceURL: serviceURL)
        if action == .openExternal && optionPressed {
            action = .showPrompt
        }
        
        switch action {
        case .openHere, .openNewWindow:
            guard let parentWindow = webView.window else { return nil }
            let popupWindow = ModalPopupWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                parentWindow: parentWindow
            )
            popupWindow.center()
            
            let popupWebView = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
            popupWebView.autoresizingMask = [.width, .height]
            popupWebView.uiDelegate = PopupUIDelegate.shared
            
            popupWindow.observeWebViewTitle(popupWebView, fallbackTitle: service.name)
            popupWindow.contentView?.addSubview(popupWebView)
            popupWindow.makeKeyAndOrderFront(nil)
            
            return popupWebView
        case .openExternal:
            NSWorkspace.shared.open(url)
            return nil
        case .showPrompt:
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
                        self.openInPopup(url: url, service: service, configuration: configuration, parentWindow: parentWindow)
                    }
                case .openExternal:
                    NSWorkspace.shared.open(url)
                case .showPrompt, .cancel:
                    break
                }
            }
            return nil
        case .cancel:
            return nil
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

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let serviceURL = serviceURL(for: webView),
              let service = services.first(where: { $0.url == serviceURL.absoluteString }) else {
            decisionHandler(.allow)
            return
        }

        // Only route main frame navigations (including new windows where targetFrame is nil)
        let targetFrameIsMain = navigationAction.targetFrame?.isMainFrame ?? true
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
        var action = determineRouting(for: url, service: service, serviceURL: serviceURL)
        if action == .openExternal && optionPressed {
            action = .showPrompt
        }
        
        switch action {
        case .openHere:
            let allowWithoutAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowWithoutAppLink)
            
        case .openNewWindow:
            if let parentWindow = webView.window {
                openInPopup(url: url, service: service, configuration: webView.configuration, parentWindow: parentWindow)
            }
            decisionHandler(.cancel)
            
        case .openExternal:
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
                        self.openInPopup(url: url, service: service, configuration: webView.configuration, parentWindow: parentWindow)
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

    @objc private func webDataClearedNotification(_ notification: Notification) {
        guard let serviceID = notification.object as? UUID else { return }
        handleWebDataCleared(for: serviceID)
    }

    private func handleWebDataCleared(for serviceID: UUID) {
        NSLog("[WebViewManager] Handling web data cleared for service: %@", serviceID.uuidString)
        
        // 1. Find all active session indices for this service ID
        guard let sessionMap = webviewsByID[serviceID] else { return }
        let sessionIndices = Array(sessionMap.keys)
        
        // 2. Tear down the old webviews
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
