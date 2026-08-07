import Foundation
#if os(macOS)
import AppKit
import Carbon
#endif

/// The built-in action set shared by both targets.
///
/// macOS surfaces these through the recorded hotkeys; iOS has no keyboard, so
/// the same actions are offered from the Actions menu instead.
enum DefaultActions {
    static let defaults: [CustomAction] = [
        newSessionAction,
        newTemporarySessionAction,
        shareAction,
        historyAction,
        settingsAction
    ]

    #if os(macOS)
    private static let newSessionAction = CustomAction(
        id: DefaultEngineDefinitions.newSessionActionID,
        name: "New Session",
        shortcut: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
    )
    private static let newTemporarySessionAction = CustomAction(
        id: DefaultEngineDefinitions.newTemporarySessionActionID,
        name: "New Temporary Session",
        shortcut: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )
    )
    private static let shareAction = CustomAction(
        id: DefaultEngineDefinitions.shareActionID,
        name: "Share",
        shortcut: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_S),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )
    )
    private static let historyAction = CustomAction(
        id: DefaultEngineDefinitions.historyActionID,
        name: "History",
        shortcut: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_H),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )
    )
    private static let settingsAction = CustomAction(
        id: DefaultEngineDefinitions.openSettingsActionID,
        name: "Settings",
        shortcut: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_Comma),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
    )
    #else
    private static let newSessionAction = CustomAction(
        id: DefaultEngineDefinitions.newSessionActionID,
        name: "New Session"
    )
    private static let newTemporarySessionAction = CustomAction(
        id: DefaultEngineDefinitions.newTemporarySessionActionID,
        name: "New Temporary Session"
    )
    private static let shareAction = CustomAction(
        id: DefaultEngineDefinitions.shareActionID,
        name: "Share"
    )
    private static let historyAction = CustomAction(
        id: DefaultEngineDefinitions.historyActionID,
        name: "History"
    )
    private static let settingsAction = CustomAction(
        id: DefaultEngineDefinitions.openSettingsActionID,
        name: "Settings"
    )
    #endif
}

/// Default action-script resolution shared by both targets.
enum ActionScripts {
    /// The bundled action whose name matches, case-insensitive.
    static func defaultActionID(matching name: String) -> UUID? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return DefaultActions.defaults.first { $0.name.lowercased() == normalized }?.id
    }

    /// The bundled engine template matching a service name, case-insensitive.
    static func defaultServiceTemplate(for service: Service) -> Service? {
        let serviceName = service.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DefaultEngineDefinitions.definitions.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == serviceName
        }
    }

    /// The default script an action ships with for a service, if a template provides one.
    static func defaultScript(for service: Service, action: CustomAction) -> String? {
        guard let template = defaultServiceTemplate(for: service),
              let defaultID = defaultActionID(matching: action.name),
              let script = template.actionScripts[defaultID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty else {
            return nil
        }
        return script
    }
}
