import AppKit
import WebKit

protocol FindBarDelegate: AnyObject {
    func activeWebViewForFind() -> WKWebView?
    func playErrorSound()
}

final class FindBarViewController: NSViewController, NSSearchFieldDelegate {
    weak var delegate: FindBarDelegate?
    
    // UI Elements
    private var findBar: NSVisualEffectView!
    private var findField: NSSearchField!
    private var findStatusLabel: NSTextField!
    private var findPreviousButton: NSButton!
    private var findNextButton: NSButton!
    private var closeButton: NSButton!
    
    // Child window that hosts the find bar above the WKWebView
    private var findBarPanel: NSPanel?
    private weak var parentWindow: NSWindow?
    
    // State
    private var isFindBarVisible = false
    private var currentFindString: String = ""
    private var findDebouncer = FindDebouncer()
    
    // Constants
    private let barWidth: CGFloat = 424
    private let barHeight: CGFloat = 46
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupFindBar()
    }
    
    func addTo(parentWindow: NSWindow, topOffset: CGFloat) {
        self.parentWindow = parentWindow
        createPanelIfNeeded()
        layoutIn(parentWindow: parentWindow, topOffset: topOffset)
    }
    
    func layoutIn(parentWindow: NSWindow, topOffset: CGFloat) {
        guard let panel = findBarPanel,
              let contentView = parentWindow.contentView else { return }
        
        let padding: CGFloat = 12
        // Compute position in parent content view coordinates
        let originX = contentView.bounds.width - barWidth - padding
        let originY = contentView.bounds.height - topOffset - barHeight - padding
        
        // Convert from content view coords to screen coords
        let rectInWindow = NSRect(x: originX, y: originY, width: barWidth, height: barHeight)
        let rectInScreen = parentWindow.convertToScreen(rectInWindow)
        
        panel.setFrame(rectInScreen, display: true)
    }
    
    // Legacy compatibility shim for callers using contentView-based API
    func addTo(contentView: NSView, topOffset: CGFloat) {
        guard let window = contentView.window else { return }
        addTo(parentWindow: window, topOffset: topOffset)
    }
    
    func layoutIn(contentView: NSView, topOffset: CGFloat) {
        guard let window = contentView.window ?? parentWindow else { return }
        layoutIn(parentWindow: window, topOffset: topOffset)
    }
    
    private func createPanelIfNeeded() {
        guard findBarPanel == nil, let parentWindow = parentWindow else { return }
        
        let panel = FindBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: barWidth, height: barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = parentWindow.level
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        
        // Set the find bar as the panel's content
        panel.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
        
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderOut(nil) // Start hidden
        
        findBarPanel = panel
    }
    
    private func setupFindBar() {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        bar.material = .menu
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 10
        bar.layer?.masksToBounds = true
        
        let field = NSSearchField(frame: .zero)
        field.placeholderString = "Find in page"
        field.delegate = self
        field.target = self
        field.font = NSFont.systemFont(ofSize: 13)
        if let cell = field.cell as? NSSearchFieldCell {
            cell.sendsSearchStringImmediately = true
            cell.sendsWholeSearchString = false
        }
        
        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        
        let prevButton = NSButton(title: "‹", target: self, action: #selector(findPreviousTapped))
        prevButton.bezelStyle = .roundRect
        prevButton.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        
        let nextButton = NSButton(title: "›", target: self, action: #selector(findNextTapped))
        nextButton.bezelStyle = .roundRect
        nextButton.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        
        let closeBtn = NSButton(title: "Done", target: self, action: #selector(closeTapped))
        closeBtn.bezelStyle = .roundRect
        closeBtn.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        
        // Layout
        let padding: CGFloat = 12
        let buttonWidth: CGFloat = 32
        let buttonHeight: CGFloat = 24
        
        field.frame = NSRect(
            x: padding,
            y: (barHeight - buttonHeight) / 2,
            width: 170,
            height: buttonHeight
        )
        
        let statusWidth: CGFloat = 90
        status.frame = NSRect(
            x: field.frame.maxX + 8,
            y: (barHeight - 18) / 2,
            width: statusWidth,
            height: 18
        )
        
        prevButton.frame = NSRect(
            x: status.frame.maxX + 6,
            y: (barHeight - buttonHeight) / 2,
            width: buttonWidth,
            height: buttonHeight
        )
        
        nextButton.frame = NSRect(
            x: prevButton.frame.maxX + 4,
            y: prevButton.frame.minY,
            width: buttonWidth,
            height: buttonHeight
        )
        
        let doneWidth: CGFloat = 50
        closeBtn.frame = NSRect(
            x: nextButton.frame.maxX + 8,
            y: nextButton.frame.minY,
            width: doneWidth,
            height: buttonHeight
        )
        
        bar.addSubview(field)
        bar.addSubview(status)
        bar.addSubview(prevButton)
        bar.addSubview(nextButton)
        bar.addSubview(closeBtn)
        
        self.view = bar
        self.findBar = bar
        self.findField = field
        self.findStatusLabel = status
        self.findPreviousButton = prevButton
        self.findNextButton = nextButton
        self.closeButton = closeBtn
        
        findDebouncer.callback = { [weak self] in
            self?.performFind(forward: true, newSearch: true)
        }
    }
    
    // MARK: - API
    
    func show() {
        createPanelIfNeeded()
        findBarPanel?.orderFront(nil)
        isFindBarVisible = true
        findBarPanel?.makeKey()
        findBarPanel?.makeFirstResponder(findField)
        if findField.stringValue.isEmpty {
            findField.stringValue = currentFindString
        }
        if let editor = findField.currentEditor() {
            editor.selectAll(nil)
        }
        updateFindStatus(matchFound: nil, index: nil, total: nil)
    }
    
    func hide() {
        currentFindString = findField.stringValue
        findBarPanel?.orderOut(nil)
        isFindBarVisible = false
        findStatusLabel.stringValue = ""
        resetFind()
        if let webView = delegate?.activeWebViewForFind(),
           let window = parentWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(webView)
        }
    }
    
    func toggle() {
        if isFindBarVisible {
            hide()
        } else {
            show()
        }
    }
    
    func handleFindRepeat(shortcutShifted: Bool) {
        if !isFindBarVisible {
            show()
            // Cmd+G (Find Next) implies you want to navigate results, not type.
            // The original code focuses the webview if opened via Cmd+G.
             if let webView = delegate?.activeWebViewForFind() {
                 parentWindow?.makeKeyAndOrderFront(nil)
                 parentWindow?.makeFirstResponder(webView)
             }
        }
        
        let trimmedField = findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedField.isEmpty {
            if currentFindString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                findBarPanel?.makeKey()
                findBarPanel?.makeFirstResponder(findField)
                delegate?.playErrorSound()
                return
            }
            findField.stringValue = currentFindString
        }
        performFind(forward: !shortcutShifted)
    }
    
    // MARK: - Find Logic
    
    @objc func findPreviousTapped() {
        performFind(forward: false)
    }
    
    @objc func findNextTapped() {
        performFind(forward: true)
    }
    
    @objc func closeTapped() {
        hide()
    }
    
    private func resetFind() {
        updateFindStatus(matchFound: nil, index: nil, total: nil)
        let script = """
        (() => {
          if (window.__quiperFindState) {
              window.__quiperFindState.search = "";
              window.__quiperFindState.total = 0;
              window.__quiperFindState.index = 0;
          }
          const sel = window.getSelection();
          if (sel) { sel.removeAllRanges(); }
        })();
        """
        delegate?.activeWebViewForFind()?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func performFind(forward: Bool, newSearch: Bool = false) {
        guard let webView = delegate?.activeWebViewForFind() else { return }
        
        let searchString = findField.stringValue
        if newSearch && searchString == currentFindString {
            return
        }
        
        currentFindString = searchString
        let trimmed = currentFindString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetFind()
            return
        }
        
        let escaped = escapeForJavaScript(trimmed)
        let resetSelection = newSearch ? "true" : "false"
        let backwards = forward ? "false" : "true"
        
        // This large script block is identical to original
        let script = """
        (() => {
            const search = "\(escaped)";
            const backwards = \(backwards);
            let forceReset = \(resetSelection);
            const root = document.body || document.documentElement;
            const selection = window.getSelection();
            if (!root || !selection) {
                return { match: false, current: 0, total: 0 };
            }
            if (!document.getElementById("__quiperFindSelectionStyle")) {
                const style = document.createElement("style");
                style.id = "__quiperFindSelectionStyle";
                style.textContent = `
                    ::selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                    ::-moz-selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                `;
                (document.head || document.body || document.documentElement).appendChild(style);
            }
            const textContent = root.innerText || root.textContent || "";
            const escapedPattern = search.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&");
            const regex = escapedPattern ? new RegExp(escapedPattern, "gi") : null;
            if (!window.__quiperFindState) {
                window.__quiperFindState = { search: "", total: 0, index: 0 };
            }
            const state = window.__quiperFindState;
            if (state.search !== search) {
                state.search = search;
                forceReset = true;
            }
            if (!search) {
                state.total = 0;
                state.index = 0;
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            if (forceReset) {
                state.total = regex ? (textContent.match(regex) || []).length : 0;
                state.index = backwards ? state.total + 1 : 0;
                selection.removeAllRanges();
                const range = document.createRange();
                range.selectNodeContents(root);
                range.collapse(!backwards);
                selection.addRange(range);
            }
            const total = state.total;
            if (!total) {
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            const match = window.find(search, false, backwards, true, false, true, false);
            if (!match) {
                return { match: false, current: 0, total };
            }
            if (backwards) {
                state.index = state.index <= 1 ? total : state.index - 1;
            } else {
                state.index = state.index >= total ? 1 : state.index + 1;
            }
            const selectionNode = selection.focusNode && selection.focusNode.nodeType === Node.TEXT_NODE
                ? selection.focusNode.parentElement
                : selection.focusNode;
            if (selectionNode && selectionNode.scrollIntoView) {
                selectionNode.scrollIntoView({ block: 'center', inline: 'nearest' });
            }
            return { match: true, current: state.index, total };
        })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard error == nil else {
                self?.updateFindStatus(matchFound: false, index: nil, total: nil)
                return
            }
            if let dict = result as? [String: Any],
               let match = dict["match"] as? Bool {
                let current = dict["current"] as? Int
                let total = dict["total"] as? Int
                self?.updateFindStatus(matchFound: match, index: current, total: total)
            } else {
                self?.updateFindStatus(matchFound: false, index: nil, total: nil)
            }
        }
    }
    
    private func updateFindStatus(matchFound: Bool?, index: Int?, total: Int?) {
        guard let label = findStatusLabel else { return }
        guard let matchFound else {
            label.stringValue = currentFindString.isEmpty ? "" : "No matches"
            return
        }

        if !matchFound {
            label.stringValue = "No matches"
            return
        }

        if let idx = index, let total, total > 0 {
            label.stringValue = "\(idx) of \(total)"
        } else {
            label.stringValue = "Match found"
        }
    }
    
    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    // MARK: - NSSearchFieldDelegate
    
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field == findField else { return }
        findDebouncer.debounce()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control == findField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            performFind(forward: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            performFind(forward: false)
            return true
        }
        return false
    }
}

private final class FindDebouncer: NSObject {
    private var timer: Timer?
    var callback: (() -> Void)?
    
    func debounce(interval: TimeInterval = 0.3) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(timerFired),
                                     userInfo: nil,
                                     repeats: false)
    }
    
    @objc private func timerFired() {
        callback?()
    }
}

private final class FindBarPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}
