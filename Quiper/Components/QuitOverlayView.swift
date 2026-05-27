import AppKit

@MainActor
final class QuitOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        layer?.masksToBounds = true
        
        let visualEffectView = NSVisualEffectView(frame: bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        addSubview(visualEffectView)
        
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 15
        container.alignment = .centerX
        container.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            container.widthAnchor.constraint(equalTo: visualEffectView.widthAnchor, multiplier: 0.8)
        ])
        
        // Spinning Progress
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.isIndeterminate = true
        progress.controlSize = .regular
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 28).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 28).isActive = true
        progress.startAnimation(nil)
        container.addArrangedSubview(progress)
        
        // Title Label
        let titleLabel = NSTextField(labelWithString: "Securing Storage")
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        container.addArrangedSubview(titleLabel)
        
        // Subtitle Label
        let subtitleLabel = NSTextField(labelWithString: "Safely locking and detaching secure profiles...")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isBezeled = false
        container.addArrangedSubview(subtitleLabel)
    }
    
    // Block all mouse interactions
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
}
