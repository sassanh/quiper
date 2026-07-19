import AppKit
import SwiftUI
import WebKit

enum CodeEditorLanguage: String, Equatable {
    case javaScript = "javascript"
    case css
    case cssSelector
}

@MainActor
struct CodeEditorContainer: View {
    @Binding private var code: String
    @StateObject private var session: EditorDocumentSession

    let language: CodeEditorLanguage
    let fileName: String
    let isReadOnly: Bool
    let openInEditor: () -> Void
    let revealInFinder: () -> Void
    let copyFilePath: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        code: Binding<String>,
        language: CodeEditorLanguage,
        fileName: String,
        fileURL: URL,
        isReadOnly: Bool = false,
        openInEditor: @escaping () -> Void,
        revealInFinder: @escaping () -> Void,
        copyFilePath: @escaping () -> Void
    ) {
        _code = code
        self.language = language
        self.fileName = fileName
        self.isReadOnly = isReadOnly
        self.openInEditor = openInEditor
        self.revealInFinder = revealInFinder
        self.copyFilePath = copyFilePath
        _session = StateObject(wrappedValue: EditorDocumentSession(
            initialText: code.wrappedValue,
            fileURL: fileURL,
            isReadOnly: isReadOnly,
            onAcceptedChange: { newValue in
                code.wrappedValue = newValue
            }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if session.conflict != nil {
                conflictBanner
                Divider()
            }

            CodeMirrorEditor(
                text: session.text,
                language: language,
                isReadOnly: isReadOnly,
                colorScheme: colorScheme,
                onChange: session.userDidEdit
            )
            .frame(minHeight: 160, maxHeight: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 0
                )
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
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

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.accentColor)
                Text(fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()
                .opacity(0.6)

            HStack(spacing: 12) {
                statusLabel
                Spacer()

                if !isReadOnly {
                    HStack(spacing: 12) {
                        Button(action: openInEditor) {
                            Label("Open Externally", systemImage: "arrow.up.forward.app")
                        }
                        .help("Open in your default text editor")

                        Button(action: revealInFinder) {
                            Label("Reveal", systemImage: "sidebar.left")
                        }
                        .help("Show file in Finder")

                        Button(action: copyFilePath) {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        .help("Copy absolute file path to clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if isReadOnly {
            Label("In Sync", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .help("This editor follows Quiper's latest bundled default and cannot be edited")
        } else {
            switch session.status {
            case .saved:
                Label("Saved", systemImage: "checkmark.circle")
                    .foregroundColor(.secondary)
            case .saving:
                Label("Saving", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundColor(.secondary)
            case .updatedExternally:
                Label("Updated Externally", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
            case .conflict:
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .error(let message):
                Label("File Error", systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help(message)
            }
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This file changed in another editor")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Choose which version should be kept.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Load External") {
                session.loadExternalVersion()
            }
            Button("Keep Mine") {
                session.keepInternalVersion()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

private struct CodeMirrorEditor: NSViewRepresentable {
    let text: String
    let language: CodeEditorLanguage
    let isReadOnly: Bool
    let colorScheme: ColorScheme
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CodeEditorHostView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        context.coordinator.updateInitialThemeScript(
            in: configuration.userContentController,
            theme: colorScheme == .light ? "light" : "dark"
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.messageHandlerName
        )

        let webView = CodeEditorWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.isInspectable = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.alphaValue = 0
        webView.underPageBackgroundColor = editorBackingColor
        webView.setAccessibilityLabel("Code editor")
        let hostView = CodeEditorHostView(
            webView: webView,
            backgroundColor: editorBackingColor
        )

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
        return hostView
    }

    func updateNSView(_ hostView: CodeEditorHostView, context: Context) {
        let webView = hostView.webView
        hostView.updateBackgroundColor(editorBackingColor)
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

    private var editorBackingColor: NSColor {
        isReadOnly ? .clear : .textBackgroundColor
    }

    static func dismantleNSView(_ hostView: CodeEditorHostView, coordinator: Coordinator) {
        let webView = hostView.webView
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

        var parent: CodeMirrorEditor
        private var latestConfiguration: EditorConfiguration?
        private var appliedConfiguration: EditorConfiguration?
        private var initialThemeScriptValue: String?
        private var isReady = false

        init(parent: CodeMirrorEditor) {
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
            case "scrollState":
                guard let webView = message.webView as? CodeEditorWebView,
                      let canScrollUp = body["canScrollUp"] as? Bool,
                      let canScrollDown = body["canScrollDown"] as? Bool,
                      let canScrollLeft = body["canScrollLeft"] as? Bool,
                      let canScrollRight = body["canScrollRight"] as? Bool else {
                    return
                }
                webView.updateScrollCapabilities(
                    up: canScrollUp,
                    down: canScrollDown,
                    left: canScrollLeft,
                    right: canScrollRight
                )
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
            webView.alphaValue = 0
            (webView as? CodeEditorWebView)?.resetScrollCapabilities()
            isReady = false
            appliedConfiguration = nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.alphaValue = 0
            (webView as? CodeEditorWebView)?.resetScrollCapabilities()
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
            ) { result in
                guard case .success = result else { return }
                webView.alphaValue = 1
            }
        }
    }
}

@MainActor
private final class CodeEditorHostView: NSView {
    let webView: CodeEditorWebView

    init(webView: CodeEditorWebView, backgroundColor: NSColor) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBackgroundColor(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }
}

@MainActor
private final class CodeEditorWebView: WKWebView {
    private var canScrollUp = false
    private var canScrollDown = false
    private var canScrollLeft = false
    private var canScrollRight = false

    func updateScrollCapabilities(up: Bool, down: Bool, left: Bool, right: Bool) {
        canScrollUp = up
        canScrollDown = down
        canScrollLeft = left
        canScrollRight = right
    }

    func resetScrollCapabilities() {
        updateScrollCapabilities(up: false, down: false, left: false, right: false)
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = event.scrollingDeltaX
        let verticalDelta = event.scrollingDeltaY
        let isVerticalGesture = abs(verticalDelta) >= abs(horizontalDelta)

        let canConsumeEvent: Bool
        if isVerticalGesture, verticalDelta != 0 {
            canConsumeEvent = verticalDelta > 0 ? canScrollUp : canScrollDown
        } else if horizontalDelta != 0 {
            canConsumeEvent = horizontalDelta > 0 ? canScrollLeft : canScrollRight
        } else {
            canConsumeEvent = true
        }

        if canConsumeEvent {
            super.scrollWheel(with: event)
        } else {
            forwardScrollWheelToEnclosingScrollView(event)
        }
    }

    private func forwardScrollWheelToEnclosingScrollView(_ event: NSEvent) {
        var ancestor = superview
        while let currentView = ancestor {
            if let scrollView = currentView as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            ancestor = currentView.superview
        }
        nextResponder?.scrollWheel(with: event)
    }
}
