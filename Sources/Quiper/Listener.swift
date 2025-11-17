import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    struct Configuration: Codable, Equatable {
        var keyCode: UInt32
        var modifierFlags: UInt

        var cocoaFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifierFlags)
        }
    }

    static let defaultConfiguration = Configuration(
        keyCode: UInt32(kVK_Space),
        modifierFlags: NSEvent.ModifierFlags.option.rawValue
    )

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

    private var configuration: Configuration
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?
    private var captureOverlay: HotkeyCaptureOverlay?
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
        configuration = settings.hotkeyConfiguration
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
        guard let window else {
            completion(.failure(CaptureError.noWindow))
            return
        }

        let overlay = HotkeyCaptureOverlay(targetWindow: window) { [weak self] result in
            guard let self else { return }
            self.captureOverlay = nil
            switch result {
            case .captured(let config):
                self.applyNewConfiguration(config)
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

    private func applyNewConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
        settings.hotkeyConfiguration = configuration
        settings.saveSettings()
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
