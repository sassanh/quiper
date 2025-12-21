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
    
    // State
    private var isFindBarVisible = false
    private var currentFindString: String = ""
    private var findDebouncer = FindDebouncer()
    
    // Constants
    private let barWidth: CGFloat = 360
    private let barHeight: CGFloat = 46
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupFindBar()
    }
    
    func addTo(contentView: NSView, bottomOffset: CGFloat) {
        contentView.addSubview(view, positioned: .above, relativeTo: nil)
        layoutIn(contentView: contentView, bottomOffset: bottomOffset)
    }
    
    func layoutIn(contentView: NSView, bottomOffset: CGFloat) {
        let padding: CGFloat = 12
        let originX = contentView.bounds.width - barWidth - padding
        let originY = contentView.bounds.height - bottomOffset - barHeight - padding
        
        view.frame = NSRect(x: originX, y: originY, width: barWidth, height: barHeight)
    }
    
    private func setupFindBar() {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        bar.material = .menu
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 10
        bar.layer?.masksToBounds = true
        // Although the view controller's view is the container, we can just treat 'bar' as the main view content
        // Or make 'bar' the view? Let's make view a container and add bar to it, or just make view = bar.
        // Let's make view = bar for simplicity.
        
        // However, loadView requires we set self.view.
        // Let's rebuild the internal structure matching the original manual layout.
        
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
        
        bar.addSubview(field)
        bar.addSubview(status)
        bar.addSubview(prevButton)
        bar.addSubview(nextButton)
        
        self.view = bar
        self.findBar = bar
        self.findField = field
        self.findStatusLabel = status
        self.findPreviousButton = prevButton
        self.findNextButton = nextButton
        
        // Start hidden
        self.view.isHidden = true
        
        findDebouncer.callback = { [weak self] in
            self?.performFind(forward: true, newSearch: true)
        }
    }
    
    // MARK: - API
    
    func show() {
        view.isHidden = false
        isFindBarVisible = true
        view.window?.makeFirstResponder(findField)
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
        view.isHidden = true
        isFindBarVisible = false
        findStatusLabel.stringValue = ""
        resetFind()
        if let webView = delegate?.activeWebViewForFind() {
            view.window?.makeFirstResponder(webView)
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
            // Should we focus the webview? The original code did:
            // showFindBar(), then window?.makeFirstResponder(currentWebView()).
            // But showFindBar() focuses the field.
            // Let's stick to the behavior: if bar wasn't visible, show it.
            // If it IS visible, perform find next.
            // Wait, original:
            /*
            if !isFindBarVisible {
                showFindBar()
                window?.makeFirstResponder(currentWebView()) // Why? Maybe to allow Cmd+G to work immediately on webview focus?
            }
             */
             // If I'm supposed to refactor, I should probably keep behavior.
             // But if I show the bar, I usually want to type in it.
             // However, Cmd+G (Find Next) implies you want to navigate *results*, not type.
             // The original code focuses the webview if opened via Cmd+G.
             if let webView = delegate?.activeWebViewForFind() {
                 view.window?.makeFirstResponder(webView)
             }
        }
        
        let trimmedField = findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedField.isEmpty {
            if currentFindString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                view.window?.makeFirstResponder(findField)
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
