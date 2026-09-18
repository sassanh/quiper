import AppKit

/// Native popup shown after picking an element. Displays the generated CSS
/// selector, a Root-to-Leaf specificity slider, and Copy/Close actions.
/// The webview keeps the live highlight; this window never renders web content.
@MainActor
final class SelectorSuggestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SelectorSuggestWindowController: NSWindowController, NSWindowDelegate {
    var onDepthChanged: ((Int) -> Void)?
    var onCopy: (() -> Void)?
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?

    private let selectorTextView = NSTextView()
    private let selectorScrollView = NSScrollView()
    private let matchLabel = NSTextField(labelWithString: "")
    private let depthSlider = NSSlider()
    private let rootLabel = NSTextField(labelWithString: "Root")
    private let leafLabel = NSTextField(labelWithString: "Leaf")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let hideButton = NSButton(title: "Hide", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private var contentStack: NSStackView?
    /// Exposed for layout tests.
    var selectorContentStack: NSStackView? { contentStack }

    private var candidates: [String] = []
    private(set) var depth: Int = 0
    private var isDismissing = false

    var currentSelector: String {
        guard !candidates.isEmpty else { return "" }
        let clamped = min(max(depth, 0), candidates.count - 1)
        return candidates[clamped]
    }

    init() {
        let window = SelectorSuggestPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Suggest Selector"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "CSS Selector")
        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail

        selectorTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        selectorTextView.isEditable = false
        selectorTextView.isSelectable = true
        selectorTextView.drawsBackground = false
        selectorTextView.isVerticallyResizable = true
        selectorTextView.isHorizontallyResizable = false
        selectorTextView.autoresizingMask = [.width]
        selectorTextView.textContainer?.lineBreakMode = .byCharWrapping
        selectorTextView.textContainer?.widthTracksTextView = true
        selectorScrollView.documentView = selectorTextView
        selectorScrollView.hasVerticalScroller = true
        selectorScrollView.hasHorizontalScroller = false
        selectorScrollView.borderType = .bezelBorder
        selectorScrollView.translatesAutoresizingMaskIntoConstraints = false
        selectorScrollView.heightAnchor.constraint(equalToConstant: 60).isActive = true

        matchLabel.font = .systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.lineBreakMode = .byTruncatingTail

        depthSlider.minValue = 0
        depthSlider.maxValue = 0
        depthSlider.numberOfTickMarks = 1
        depthSlider.allowsTickMarkValuesOnly = true
        depthSlider.isContinuous = true
        depthSlider.target = self
        depthSlider.action = #selector(sliderChanged(_:))

        rootLabel.font = .systemFont(ofSize: 11)
        rootLabel.textColor = .secondaryLabelColor
        leafLabel.font = .systemFont(ofSize: 11)
        leafLabel.textColor = .secondaryLabelColor

        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.keyEquivalent = "\r"
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        hideButton.bezelStyle = .rounded
        hideButton.target = self
        hideButton.action = #selector(hideClicked)
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        hideButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let sliderRow = NSStackView(views: [rootLabel, depthSlider, leafLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8
        depthSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, closeButton, hideButton, copyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fill
        buttonRow.alignment = .centerY

        let stack = NSStackView(views: [titleLabel, selectorScrollView, matchLabel, sliderRow, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentStack = stack
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectorScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            sliderRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])

        // Hug the content exactly: a taller window leaves a dead gap under
        // the buttons, a shorter one breaks constraints. Row heights are
        // fixed (text view, buttons) or single-line, so this stays exact.
        contentView.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        window?.setContentSize(NSSize(width: 440, height: fitting.height))
    }

    func present(candidates: [String], parentWindow: NSWindow?) {
        self.candidates = candidates
        self.depth = max(candidates.count - 1, 0)
        depthSlider.minValue = 0
        depthSlider.maxValue = Double(max(candidates.count - 1, 0))
        depthSlider.numberOfTickMarks = max(candidates.count, 1)
        depthSlider.integerValue = depth
        updateSelectorText(matchCount: nil)
        copyButton.isEnabled = !currentSelector.isEmpty
        hideButton.isEnabled = !currentSelector.isEmpty

        if let window, let parentWindow, window.parent == nil {
            parentWindow.addChildWindow(window, ordered: .above)
        }
        if window?.isVisible == false {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func updateMatchCount(_ count: Int?) {
        updateSelectorText(matchCount: count)
    }

    /// Orders out without triggering `onClose` (used by the cancel path,
    /// which already performs teardown).
    func dismissWithoutCallback() {
        isDismissing = true
        if let popup = window {
            if let parent = popup.parent {
                parent.removeChildWindow(popup)
            }
            popup.orderOut(nil)
        }
        isDismissing = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isDismissing else { return }
        onClose?()
    }

    private func updateSelectorText(matchCount: Int?) {
        let text = currentSelector.isEmpty ? "No selector" : currentSelector
        selectorTextView.string = text
        if let count = matchCount {
            matchLabel.stringValue = count == 1 ? "Matches 1 element" : "Matches \(count) elements"
        } else {
            matchLabel.stringValue = candidates.isEmpty ? "" : "Move the slider to change specificity"
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        depth = sender.integerValue
        updateSelectorText(matchCount: nil)
        onDepthChanged?(depth)
    }

    @objc private func copyClicked() {
        onCopy?()
    }

    @objc private func hideClicked() {
        onHide?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
