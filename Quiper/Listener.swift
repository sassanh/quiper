import AppKit
import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    struct Configuration: Codable, Equatable {
        var keyCode: UInt32
        var modifierFlags: UInt

        var cocoaFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifierFlags)
        }

        var isDisabled: Bool {
            keyCode == 0 && modifierFlags == 0
        }
    }

    func updateConfiguration(_ configuration: Configuration) {
        applyNewConfiguration(configuration)
        _ = registerHotKey(with: configuration)
    }

    static let defaultConfiguration = Configuration(
        keyCode: UInt32(kVK_Space),
        modifierFlags: NSEvent.ModifierFlags.option.rawValue
    )

    private var configuration: Configuration
    private var hotKeyRef: EventHotKeyRef?
    private var devHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?
    private let settings: Settings
    private let hotKeySignature = OSType(UInt32(truncatingIfNeeded: 0x51555052))

    init(settings: Settings? = nil) {
        self.settings = settings ?? .shared
        configuration = self.settings.hotkeyConfiguration
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

    // MARK: - Hotkey registration
    @discardableResult
    private func registerHotKey(with configuration: Configuration) -> Bool {
        unregisterHotKey()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            configuration.keyCode,
            carbonFlags(from: configuration.cocoaFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        
        NSLog("[Quiper] RegisterEventHotKey keyCode=\(configuration.keyCode) status=\(status)")
        
        if status == noErr {
            hotKeyRef = ref
            registerDevFallbackHotkeyIfNeeded(for: configuration)
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
        unregisterDevFallbackHotkey()
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
            
            if ShortcutRecordingState.isRecording {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    NotificationCenter.default.post(name: .shortcutRecordingDidTriggerReserved, object: manager.configuration)
                }
                return noErr
            }
            
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

    private func registerDevFallbackHotkeyIfNeeded(for configuration: Configuration) {
        guard DevEnvironment.isRunningInXcode else {
            unregisterDevFallbackHotkey()
            return
        }
        guard usesDefaultOptionSpace(configuration) else {
            unregisterDevFallbackHotkey()
            return
        }
        unregisterDevFallbackHotkey()

        var fallbackRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 2)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            carbonFlags(from: [.control]),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &fallbackRef
        )
        if status == noErr {
            devHotKeyRef = fallbackRef
        }
    }

    private func unregisterDevFallbackHotkey() {
        if let ref = devHotKeyRef {
            UnregisterEventHotKey(ref)
            devHotKeyRef = nil
        }
    }

    private func usesDefaultOptionSpace(_ configuration: Configuration) -> Bool {
        let normalized = configuration.cocoaFlags.intersection([.command, .option, .control, .shift])
        return configuration.keyCode == UInt32(kVK_Space) && normalized == [.option]
    }
}

// MARK: - Per-engine hotkeys

final class EngineHotkeyManager {
    struct Entry: Equatable {
        var serviceID: UUID
        var configuration: HotkeyManager.Configuration
    }

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var identifiersByService: [UUID: UInt32] = [:]
    private var serviceIDByIdentifier: [UInt32: UUID] = [:]
    private var configurationByService: [UUID: HotkeyManager.Configuration] = [:]
    private var onTrigger: ((UUID) -> Void)?
    private var nextIdentifier: UInt32 = 1
    private let hotKeySignature = OSType(UInt32(truncatingIfNeeded: 0x51454E47)) // 'QENG'
    private func assertMainThread() {
        assert(Thread.isMainThread, "EngineHotkeyManager must be used on the main thread")
    }

    deinit {
        assertMainThread()
        reset()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    func register(entries: [Entry], onTrigger: @escaping (UUID) -> Void) {
        assertMainThread()
        reset()
        installHandlerIfNeeded()
        self.onTrigger = onTrigger

        var seenConfigurations: [HotkeyManager.Configuration] = []

        for entry in entries {
            if seenConfigurations.contains(entry.configuration) {
                continue
            }
            seenConfigurations.append(entry.configuration)
            register(entry: entry)
        }
    }

    func reset() {
        assertMainThread()
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        identifiersByService.removeAll()
        serviceIDByIdentifier.removeAll()
        configurationByService.removeAll()
        onTrigger = nil
        nextIdentifier = 1
    }

    func disable() {
        reset()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    func update(configuration: HotkeyManager.Configuration, for serviceID: UUID) {
        assertMainThread()
        unregister(serviceID: serviceID)
        let entry = Entry(serviceID: serviceID, configuration: configuration)
        register(entry: entry)
    }

    func unregister(serviceID: UUID) {
        assertMainThread()
        guard let identifier = identifiersByService[serviceID] else { return }
        if let ref = hotKeyRefs[serviceID] {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeValue(forKey: serviceID)
        identifiersByService.removeValue(forKey: serviceID)
        serviceIDByIdentifier.removeValue(forKey: identifier)
        configurationByService.removeValue(forKey: serviceID)
    }

    private func register(entry: Entry) {
        assertMainThread()
        let identifier = nextIdentifier
        nextIdentifier &+= 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: identifier)
        let status = RegisterEventHotKey(entry.configuration.keyCode,
                                         carbonFlags(from: entry.configuration.cocoaFlags),
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return }
        hotKeyRefs[entry.serviceID] = ref
        identifiersByService[entry.serviceID] = identifier
        serviceIDByIdentifier[identifier] = entry.serviceID
        configurationByService[entry.serviceID] = entry.configuration
    }

    private func installHandlerIfNeeded() {
        assertMainThread()
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<EngineHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            
            if ShortcutRecordingState.isRecording {
                if status == noErr {
                    let config = manager.configuration(for: hotKeyID)
                    if let config {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .shortcutRecordingDidTriggerReserved, object: config)
                        }
                    }
                }
                return noErr
            }
            
            if status == noErr, manager.handleHotkey(hotKeyID: hotKeyID) {
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)
    }

    func configuration(for hotKeyID: EventHotKeyID) -> HotkeyManager.Configuration? {
        assertMainThread()
        guard hotKeyID.signature == hotKeySignature,
              let serviceID = serviceIDByIdentifier[hotKeyID.id] else { return nil }
        return configurationByService[serviceID]
    }
    
    @discardableResult
    private func handleHotkey(hotKeyID: EventHotKeyID) -> Bool {
        assertMainThread()
        guard hotKeyID.signature == hotKeySignature,
              let serviceID = serviceIDByIdentifier[hotKeyID.id] else { return false }
        onTrigger?(serviceID)
        return true
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

#if DEBUG
private enum DevEnvironment {
    static let isRunningInXcode: Bool = {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil {
            return true
        }
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/DerivedData/") {
            return true
        }
        if let serviceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
           serviceName.contains("com.apple.dt.Xcode") {
            return true
        }
        return false
    }()
}
#else
private enum DevEnvironment {
    static let isRunningInXcode = false
}
#endif
