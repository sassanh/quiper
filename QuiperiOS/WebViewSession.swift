import Combine
import Foundation
import WebKit

@MainActor
final class WebViewSession: ObservableObject {
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
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true

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

    private static let collapseThreshold: CGFloat = 80
    private static let restoreThreshold: CGFloat = 40
    private static let scrollNoiseFloor: CGFloat = 1

    var onPromptRecorded: ((String) -> Void)?
    var onURLChange: ((URL) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onRememberRoutingDecision: ((_ host: String, _ action: RoutingAction) -> Void)?

    func handleInputState(_ payload: [String: Any]) {
        let parsed = InputStatePayload(payload)
        if parsed.wasSent, parsed.clearType == "submit",
           PromptHistoryPolicy.makeEntryIfEligible(submittedText: parsed.wasSentText) != nil {
            onPromptRecorded?(parsed.wasSentText)
        }
    }

    func submitPrompt(_ text: String) {
        coordinator.injectAndSubmit(text)
    }

    func focusInput() {
        coordinator.focusInput()
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
}
