import AppKit
import Carbon

@MainActor
final class HotkeyCaptureOverlay {
    enum Result {
        case captured(HotkeyManager.Configuration)
        case cancelled
    }

    private weak var targetWindow: NSWindow?
    private var overlayWindow: NSPanel?
    private var monitor: Any?
    private let completion: (Result) -> Void
    private let displayField = NSTextField(labelWithString: "Waiting for key press…")

    init(targetWindow: NSWindow, completion: @escaping (Result) -> Void) {
        self.targetWindow = targetWindow
        self.completion = completion
    }

    func present() {
        guard let targetWindow else {
            completion(.cancelled)
            return
        }
        let panel = NSPanel(contentRect: targetWindow.frame,
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = NSView(frame: panel.contentView?.bounds ?? .zero)
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        panel.contentView = overlayView

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let message = NSTextField(labelWithString: "Press the new hotkey combination")
        message.font = NSFont.boldSystemFont(ofSize: 17)
        message.alignment = .center

        displayField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        displayField.alignment = .center
        displayField.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [message, displayField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        overlayView.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 420),
            container.heightAnchor.constraint(equalToConstant: 180)
        ])

        panel.makeKeyAndOrderFront(nil)
        overlayWindow = panel
        attachKeyMonitor()
    }

    private func attachKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.finish(.cancelled)
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let configuration = HotkeyManager.Configuration(keyCode: UInt32(event.keyCode), modifierFlags: modifiers.rawValue)
            self.displayField.stringValue = ShortcutFormatter.string(for: modifiers, keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            self.finish(.captured(configuration))
            return nil
        }
    }

    private func finish(_ result: Result) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let panel = overlayWindow {
            panel.orderOut(nil)
            overlayWindow = nil
        }
        completion(result)
    }
}
