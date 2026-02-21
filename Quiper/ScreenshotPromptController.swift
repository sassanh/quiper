
import AppKit
import SwiftUI

@MainActor
final class ScreenshotPromptController: NSWindowController {
    
    private let nameLabel = NSTextField(labelWithString: "")
    private let captureButton = NSButton(title: "Take Screenshot", target: nil, action: #selector(captureClicked))
    
    var onCapture: (() -> Void)?
    
    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isFloatingPanel = true
        window.title = "Screenshot Step"
        window.center()
        
        super.init(window: window)
        
        setupUI()
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowPrompt(_:)),
            name: NSNotification.Name("app.sassanh.quiper.ShowCapturePrompt"),
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        let title = NSTextField(labelWithString: "About to capture:")
        title.font = .systemFont(ofSize: 12)
        title.alignment = .center
        
        nameLabel.font = .boldSystemFont(ofSize: 16)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        
        captureButton.bezelStyle = .rounded
        captureButton.keyEquivalent = "\r" // Enter key
        captureButton.target = self
        captureButton.setAccessibilityIdentifier("TakeScreenshotButton")
        
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(captureButton)
        
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        ])
    }
    
    @objc private func handleShowPrompt(_ notification: Notification) {
        let name = notification.object as? String ?? "Unknown"
        show(name: name)
    }
    
    func show(name: String) {
        nameLabel.stringValue = name
        window?.makeKeyAndOrderFront(nil)
        // Position at the top of the screen to stay out of the way
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 300) / 2
            let y = screen.frame.height - 150
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    @objc private func captureClicked() {
        window?.orderOut(nil)
        onCapture?()
    }
}
