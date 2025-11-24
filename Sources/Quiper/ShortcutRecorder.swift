import SwiftUI
import Carbon

class ShortcutRecordingState: ObservableObject {
    @Published var isPresenting = false
    @Published var message = ""
    
    nonisolated(unsafe) public static var isRecording = false
    
    private var currentSession: CancellableSession?
    
    func start(session: CancellableSession) {
        currentSession?.cancel()
        currentSession = session
        Self.isRecording = true
        withAnimation {
            isPresenting = true
        }
    }
    
    func cancel() {
        currentSession?.cancel()
        currentSession = nil
        Self.isRecording = false
        withAnimation {
            isPresenting = false
        }
        message = ""
    }
    
    func updateMessage(_ newMessage: String) {
        message = newMessage
    }
}

protocol CancellableSession {
    func cancel()
}

final class StandardShortcutSession: CancellableSession, @unchecked Sendable {
    private var monitor: Any?
    private var notificationObserver: Any?
    private let onUpdate: (String) -> Void
    private let completion: (HotkeyManager.Configuration?) -> Void
    private let onFinish: () -> Void
    private let additionalValidation: ((NSEvent) -> String?)?
    
    init(onUpdate: @escaping (String) -> Void,
         onFinish: @escaping () -> Void,
         additionalValidation: ((NSEvent) -> String?)? = nil,
         completion: @escaping (HotkeyManager.Configuration?) -> Void) {
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        self.additionalValidation = additionalValidation
        self.completion = completion
        self.onUpdate("Press the new shortcut")
        attachKeyMonitor()
        attachNotificationObserver()
    }
    
    func cancel() {
        finish(nil)
    }
    
    private func attachKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.finish(nil)
                return nil
            }
            
            // Check additional validation first (e.g. reserved shortcuts)
            if let error = self.additionalValidation?(event) {
                NSSound.beep()
                self.onUpdate(error)
                return nil
            }
            
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let configuration = HotkeyManager.Configuration(keyCode: UInt32(event.keyCode), modifierFlags: modifiers.rawValue)
            
            guard ShortcutValidator.hasRequiredModifiers(modifiers: modifiers, keyCode: event.keyCode) else {
                NSSound.beep()
                self.onUpdate("Shortcut must include Command/Option/Control/Shift unless using F1–F20")
                return nil
            }
            
            // Check if shortcut is reserved
            let shortcutString = ShortcutFormatter.string(for: modifiers, keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            let actionName = MainActor.assumeIsolated {
                Settings.shared.getReservedActionName(for: configuration)
            }
            if let actionName {
                NSSound.beep()
                self.onUpdate("\(shortcutString) is reserved for '\(actionName)'")
                return nil
            }
            
            self.onUpdate(shortcutString)
            self.finish(configuration)
            return nil
        }
    }
    
    private func attachNotificationObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .shortcutRecordingDidTriggerReserved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let config = notification.object as? HotkeyManager.Configuration else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let shortcutString = ShortcutFormatter.string(for: config)
                if let actionName = Settings.shared.getReservedActionName(for: config) {
                    NSSound.beep()
                    self.onUpdate("\(shortcutString) is reserved for '\(actionName)'")
                }
            }
        }
    }
    
    private var isFinished = false

    private func finish(_ configuration: HotkeyManager.Configuration?) {
        guard !isFinished else { return }
        isFinished = true
        
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            self.notificationObserver = nil
        }
        completion(configuration)
        onFinish()
    }
}

struct ShortcutRecordingOverlay: View {
    @ObservedObject var state: ShortcutRecordingState
    
    var body: some View {
        if state.isPresenting {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Press the new shortcut")
                        .font(.headline)
                    if !state.message.isEmpty {
                        Text(state.message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button("Cancel") {
                        state.cancel()
                    }
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(18)
            }
            .transition(.opacity)
        }
    }
}
