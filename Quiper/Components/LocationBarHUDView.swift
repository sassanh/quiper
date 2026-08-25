import AppKit
import WebKit

@MainActor
final class LocationBarHUDView: NSView {
    private(set) var isHiding: Bool = false
    /// Invalidates pending animation completions whenever show()/hide() re-run,
    /// so a stale completion can't tear down a newer presentation state.
    private var displayGeneration = 0

    private weak var wc: MainWindowController?
    private let visualEffectView: NSVisualEffectView
    private let containerView: NSView
    private let urlIcon = NSImageView()
    private var urlField: NSTextField!
    private let goButton = LocationBarGoButton()

    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, windowController: MainWindowController) {
        self.wc = windowController

        visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        containerView = NSView()

        super.init(frame: frameRect)

        self.appearance = NSAppearance(named: .vibrantDark)
        self.autoresizingMask = [.width, .height]

        // Base view styling
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        // Visual Effect backdrop with rounded mask and border
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Constants.LocationBarHUD.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        addSubview(visualEffectView)

        // Premium dark backing layer to increase contrast
        let darkBacking = NSView(frame: bounds)
        darkBacking.autoresizingMask = [.width, .height]
        darkBacking.wantsLayer = true
        darkBacking.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        visualEffectView.addSubview(darkBacking)

        setupLocationBar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLocationBar() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.autoresizingMask = [.width, .height]
        containerView.frame = visualEffectView.bounds
        visualEffectView.addSubview(containerView)

        if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Page Address") {
            image.isTemplate = true
            urlIcon.image = image
        }
        urlIcon.contentTintColor = .secondaryLabelColor
        urlIcon.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(urlIcon)

        let field = NSTextField()
        field.placeholderString = "Enter page address"
        field.font = NSFont.systemFont(ofSize: 26, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setAccessibilityIdentifier("LocationBarField")
        containerView.addSubview(field)
        urlField = field

        goButton.onClick = { [weak self] in
            self?.navigateToCurrentInput()
        }
        goButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(goButton)

        NSLayoutConstraint.activate([
            urlIcon.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            urlIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            urlIcon.widthAnchor.constraint(equalToConstant: 20),
            urlIcon.heightAnchor.constraint(equalToConstant: 20),

            urlField.leadingAnchor.constraint(equalTo: urlIcon.trailingAnchor, constant: 12),
            urlField.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -14),
            urlField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            goButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -11),
            goButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            goButton.widthAnchor.constraint(equalToConstant: 36),
            goButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    func show() {
        displayGeneration += 1
        self.isHiding = false
        self.isHidden = false
        self.alphaValue = 0

        // Prefill with the current page's address
        self.urlField.stringValue = wc?.currentWebView()?.url?.absoluteString ?? ""

        if let window = self.window {
            window.makeFirstResponder(self.urlField)
        }
        if let editor = self.urlField.currentEditor() {
            editor.selectAll(nil)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        QuickTooltip.shared.hideImmediately()
        guard !isHiding else {
            return
        }
        self.isHiding = true
        displayGeneration += 1
        let generation = displayGeneration

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.displayGeneration == generation else { return }
                if let editor = self.urlField.currentEditor(),
                   self.window?.firstResponder === editor {
                    self.window?.makeFirstResponder(nil)
                }
                self.isHidden = true
                self.isHiding = false
                self.wc?.hideLocationBarHUD()
            }
        })
    }

    private func navigateToCurrentInput() {
        guard let wc = wc, let webView = wc.currentWebView() else { return }
        guard let url = Self.navigationURL(fromInput: self.urlField.stringValue) else {
            wc.playErrorSound()
            return
        }
        wc.webViewManager.load(url, in: webView)
        hide()
    }

    /// Resolves the text typed into the location bar into a navigable URL.
    /// Accepts full URLs, bare hosts ("example.com"), and absolute file paths.
    static func navigationURL(fromInput rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if input.hasPrefix("/") {
            return URL(fileURLWithPath: input)
        }

        func parsed(_ candidate: String) -> URL? {
            guard let url = URL(string: candidate),
                  let scheme = url.scheme,
                  !scheme.isEmpty else { return nil }
            guard url.isFileURL || !(url.host ?? "").isEmpty else { return nil }
            return url
        }

        if let url = parsed(input) { return url }

        let percentEncoded = input.replacingOccurrences(of: " ", with: "%20")
        if let url = parsed(percentEncoded) { return url }

        return parsed("https://\(percentEncoded)")
    }

    // Swallow mouse clicks to prevent click-through to webview
    override func mouseDown(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHiding || isHidden {
            return nil
        }
        return super.hitTest(point)
    }
}

// MARK: - NSTextFieldDelegate
extension LocationBarHUDView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            navigateToCurrentInput()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}

@MainActor
fileprivate final class LocationBarGoButton: NSControl {
    var onClick: (() -> Void)?

    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var isPressed = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    private let iconView = NSImageView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        refusesFirstResponder = true

        if let image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Go") {
            image.isTemplate = true
            iconView.image = image
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16)
        ])

        setAccessibilityLabel("Go")

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }

    private func updateAppearance() {
        if isPressed {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            iconView.contentTintColor = .labelColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            iconView.contentTintColor = .controlAccentColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            iconView.contentTintColor = .secondaryLabelColor
        }
    }
}
