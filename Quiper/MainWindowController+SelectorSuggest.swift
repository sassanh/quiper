import AppKit
import WebKit

/// Message handler for the selector picker. Deliberately non-isolated like
/// `InputStateScriptMessageHandler`: WebKit calls back from its own context,
/// so the handler hops to the main actor explicitly.
final class SelectorPickerMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var controller: MainWindowController?

    init(controller: MainWindowController) {
        self.controller = controller
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let controller = controller
        Task { @MainActor in
            if message.name == MainWindowController.selectorPickerHandlerName {
                controller?.handleSelectorPickerMessage(message.body)
            }
        }
    }
}

extension MainWindowController {
    static let selectorPickerHandlerName = "quiperSelectorPicker"

    var isSelectorSuggestActive: Bool {
        isSelectorSuggestPicking || selectorSuggestWindowController?.window?.isVisible == true
    }

    @objc func startSelectorSuggestMode(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        beginSelectorSuggestHover(on: webView)
    }

    private func attachSelectorPickerHandler(to webView: WKWebView) {
        let handler = SelectorPickerMessageHandler(controller: self)
        selectorSuggestMessageHandler = handler
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.selectorPickerHandlerName)
        webView.configuration.userContentController.add(handler, name: Self.selectorPickerHandlerName)
    }

    private func beginSelectorSuggestHover(on webView: WKWebView) {
        if isSelectorSuggestActive {
            cancelSelectorSuggest()
        }
        selectorSuggestCandidates = []
        selectorSuggestWebView = webView
        isSelectorSuggestPicking = true
        attachSelectorPickerHandler(to: webView)
        webView.evaluateJavaScript(WebScripts.makeSelectorPickerStartScript()) { _, error in
            if let error {
                NSLog("[Quiper] Selector picker failed to start: %@", error.localizedDescription)
            }
        }
    }

    /// Maps a point in the webview's own coordinates (points, origin at the
    /// bottom-left) to viewport (client) coordinates for
    /// `document.elementFromPoint`. Retina scaling cancels out, leaving only
    /// the page zoom.
    static func clientPoint(forViewPoint point: NSPoint, viewHeight: CGFloat, pageZoom: CGFloat) -> NSPoint {
        let zoom = pageZoom > 0 ? pageZoom : 1
        return NSPoint(x: point.x / zoom, y: (viewHeight - point.y) / zoom)
    }

    /// Starts the flow directly on the right-clicked element: resolves it in
    /// the page and opens the dialog, skipping hover mode. Falls back to
    /// hover picking when the element cannot be resolved.
    func webViewDidRequestSelectorSuggest(_ webView: WKWebView, at viewPoint: NSPoint) {
        if isSelectorSuggestActive {
            cancelSelectorSuggest()
        }
        selectorSuggestCandidates = []
        selectorSuggestWebView = webView
        isSelectorSuggestPicking = false
        attachSelectorPickerHandler(to: webView)
        let client = Self.clientPoint(
            forViewPoint: viewPoint,
            viewHeight: webView.bounds.height,
            pageZoom: webView.pageZoom
        )
        NSLog(
            "[Quiper] Direct pick at view %@ (height %.1f, zoom %.3f) -> client %@",
            NSStringFromPoint(viewPoint),
            webView.bounds.height,
            webView.pageZoom,
            NSStringFromPoint(client)
        )
        webView.evaluateJavaScript(
            WebScripts.makeSelectorDirectPickScript(x: client.x, y: client.y)
        ) { [weak self] result, _ in
            guard let self else { return }
            if (result as? Bool) == true {
                return
            }
            Task { @MainActor in
                self.beginSelectorSuggestHover(on: webView)
            }
        }
    }

    func cancelSelectorSuggest() {
        if let webView = selectorSuggestWebView {
            webView.evaluateJavaScript(WebScripts.makeSelectorPickerStopScript(), completionHandler: nil)
            webView.evaluateJavaScript(WebScripts.makeSelectorPreviewClearScript(), completionHandler: nil)
            detachSelectorPickerHandler(from: webView)
        }
        selectorSuggestWindowController?.dismissWithoutCallback()
        resetSelectorSuggestState()
    }

    func handleSelectorPickerMessage(_ body: Any) {
        guard let payload = body as? [String: Any],
              let type = payload["type"] as? String
        else { return }
        switch type {
        case "picked":
            let rawPath = payload["path"] as? [[String: Any]] ?? []
            let descriptors = rawPath.compactMap { SelectorElementDescriptor(dictionary: $0) }
            selectorSuggestDidPick(path: descriptors)
        case "cancelled":
            cancelSelectorSuggest()
        default:
            break
        }
    }

    private func selectorSuggestDidPick(path: [SelectorElementDescriptor]) {
        let candidates = SelectorSuggest.candidates(for: path)
        guard !candidates.isEmpty else {
            cancelSelectorSuggest()
            return
        }
        selectorSuggestCandidates = candidates
        isSelectorSuggestPicking = false
        if let webView = selectorSuggestWebView {
            detachSelectorPickerHandler(from: webView)
        }
        presentSelectorSuggestWindow()
        previewSelector(at: candidates.count - 1, scroll: true)
    }

    private func presentSelectorSuggestWindow() {
        if selectorSuggestWindowController == nil {
            let controller = SelectorSuggestWindowController()
            controller.onDepthChanged = { [weak self] depth in
                self?.previewSelector(at: depth, scroll: false)
            }
            controller.onCopy = { [weak self] in
                self?.copySelectorSuggestSelector()
            }
            controller.onHide = { [weak self] in
                self?.hideSelectorSuggestSelector()
            }
            controller.onClose = { [weak self] in
                self?.cancelSelectorSuggest()
            }
            selectorSuggestWindowController = controller
        }
        selectorSuggestWindowController?.present(
            candidates: selectorSuggestCandidates,
            parentWindow: window
        )
    }

    private func previewSelector(at depth: Int, scroll: Bool) {
        guard let webView = selectorSuggestWebView,
              !selectorSuggestCandidates.isEmpty
        else { return }
        let clamped = min(max(depth, 0), selectorSuggestCandidates.count - 1)
        let selector = selectorSuggestCandidates[clamped]
        webView.callAsyncJavaScript(
            WebScripts.makeSelectorPreviewScript(selector: selector, scrollIntoView: scroll),
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            let count: Int? = {
                switch result {
                case .success(let value):
                    if let number = value as? NSNumber { return number.intValue }
                    if let intValue = value as? Int { return intValue }
                    if let doubleValue = value as? Double { return Int(doubleValue) }
                    return nil
                case .failure:
                    return nil
                }
            }()
            self.selectorSuggestWindowController?.updateMatchCount(count)
        }
    }

    private func copySelectorSuggestSelector() {
        let selector = selectorSuggestWindowController?.currentSelector ?? ""
        guard !selector.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selector, forType: .string)
        cancelSelectorSuggest()
    }

    /// Appends `display: none` for the current selector to the engine
    /// stylesheet. The CSS gate pushes it into live sessions immediately;
    /// future loads pick it up from disk. Ephemeral tabs save nothing.
    private func hideSelectorSuggestSelector() {
        let selector = selectorSuggestWindowController?.currentSelector ?? ""
        guard !selector.isEmpty,
              let webView = selectorSuggestWebView,
              let (service, sessionIndex) = webViewManager.findServiceAndSession(for: webView)
        else { return }
        if !webViewManager.isQuiperPrivateTab(serviceID: service.id, sessionIndex: sessionIndex) {
            let existing = Settings.shared.customCSS(for: service).trimmingCharacters(in: .whitespacesAndNewlines)
            let rule = SelectorSuggest.hideRule(for: selector)
            let updated = (existing.isEmpty ? "" : existing + "\n\n")
                + "/* Hidden via Suggest Selector */\n" + rule + "\n"
            Settings.shared.saveCustomCSS(updated, serviceID: service.id)
        }
        cancelSelectorSuggest()
    }

    private func detachSelectorPickerHandler(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.selectorPickerHandlerName
        )
        if selectorSuggestMessageHandler != nil {
            selectorSuggestMessageHandler = nil
        }
    }

    private func resetSelectorSuggestState() {
        selectorSuggestCandidates = []
        selectorSuggestWebView = nil
        isSelectorSuggestPicking = false
        selectorSuggestMessageHandler = nil
    }

    /// Re-applies picker state after a navigation wipes page scripts.
    func selectorSuggestDidReload(webView: WKWebView) {
        guard webView === selectorSuggestWebView else { return }
        if isSelectorSuggestPicking {
            webView.evaluateJavaScript(WebScripts.makeSelectorPickerStartScript(), completionHandler: nil)
        } else if !selectorSuggestCandidates.isEmpty {
            previewSelector(at: selectorSuggestWindowController?.depth ?? selectorSuggestCandidates.count - 1, scroll: true)
        }
    }
}
