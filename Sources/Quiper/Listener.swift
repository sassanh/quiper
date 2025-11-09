import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    struct Configuration: Codable {
        var keyCode: UInt32
        var modifierFlags: UInt

        var cocoaFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifierFlags)
        }
    }

    enum CaptureError: LocalizedError {
        case noWindow
        case cancelled
        case registrationFailed

        var errorDescription: String? {
            switch self {
            case .noWindow:
                return "Unable to show hotkey capture overlay."
            case .cancelled:
                return "Hotkey selection cancelled."
            case .registrationFailed:
                return "Failed to register the selected hotkey."
            }
        }
    }

    private static let configURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/quiper", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("hotkey_config.json")
    }()

    private var configuration: Configuration
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?
    private var captureOverlay: HotkeyCaptureOverlay?

    init() {
        configuration = Self.loadConfiguration()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.unregisterHotKey()
            if let handler = self?.eventHandler {
                RemoveEventHandler(handler)
            }
        }
    }

    func registerCurrentHotkey(_ callback: @escaping () -> Void) {
        self.callback = callback
        registerHotKey(with: configuration)
    }

    func beginCapture(from window: NSWindow?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let window, let contentView = window.contentView else {
            completion(.failure(CaptureError.noWindow))
            return
        }

        let overlay = HotkeyCaptureOverlay(targetView: contentView) { [weak self] result in
            guard let self else { return }
            self.captureOverlay = nil
            switch result {
            case .captured(let config):
                self.configuration = config
                self.saveConfiguration()
                if self.registerHotKey(with: config) {
                    completion(.success(()))
                } else {
                    completion(.failure(CaptureError.registrationFailed))
                }
            case .cancelled:
                completion(.failure(CaptureError.cancelled))
            }
        }
        captureOverlay = overlay
        overlay.present()
    }

    // MARK: - Persistence
    private static func loadConfiguration() -> Configuration {
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            return Configuration(keyCode: UInt32(kVK_Space), modifierFlags: NSEvent.ModifierFlags.option.rawValue)
        }
    }

    private func saveConfiguration() {
        do {
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: Self.configURL)
        } catch {
            NSLog("[Quiper] Failed to save hotkey configuration: \(error)")
        }
    }

    // MARK: - Hotkey registration
    @discardableResult
    private func registerHotKey(with configuration: Configuration) -> Bool {
        unregisterHotKey()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x51555052)), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            configuration.keyCode,
            carbonFlags(from: configuration.cocoaFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            return true
        }
        return false
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.callback?()
            }
            return noErr
        }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

@MainActor
private final class HotkeyCaptureOverlay {
    enum Result {
        case captured(HotkeyManager.Configuration)
        case cancelled
    }

    private weak var targetView: NSView?
    private var monitor: Any?
    private let completion: (Result) -> Void
    private let overlayView = NSView()
    private let displayField = NSTextField(labelWithString: "Waiting for key press…")

    init(targetView: NSView, completion: @escaping (Result) -> Void) {
        self.targetView = targetView
        self.completion = completion
        configureOverlay()
    }

    func present() {
        guard let targetView else {
            completion(.cancelled)
            return
        }
        targetView.addSubview(overlayView)
        overlayView.frame = targetView.bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlayView.animator().alphaValue = 1.0
        }
        attachKeyMonitor()
    }

    private func configureOverlay() {
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor

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
            self.displayField.stringValue = self.displayString(for: modifiers, keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            self.finish(.captured(configuration))
            return nil
        }
    }

    private func finish(_ result: Result) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            overlayView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.overlayView.removeFromSuperview()
            }
        })
        completion(result)
    }

    private func displayString(for modifiers: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        parts.append(keyName(for: keyCode, fallback: characters))
        return parts.joined(separator: " + ")
    }

    private func keyName(for keyCode: UInt16, fallback: String?) -> String {
        if let special = specialKeys[keyCode] {
            return special
        }
        if let fallback, let scalar = fallback.uppercased().first {
            return String(scalar)
        }
        return "Key \(keyCode)"
    }

    private let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Escape): "Escape",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_ANSI_KeypadEnter): "Enter",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12"
    ]
}
