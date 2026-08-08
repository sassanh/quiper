import SwiftUI
import UIKit
import WebKit

/// SwiftUI host for the shared CodeMirror editor bundle, mirroring the macOS
/// `CodeEditorContainer`/`CodeMirrorEditor` pair. It owns a `CodeEditorSession`
/// that maps the macOS `EditorDocumentSession` document/debounced-save/read-only
/// contract to in-memory storage.
struct CodeEditorView: View {
    @Binding private var code: String
    @StateObject private var session: CodeEditorSession

    let language: CodeEditorLanguage
    let isReadOnly: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(code: Binding<String>, language: CodeEditorLanguage, isReadOnly: Bool = false) {
        _code = code
        self.language = language
        self.isReadOnly = isReadOnly
        _session = StateObject(wrappedValue: CodeEditorSession(
            initialText: code.wrappedValue,
            isReadOnly: isReadOnly,
            onAcceptedChange: { newValue in
                code.wrappedValue = newValue
            }
        ))
    }

    var body: some View {
        CodeMirrorEditorView(
            text: session.text,
            language: language,
            isReadOnly: isReadOnly,
            colorScheme: colorScheme,
            onChange: session.userDidEdit
        )
        .onAppear {
            session.resume()
        }
        .onDisappear {
            session.stop()
        }
        .onChange(of: code) { _, newValue in
            session.receiveHostText(newValue)
        }
        .onChange(of: isReadOnly) { _, newValue in
            session.updateReadOnlyState(newValue, hostText: code)
        }
    }
}

/// `UIViewRepresentable` port of the macOS `CodeMirrorEditor` (NSViewRepresentable).
/// It hosts the bundled `quiper-code-editor.html`/`.js` in a `WKWebView` and speaks
/// the same `quiperCodeEditor` message-handler and `window.quiperEditor.setDocument`
/// bridge contract.
private struct CodeMirrorEditorView: UIViewRepresentable {
    let text: String
    let language: CodeEditorLanguage
    let isReadOnly: Bool
    let colorScheme: ColorScheme
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        context.coordinator.updateInitialThemeScript(
            in: configuration.userContentController,
            theme: colorScheme == .light ? "light" : "dark"
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.messageHandlerName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        webView.backgroundColor = editorBackingColor
        webView.isOpaque = true
        webView.underPageBackgroundColor = editorBackingColor
        webView.accessibilityLabel = "Code editor"

        if let editorURL = Bundle.main.url(
            forResource: "quiper-code-editor",
            withExtension: "html"
        ) {
            webView.loadFileURL(
                editorURL,
                allowingReadAccessTo: editorURL.deletingLastPathComponent()
            )
        } else {
            webView.loadHTMLString(
                "<html><body>Code editor resources are unavailable.</body></html>",
                baseURL: nil
            )
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.backgroundColor = editorBackingColor
        webView.underPageBackgroundColor = editorBackingColor
        context.coordinator.parent = self
        context.coordinator.updateInitialThemeScript(
            in: webView.configuration.userContentController,
            theme: colorScheme == .light ? "light" : "dark"
        )
        context.coordinator.update(
            webView: webView,
            configuration: EditorConfiguration(
                text: text,
                language: language.rawValue,
                readOnly: isReadOnly,
                theme: colorScheme == .light ? "light" : "dark"
            )
        )
    }

    private var editorBackingColor: UIColor {
        .secondarySystemGroupedBackground
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
    }

    fileprivate struct EditorConfiguration: Equatable {
        let text: String
        let language: String
        let readOnly: Bool
        let theme: String
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "quiperCodeEditor"

        var parent: CodeMirrorEditorView
        private var latestConfiguration: EditorConfiguration?
        private var appliedConfiguration: EditorConfiguration?
        private var initialThemeScriptValue: String?
        private var isReady = false

        init(parent: CodeMirrorEditorView) {
            self.parent = parent
        }

        fileprivate func update(webView: WKWebView, configuration: EditorConfiguration) {
            latestConfiguration = configuration
            applyLatestConfiguration(to: webView)
        }

        fileprivate func updateInitialThemeScript(
            in userContentController: WKUserContentController,
            theme: String
        ) {
            guard theme != initialThemeScriptValue else { return }
            userContentController.removeAllUserScripts()
            userContentController.addUserScript(WKUserScript(
                source: "window.__quiperInitialTheme = \"\(theme)\";",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            initialThemeScriptValue = theme
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                isReady = true
                if let webView = message.webView {
                    applyLatestConfiguration(to: webView)
                }
            case "change":
                guard let text = body["text"] as? String else { return }
                parent.onChange(text)
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isAllowedLocalPage = url?.isFileURL == true || url?.absoluteString == "about:blank"
            guard navigationAction.navigationType != .linkActivated, isAllowedLocalPage else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation?
        ) {
            isReady = false
            appliedConfiguration = nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            appliedConfiguration = nil
            webView.reload()
        }

        private func applyLatestConfiguration(to webView: WKWebView) {
            guard isReady,
                  let latestConfiguration,
                  latestConfiguration != appliedConfiguration else {
                return
            }

            appliedConfiguration = latestConfiguration
            let payload: [String: Any] = [
                "text": latestConfiguration.text,
                "language": latestConfiguration.language,
                "readOnly": latestConfiguration.readOnly,
                "theme": latestConfiguration.theme
            ]
            webView.callAsyncJavaScript(
                """
                window.quiperEditor?.setDocument(payload);
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                """,
                arguments: ["payload": payload],
                in: nil,
                in: .page
            ) { _ in }
        }
    }
}
