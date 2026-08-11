import SwiftUI
import WebKit

struct BrowserViewportLayout: Equatable {
    let obscuredContentInsets: UIEdgeInsets
}

struct WebKitBrowserView: UIViewControllerRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let session: WebViewSession
    let viewportLayout: BrowserViewportLayout

    func makeUIViewController(context: Context) -> WebViewHostController {
        WebViewHostController(
            webView: session.webView,
            viewportLayout: viewportLayout,
            colorScheme: colorScheme
        )
    }

    func updateUIViewController(_ controller: WebViewHostController, context: Context) {
        controller.apply(viewportLayout, colorScheme: colorScheme)
    }

    static func dismantleUIViewController(_ controller: WebViewHostController, coordinator: ()) {
        controller.detachWebView()
    }
}

final class WebViewHostController: UIViewController {
    private let webView: WKWebView
    private var appliedViewportLayout: BrowserViewportLayout?
    private var appliedColorScheme: ColorScheme?
    private var webViewTopConstraint: NSLayoutConstraint?

    init(
        webView: WKWebView,
        viewportLayout: BrowserViewportLayout,
        colorScheme: ColorScheme
    ) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        apply(viewportLayout, colorScheme: colorScheme)
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

    func apply(_ viewportLayout: BrowserViewportLayout, colorScheme: ColorScheme) {
        let layoutChanged = appliedViewportLayout != viewportLayout
        let colorSchemeChanged = appliedColorScheme != colorScheme
        guard layoutChanged || colorSchemeChanged else { return }
        loadViewIfNeeded()
        if layoutChanged {
            appliedViewportLayout = viewportLayout
            webViewTopConstraint?.constant = 0
            additionalSafeAreaInsets = .zero
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.contentInset = viewportLayout.obscuredContentInsets
            webView.scrollView.scrollIndicatorInsets = viewportLayout.obscuredContentInsets
            webView.obscuredContentInsets = viewportLayout.obscuredContentInsets
        }
        if colorSchemeChanged {
            appliedColorScheme = colorScheme
            let backgroundColor = Self.backgroundColor(for: colorScheme)
            webView.underPageBackgroundColor = backgroundColor
            webView.backgroundColor = backgroundColor
            webView.scrollView.backgroundColor = backgroundColor
            view.backgroundColor = backgroundColor
        }
    }

    private static func backgroundColor(for colorScheme: ColorScheme) -> UIColor {
        UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(
                userInterfaceStyle: colorScheme == .dark ? .dark : .light
            )
        )
    }

    func detachWebView() {
        guard webView.superview === view else { return }
        webView.removeFromSuperview()
    }
}
