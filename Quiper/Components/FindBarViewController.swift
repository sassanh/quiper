import AppKit
import WebKit

protocol FindBarDelegate: AnyObject {
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
    
    private weak var targetWebView: WKWebView?
    var webView: WKWebView? { targetWebView }
    private var wasFocusedWhenTabHidden = false
    var windowKeyStateProvider: (NSWindow) -> Bool = { $0.isKeyWindow }
    var isVisible: Bool { !view.isHidden }
    var hasInputFocus: Bool {
        guard let window = view.window, windowKeyStateProvider(window) else { return false }
        return window.firstResponder === findField
            || window.firstResponder === findField.currentEditor()
    }
    
    // State
    private var isFindBarVisible = false
    private var currentFindString: String = ""
    private var findDebouncer = FindDebouncer()
    
    // Constants
    private let barWidth: CGFloat = 424
    private let barHeight: CGFloat = 46
    
    override func loadView() {
        view = FindBarEventView()
        view.wantsLayer = true
        setupFindBar()
    }
    
    func attach(to webView: WKWebView, in tabView: NSView) {
        targetWebView = webView
        let padding: CGFloat = 12
        view.frame = NSRect(
            x: tabView.bounds.width - barWidth - padding,
            y: tabView.bounds.height - barHeight - padding,
            width: barWidth,
            height: barHeight
        )
        view.autoresizingMask = [.minXMargin, .minYMargin]
        view.isHidden = true
        tabView.addSubview(view, positioned: .above, relativeTo: webView)
        (tabView as? WebViewWrapperView)?.interactiveOverlayView = view
    }
    
    private func setupFindBar() {
        let bar = FindBarEventView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
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
        self.view.isHidden = true
        
        findDebouncer.callback = { [weak self] in
            self?.performFind(forward: true, newSearch: true)
        }
    }
    
    // MARK: - API
    
    func show() {
        guard targetWebView != nil else { return }
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
        hide(restoreWebViewFocus: true)
    }

    func tabWillHide() {
        wasFocusedWhenTabHidden = isFindBarVisible && hasInputFocus
    }

    @discardableResult
    func tabDidShow() -> Bool {
        guard isFindBarVisible, wasFocusedWhenTabHidden else {
            return false
        }
        view.window?.makeFirstResponder(findField)
        return hasInputFocus
    }

    func hide(restoreWebViewFocus: Bool) {
        currentFindString = findField.stringValue
        view.isHidden = true
        isFindBarVisible = false
        wasFocusedWhenTabHidden = false
        findStatusLabel.stringValue = ""
        findDebouncer.cancel()
        resetFind(in: targetWebView)
        if restoreWebViewFocus,
           let webView = targetWebView,
           let window = view.window, window.isVisible {
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
            if let webView = targetWebView {
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
    
    @objc func closeTapped() {
        hide()
    }
    
    private func resetFind(in webView: WKWebView?) {
        updateFindStatus(matchFound: nil, index: nil, total: nil)
        webView?.evaluateJavaScript(WebScripts.makeResetFindScript(), completionHandler: nil)
    }
    
    private func performFind(forward: Bool, newSearch: Bool = false) {
        guard isFindBarVisible, let webView = targetWebView else { return }
        
        let searchString = findField.stringValue
        if newSearch && searchString == currentFindString {
            return
        }
        
        currentFindString = searchString
        let trimmed = currentFindString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetFind(in: webView)
            return
        }
        
        let escaped = WebScripts.escapeForJavaScript(trimmed)
        let script = WebScripts.makeFindScript(search: escaped, backwards: !forward, resetSelection: newSearch)
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self,
                  self.isFindBarVisible,
                  self.targetWebView === webView else { return }
            guard error == nil else {
                self.updateFindStatus(matchFound: false, index: nil, total: nil)
                return
            }
            if let dict = result as? [String: Any],
               let match = dict["match"] as? Bool {
                let current = dict["current"] as? Int
                let total = dict["total"] as? Int
                self.updateFindStatus(matchFound: match, index: current, total: total)
            } else {
                self.updateFindStatus(matchFound: false, index: nil, total: nil)
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

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func timerFired() {
        timer = nil
        callback?()
    }
}

private final class FindBarEventView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), !isHidden else { return nil }

        for subview in subviews.reversed() where !subview.isHidden && subview.alphaValue > 0 {
            let subviewPoint = convert(point, to: subview)
            guard subview.bounds.contains(subviewPoint) else { continue }
            return subview.hitTest(subviewPoint) ?? subview
        }

        return self
    }

    override func mouseMoved(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
