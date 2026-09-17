import Foundation
#if os(macOS)
import AppKit
import Carbon
#endif

/// The built-in action set shared by both targets.
///
/// macOS stores Carbon-based action hotkeys on each action. iOS presents the
/// same actions in its menu and assigns independent logical-key defaults when
/// a hardware keyboard is attached.
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

    /// Engine-independent fallback scripts, keyed by canonical action name.
    /// Used only when neither a custom script nor an engine template provides
    /// one. Kept deliberately small: most actions have no generic form.
    private static let globalDefaultScripts: [String: String] = [
        "share": """
        const url = location.href;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(url);
        } else {
          throw new Error("Clipboard is unavailable");
        }
        """,
        // No website automation exists for this engine: an anonymous tab is
        // the honest answer. Throwing scripts still beep; this only fires
        // when no script exists at any level above.
        "new temporary session": "return { ephemeral: true };"
    ]

    /// The global default script for an action, regardless of engine.
    /// This is the last resort before "not implemented": custom scripts and
    /// engine template defaults always win.
    static func globalDefaultScript(for action: CustomAction) -> String? {
        let normalized = action.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return globalDefaultScripts[normalized]
    }
}

/// Default action-script resolution shared by both targets.
enum ActionScripts {
    /// The bundled action whose name matches, case-insensitive.
    static func defaultActionID(matching name: String) -> UUID? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return DefaultActions.defaults.first { $0.name.lowercased() == normalized }?.id
    }

    /// Whether an action is the bundled action with the given ID, matched by
    /// name. Action IDs are generated fresh per launch, so actions persisted
    /// from earlier launches never equal the runtime IDs; names are the
    /// stable identity. Single gate for all "is this the X action?" checks.
    static func isDefaultAction(_ action: CustomAction, id: UUID) -> Bool {
        defaultActionID(matching: action.name) == id
    }

    /// The bundled engine template matching a service name, case-insensitive.
    static func defaultServiceTemplate(for service: Service) -> Service? {
        let serviceName = service.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DefaultEngineDefinitions.definitions.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == serviceName
        }
    }

    /// The default custom CSS a service ships with, if its template provides one.
    static func defaultCustomCSS(for service: Service) -> String? {
        guard let template = defaultServiceTemplate(for: service),
              let css = template.customCSS?.trimmingCharacters(in: .whitespacesAndNewlines),
              !css.isEmpty else {
            return nil
        }
        return css
    }

    /// The bundled default custom CSS when the engine tracks the template's value,
    /// mirroring macOS `Settings.customCSS(for:)` resolution.
    static func syncedCustomCSS(for service: Service) -> String? {
        guard service.templateCustomCSSSync else { return nil }
        return defaultCustomCSS(for: service)
    }

    /// The custom CSS actually applied to a service's pages, mirroring macOS
    /// `Settings.customCSS(for:)`: a synced template wins, otherwise the
    /// file-backed stylesheet with the engine's stored copy as fallback.
    static func resolvedCustomCSS(for service: Service) -> String {
        if let syncedCSS = syncedCustomCSS(for: service) {
            return syncedCSS
        }
        return EngineFileStorage.loadCustomCSS(
            serviceID: service.id,
            fallback: service.customCSS ?? ""
        )
    }

    /// The action script actually used for a service and action, mirroring
    /// macOS `Settings.actionScript(for:action:)`: a synced template wins,
    /// otherwise the file-backed script with the engine's stored copy as
    /// fallback, otherwise the engine-independent global default. Empty means
    /// the action is unimplemented for the engine.
    static func resolvedActionScript(for service: Service, action: CustomAction) -> String {
        if let syncedScript = syncedActionScript(for: service, action: action) {
            return syncedScript
        }
        let stored = EngineFileStorage.loadActionScript(
            serviceID: service.id,
            actionID: action.id,
            fallback: service.actionScripts[action.id] ?? ""
        )
        if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return DefaultActions.globalDefaultScript(for: action) ?? ""
    }

    /// The bundled default script when the engine tracks the template's value.
    static func syncedActionScript(for service: Service, action: CustomAction) -> String? {
        guard service.templateActionScriptSync[action.id] == true else { return nil }
        return defaultScript(for: service, action: action)
    }

    /// The default prompt input selector an engine ships with, if its template provides one.
    static func defaultPromptInputSelector(for service: Service) -> String? {
        guard let template = defaultServiceTemplate(for: service) else {
            return nil
        }
        let selector = template.focus_selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return nil }
        return selector
    }

    /// The bundled default prompt input selector when the engine tracks the
    /// template's value, mirroring macOS `Settings.promptInputSelector(for:)`.
    static func syncedPromptInputSelector(for service: Service) -> String? {
        guard service.templatePromptInputSelectorSync else { return nil }
        return defaultPromptInputSelector(for: service)
    }

    /// The prompt input selector actually used for a service, mirroring macOS
    /// `Settings.promptInputSelector(for:)` resolution: a synced template wins,
    /// otherwise the engine's own stored selector.
    static func resolvedPromptInputSelector(for service: Service) -> String {
        if let syncedSelector = syncedPromptInputSelector(for: service) {
            return syncedSelector
        }
        return service.focus_selector
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
