import SwiftUI
import WebKit

struct BrowserViewportLayout: Equatable {
    let contentFrameTopInset: CGFloat
    let obscuredContentInsets: UIEdgeInsets
    let fallbackAdditionalSafeAreaInsets: UIEdgeInsets
}

struct WebKitBrowserView: UIViewControllerRepresentable {
    let session: WebViewSession
    let viewportLayout: BrowserViewportLayout

    func makeUIViewController(context: Context) -> WebViewHostController {
        WebViewHostController(
            webView: session.webView,
            viewportLayout: viewportLayout
        )
    }

    func updateUIViewController(_ controller: WebViewHostController, context: Context) {
        controller.apply(viewportLayout)
    }

    static func dismantleUIViewController(_ controller: WebViewHostController, coordinator: ()) {
        controller.detachWebView()
    }
}

final class WebViewHostController: UIViewController {
    private let webView: WKWebView
    private var appliedViewportLayout: BrowserViewportLayout?
    private var webViewTopConstraint: NSLayoutConstraint?

    init(
        webView: WKWebView,
        viewportLayout: BrowserViewportLayout
    ) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        apply(viewportLayout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = webView.underPageBackgroundColor
        container.clipsToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        let topConstraint = webView.topAnchor.constraint(equalTo: container.topAnchor)
        webViewTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topConstraint,
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.backgroundColor = webView.underPageBackgroundColor
    }

    func apply(_ viewportLayout: BrowserViewportLayout) {
        guard appliedViewportLayout != viewportLayout else { return }
        appliedViewportLayout = viewportLayout
        loadViewIfNeeded()
        if #available(iOS 26.0, *) {
            webViewTopConstraint?.constant = 0
            additionalSafeAreaInsets = .zero
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.contentInset = viewportLayout.obscuredContentInsets
            webView.scrollView.scrollIndicatorInsets = viewportLayout.obscuredContentInsets
            webView.obscuredContentInsets = viewportLayout.obscuredContentInsets
        } else {
            webViewTopConstraint?.constant = viewportLayout.contentFrameTopInset
            webView.scrollView.contentInsetAdjustmentBehavior = .always
            additionalSafeAreaInsets = viewportLayout.fallbackAdditionalSafeAreaInsets
        }
    }

    func detachWebView() {
        guard webView.superview === view else { return }
        webView.removeFromSuperview()
    }
}
