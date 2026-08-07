import SwiftUI
import WebKit

struct WebKitBrowserView: UIViewRepresentable {
    let session: WebViewSession

    func makeUIView(context: Context) -> WKWebView {
        session.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.removeFromSuperview()
    }
}
