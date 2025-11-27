import AppKit

@MainActor
protocol CustomActionProvider: AnyObject {
    var customActions: [CustomAction] { get }
}

@MainActor
final class CustomActionShortcutDispatcher {
    private var monitor: Any?
    private weak var windowController: MainWindowControlling?
    private let actionProvider: CustomActionProvider

    init(actionProvider: CustomActionProvider = Settings.shared) {
        self.actionProvider = actionProvider
    }

    func startMonitoring(windowController: MainWindowControlling) {
        self.windowController = windowController
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        windowController = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let configuration = HotkeyManager.Configuration(keyCode: UInt32(event.keyCode), modifierFlags: modifiers.rawValue)
        guard ShortcutValidator.allows(configuration: configuration) else { return false }
        
        guard let action = actionProvider.customActions.first(where: { action in
            guard let shortcut = action.shortcut else { return false }
            return shortcut.keyCode == configuration.keyCode && shortcut.modifierFlags == configuration.modifierFlags
        }) else { return false }
        
        if ShortcutRecordingState.isRecording {
            NotificationCenter.default.post(name: .shortcutRecordingDidTriggerReserved, object: configuration)
            return true
        }
        
        guard let controller = windowController else { return false }
        controller.focusInputInActiveWebview()
        controller.logCustomAction(action)
        return true
    }
}
extension CustomActionShortcutDispatcher: CustomActionDispatching {}
