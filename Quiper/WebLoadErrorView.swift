import AppKit

@MainActor
final class WebLoadErrorView: NSView {
    var onRetry: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func configure(error: WebLoadError, retryAvailable: Bool = true) {
        titleLabel.stringValue = error.kind.title
        messageLabel.stringValue = error.kind.message
        retryButton.isEnabled = retryAvailable
    }

    func setVisible(_ isVisible: Bool) {
        isHidden = !isVisible
        setAccessibilityElement(isVisible)
    }

    func focus() {
        window?.makeFirstResponder(retryButton.isEnabled ? retryButton : self)
    }

    private func setupViews() {
        identifier = NSUserInterfaceItemIdentifier("WebLoadErrorView")
        setAccessibilityIdentifier("WebLoadErrorView")
        setVisible(false)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor

        iconView.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "Page load error"
        )
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityIdentifier("WebLoadErrorIcon")

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setAccessibilityIdentifier("WebLoadErrorTitle")

        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.setAccessibilityIdentifier("WebLoadErrorMessage")

        retryButton.target = self
        retryButton.action = #selector(retryButtonClicked)
        retryButton.bezelStyle = .rounded
        retryButton.keyEquivalent = "\r"
        retryButton.setAccessibilityIdentifier("WebLoadErrorRetryButton")

        let stack = NSStackView(views: [iconView, titleLabel, messageLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    @objc private func retryButtonClicked() {
        onRetry?()
    }
}
