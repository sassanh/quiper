import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class WebViewSession: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    let id: UUID
    let serviceID: UUID
    let sessionIndex: Int
    let webView: WKWebView
    let coordinator: WebSessionCoordinator

    @Published var title: String = ""
    @Published var isLoading: Bool = false
    @Published var url: URL?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isBarCollapsed: Bool = false
    @Published var findQuery: String = ""
    @Published var findStatusText: String? = nil
    @Published var snapshot: UIImage?

    init(service: Service, sessionIndex: Int, initialURL: URL?, loadImmediately: Bool = true) {
        self.id = UUID()
        self.serviceID = service.id
        self.sessionIndex = sessionIndex
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        self.coordinator = WebSessionCoordinator(
            webView: webView,
            service: service,
            sessionIndex: sessionIndex
        )
        super.init()
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true

        installDoubleTapGesture()
        coordinator.installInputTracker()

        coordinator.onInputState = { [weak self] payload in
            self?.handleInputState(payload)
        }
        coordinator.onTitle = { [weak self] title in
            self?.title = title
            self?.onTitleChange?(title)
        }
        coordinator.onLoading = { [weak self] loading in
            self?.isLoading = loading
        }
        coordinator.onURL = { [weak self] url in
            self?.url = url
            self?.onURLChange?(url)
        }
        coordinator.onNavigationState = { [weak self] canGoBack, canGoForward in
            self?.canGoBack = canGoBack
            self?.canGoForward = canGoForward
        }
        coordinator.onRememberRoutingDecision = { [weak self] host, action in
            self?.onRememberRoutingDecision?(host, action)
        }
        coordinator.onDidFinish = { [weak self] in
            self?.restoreInputStateIfNeeded()
            self?.captureSnapshot()
        }

        installScrollObservation()

        if let initialURL {
            self.url = initialURL
            if loadImmediately {
                webView.load(URLRequest(url: initialURL))
            } else {
                pendingLoadURL = initialURL
            }
        }
    }

    private var pendingLoadURL: URL?

    private var pendingInputState: TabInputState?
    private var lastScrollY: CGFloat = 0
    private var downwardAccumulation: CGFloat = 0
    private var upwardAccumulation: CGFloat = 0
    private var scrollObservation: NSKeyValueObservation?
    private var findDebounceTask: Task<Void, Never>?
    private var findSearch = ""
    private var findCurrentIndex = 0
    private var findTotal = 0
    private var findRequestID = 0

    private static let collapseThreshold: CGFloat = 80
    private static let restoreThreshold: CGFloat = 40
    private static let scrollNoiseFloor: CGFloat = 1

    var onPromptRecorded: ((_ text: String, _ clearType: String) -> Void)?
    var onURLChange: ((URL) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onRememberRoutingDecision: ((_ host: String, _ action: RoutingAction) -> Void)?
    var onInputStateChanged: ((TabInputState) -> Void)?
    var onRequestRestoreInputState: (() -> TabInputState?)?
    var onInputStateCommitted: (() -> Void)?

    var onRingSecondTapDown: ((CGPoint) -> Void)?
    var onRingHoldBegan: (() -> Void)?
    var onRingHoldUpdate: ((CGPoint) -> Void)?
    var onRingQuickEnd: ((CGPoint) -> Void)?
    var onRingHoldEnd: ((CGPoint) -> Void)?
    var onRingCancel: (() -> Void)?
    var onSnapshot: ((UIImage?) -> Void)?

    private var ringGestureRecognizer: DoubleTapGestureRecognizer?
    private var ringTouchShield: RingTouchShield?
    private var suspendedWebViewRecognizers: [UIGestureRecognizer] = []

    /// Installs the double-tap recognizer that drives the navigation ring and
    /// disables WKWebView's built-in double-tap zoom so the two never fight. A
    /// touch shield over the page swallows the second tap so the web view never
    /// receives it (no text selection or click while the ring is open).
    private func installDoubleTapGesture() {
        disableWebViewDoubleTapZoom()

        let shield = RingTouchShield()
        shield.frame = webView.bounds
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.addSubview(shield)
        ringTouchShield = shield

        let recognizer = DoubleTapGestureRecognizer()
        recognizer.delegate = self
        recognizer.onFirstTapEnded = { [weak shield] location in
            shield?.arm(at: location)
        }
        recognizer.onSecondTapDown = { [weak self, weak shield] location in
            shield?.disarm()
            self?.onRingSecondTapDown?(location)
        }
        recognizer.onHoldBegan = { [weak self] in
            self?.onRingHoldBegan?()
        }
        recognizer.onHoldUpdate = { [weak self] location in
            self?.onRingHoldUpdate?(location)
        }
        recognizer.onQuickEnd = { [weak self] location in
            self?.onRingQuickEnd?(location)
        }
        recognizer.onHoldEnd = { [weak self] location in
            self?.onRingHoldEnd?(location)
        }
        recognizer.onCancel = { [weak self, weak shield] in
            shield?.disarm()
            self?.onRingCancel?()
        }
        webView.addGestureRecognizer(recognizer)
        ringGestureRecognizer = recognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// WKWebView handles double-tap zoom inside its own content view; disabling
    /// those recognizers leaves single-tap and scroll behavior untouched.
    private func disableWebViewDoubleTapZoom() {
        let recognizers = webView.scrollView.subviews
            .compactMap { $0.gestureRecognizers }
            .flatMap { $0 }
        for recognizer in recognizers {
            guard let tap = recognizer as? UITapGestureRecognizer,
                  tap.numberOfTapsRequired == 2 else { continue }
            tap.isEnabled = false
        }
    }

    /// Freezes the page's own gestures while the ring is open so the held
    /// finger does not scroll or select text in the web view.
    func suspendWebViewInteraction() {
        let recognizers = webView.scrollView.gestureRecognizers ?? []
        suspendedWebViewRecognizers = recognizers.filter { $0.isEnabled && $0 !== ringGestureRecognizer }
        for recognizer in suspendedWebViewRecognizers {
            recognizer.isEnabled = false
        }
    }

    func resumeWebViewInteraction() {
        for recognizer in suspendedWebViewRecognizers {
            recognizer.isEnabled = true
        }
        suspendedWebViewRecognizers = []
    }

    func handleInputState(_ payload: [String: Any]) {
        let parsed = InputStatePayload(payload)
        if parsed.wasSent,
           PromptHistoryPolicy.makeEntryIfEligible(submittedText: parsed.wasSentText) != nil {
            onPromptRecorded?(parsed.wasSentText, parsed.clearType)
        }
        let inputState = TabInputState(
            text: parsed.text,
            isContentEditable: parsed.isContentEditable,
            start: parsed.start,
            end: parsed.end
        )
        onInputStateChanged?(inputState)
        if parsed.wasSent {
            onInputStateCommitted?()
        }
    }

    func submitPrompt(_ text: String) {
        coordinator.injectAndSubmit(text)
    }

    func focusInput() {
        coordinator.focusInput(restoring: onRequestRestoreInputState?())
    }

    func setKeyboardSuppressed(_ suppressed: Bool) {
        coordinator.setKeyboardSuppressed(suppressed)
    }

    func updateService(_ service: Service) {
        coordinator.updateService(service)
    }

    /// Mirrors macOS: once the page finishes loading, re-apply the tab's saved
    /// input state (text + selection) into the composer so drafts survive reloads.
    func restoreInputStateIfNeeded() {
        guard let state = onRequestRestoreInputState?() else { return }
        let hasContent = !state.text.isEmpty || state.start != 0 || state.end != 0
        guard hasContent else { return }
        coordinator.focusInput(restoring: state)
    }

    func reload() {
        webView.reload()
    }

    func loadIfNeeded() {
        guard let pending = pendingLoadURL else { return }
        pendingLoadURL = nil
        webView.load(URLRequest(url: pending))
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }
    // MARK: - Ring previews

    /// Captures the current page content so the navigation ring can show a
    /// live preview of each tab instead of a static label card.
    func captureSnapshot(completion: ((UIImage?) -> Void)? = nil) {
        guard !isLoading, webView.url != nil else {
            completion?(nil)
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 1024
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let image else {
                completion?(nil)
                return
            }
            Task { @MainActor [weak self] in
                self?.snapshot = image
                self?.onSnapshot?(image)
                completion?(image)
            }
        }
    }

    /// Captures the current page content asynchronously and returns it, waiting
    /// (by suspending, never blocking or spinning the run loop) for WebKit to
    /// deliver the snapshot. The ring defers presentation until this returns so
    /// it opens on the exact state on screen. Bounded by a safety timeout.
    @MainActor
    func captureFreshSnapshot() async -> UIImage? {
        guard !isLoading, webView.url != nil else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 1024
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            webView.takeSnapshot(with: configuration) { result, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
        snapshot = image
        return image
    }
    // MARK: - Scroll-collapse bar

    private func installScrollObservation() {
        scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleScroll(scrollView.contentOffset.y)
            }
        }
    }

    private func handleScroll(_ y: CGFloat) {
        if y <= 0 {
            lastScrollY = y
            downwardAccumulation = 0
            upwardAccumulation = 0
            isBarCollapsed = false
            return
        }
        let delta = y - lastScrollY
        lastScrollY = y
        guard abs(delta) > Self.scrollNoiseFloor else { return }

        if isBarCollapsed {
            if delta < 0 {
                upwardAccumulation += -delta
                if upwardAccumulation >= Self.restoreThreshold {
                    downwardAccumulation = 0
                    upwardAccumulation = 0
                    isBarCollapsed = false
                }
            } else {
                upwardAccumulation = 0
            }
            return
        }

        if delta > 0 {
            downwardAccumulation += delta
            if downwardAccumulation >= Self.collapseThreshold {
                downwardAccumulation = 0
                upwardAccumulation = 0
                isBarCollapsed = true
            }
        } else {
            downwardAccumulation = max(0, downwardAccumulation + delta)
        }
    }

    func expandBar() {
        downwardAccumulation = 0
        upwardAccumulation = 0
        isBarCollapsed = false
    }

    // MARK: - Find in page

    func setFindQuery(_ query: String) {
        findQuery = query
        findDebounceTask?.cancel()
        findRequestID += 1
        findStatusText = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetFind()
            return
        }
        findDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.performFind(forward: true, newSearch: true)
        }
    }

    func stepFind(forward: Bool) {
        findDebounceTask?.cancel()
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        performFind(forward: forward, newSearch: false)
    }

    func resetFind() {
        findDebounceTask?.cancel()
        findRequestID += 1
        findSearch = ""
        findCurrentIndex = 0
        findTotal = 0
        findStatusText = nil
        webView.find("", configuration: WKFindConfiguration()) { _ in }
        webView.findInteraction?.dismissFindNavigator()
        webView.evaluateJavaScript(WebScripts.makeResetFindScript(), completionHandler: nil)
    }

    private func performFind(forward: Bool, newSearch: Bool) {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetFind()
            return
        }
        findRequestID += 1
        let requestID = findRequestID
        let escaped = WebScripts.escapeForJavaScript(trimmed)
        let countScript = WebScripts.makeFindMatchCountScript(search: escaped)
        webView.evaluateJavaScript(countScript) { [weak self] result, error in
            guard let self else { return }
            guard requestID == self.findRequestID,
                  trimmed == self.findQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            guard error == nil else {
                self.findStatusText = "No matches"
                return
            }
            let total = (result as? NSNumber)?.intValue ?? 0
            let configuration = WKFindConfiguration()
            configuration.backwards = !forward
            configuration.caseSensitive = false
            configuration.wraps = true
            self.webView.find(trimmed, configuration: configuration) { [weak self] result in
                guard let self,
                      requestID == self.findRequestID,
                      trimmed == self.findQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.updateNativeFindStatus(
                    matchFound: result.matchFound,
                    search: trimmed,
                    total: total,
                    forward: forward,
                    resetIndex: newSearch
                )
            }
        }
    }

    private func updateNativeFindStatus(
        matchFound: Bool,
        search: String,
        total: Int,
        forward: Bool,
        resetIndex: Bool
    ) {
        guard matchFound else {
            findSearch = search
            findCurrentIndex = 0
            findTotal = total
            findStatusText = "No matches"
            return
        }

        let shouldReset = resetIndex || findSearch != search || findTotal != total || findCurrentIndex == 0
        findSearch = search
        findTotal = total
        if shouldReset {
            findCurrentIndex = forward ? 1 : max(total, 1)
        } else if forward {
            findCurrentIndex = findCurrentIndex >= total ? 1 : findCurrentIndex + 1
        } else {
            findCurrentIndex = findCurrentIndex <= 1 ? max(total, 1) : findCurrentIndex - 1
        }
        updateFindStatus(matchFound: true, index: findCurrentIndex, total: total)
        let escaped = WebScripts.escapeForJavaScript(search)
        webView.evaluateJavaScript(
            WebScripts.makeScrollToFindMatchScript(search: escaped, index: findCurrentIndex),
            completionHandler: nil
        )
    }

    private func updateFindStatus(matchFound: Bool, index: Int?, total: Int?) {
        if !matchFound {
            findStatusText = "No matches"
        } else if let idx = index, let total, total > 0 {
            findStatusText = "\(idx) of \(total)"
        } else {
            findStatusText = "Match found"
        }
    }
}
