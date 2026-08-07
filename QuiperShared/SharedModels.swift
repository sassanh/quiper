import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Routing

enum RoutingAction: String, Codable, CaseIterable, Identifiable {
    case internalStay = "Internal"
    case popup = "Popup"
    case prompt = "Prompt"
    case external = "Safari"

    var id: String { rawValue }
}

struct RoutingRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var pattern: String
    var action: RoutingAction

    init(id: UUID = UUID(), pattern: String, action: RoutingAction) {
        self.id = id
        self.pattern = pattern
        self.action = action
    }
}

// MARK: - Service

struct Service: Codable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var focus_selector: String
    var actionScripts: [UUID: String] = [:]
    #if os(macOS)
    var activationShortcut: HotkeyManager.Configuration?
    #endif
    var customCSS: String?
    var routingRules: [RoutingRule] = []
    var iconBase64: String?
    var iconManuallyUnset: Bool?
    var isEncrypted: Bool = false
    /// True once this engine's sparsebundle was created or migrated with diskutil.
    var usesDiskutilSparseBundle: Bool = false
    /// True once this engine's metadata has been migrated into the secure bundle.
    /// After migration, metadata fields are no longer persisted in settings.json.
    var hasMigratedMetadata: Bool = false
    var lockOnSwitchAway: Bool = true
    var lockAfterInactivity: Bool = false
    var autoLockInactivityTimeout: Int = 5
    var preservePrompt: Bool = true
    var templateActionScriptSync: [UUID: Bool] = [:]
    var templatePromptInputSelectorSync: Bool = false
    var templateCustomCSSSync: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case focus_selector
        case actionScripts
        case activationShortcut
        case routingRules
        case associatedDomains // legacy
        case friendDomains // legacy
        case customCSS
        case iconBase64
        case iconManuallyUnset
        case isEncrypted
        case usesDiskutilSparseBundle
        case hasMigratedMetadata
        case lockOnSwitchAway
        case lockAfterInactivity
        case autoLockInactivityTimeout
        case autoLockPolicy // Keep for decoding legacy settings
        case preservePrompt
        case templateActionScriptSync
        case templatePromptInputSelectorSync
        case templateCustomCSSSync
    }

    #if os(macOS)
    init(id: UUID = UUID(),
         name: String,
         url: String,
         focus_selector: String,
         actionScripts: [UUID: String] = [:],
         activationShortcut: HotkeyManager.Configuration? = nil,
         routingRules: [RoutingRule] = [],
         customCSS: String? = nil,
         iconBase64: String? = nil,
         iconManuallyUnset: Bool? = nil,
         isEncrypted: Bool = false,
         usesDiskutilSparseBundle: Bool = false,
         hasMigratedMetadata: Bool = false,
         lockOnSwitchAway: Bool = true,
         lockAfterInactivity: Bool = false,
         autoLockInactivityTimeout: Int = 5,
         preservePrompt: Bool = true,
         templateActionScriptSync: [UUID: Bool] = [:],
         templatePromptInputSelectorSync: Bool = false,
         templateCustomCSSSync: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
        self.activationShortcut = activationShortcut
        self.routingRules = routingRules
        self.customCSS = customCSS
        self.iconBase64 = iconBase64
        self.iconManuallyUnset = iconManuallyUnset
        self.isEncrypted = isEncrypted
        self.usesDiskutilSparseBundle = usesDiskutilSparseBundle
        self.hasMigratedMetadata = hasMigratedMetadata
        self.lockOnSwitchAway = lockOnSwitchAway
        self.lockAfterInactivity = lockAfterInactivity
        self.autoLockInactivityTimeout = autoLockInactivityTimeout
        self.preservePrompt = preservePrompt
        self.templateActionScriptSync = templateActionScriptSync
        self.templatePromptInputSelectorSync = templatePromptInputSelectorSync
        self.templateCustomCSSSync = templateCustomCSSSync
    }
    #else
    init(id: UUID = UUID(),
         name: String,
         url: String,
         focus_selector: String,
         actionScripts: [UUID: String] = [:],
         routingRules: [RoutingRule] = [],
         customCSS: String? = nil,
         iconBase64: String? = nil,
         iconManuallyUnset: Bool? = nil,
         isEncrypted: Bool = false,
         usesDiskutilSparseBundle: Bool = false,
         hasMigratedMetadata: Bool = false,
         lockOnSwitchAway: Bool = true,
         lockAfterInactivity: Bool = false,
         autoLockInactivityTimeout: Int = 5,
         preservePrompt: Bool = true,
         templateActionScriptSync: [UUID: Bool] = [:],
         templatePromptInputSelectorSync: Bool = false,
         templateCustomCSSSync: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
        self.routingRules = routingRules
        self.customCSS = customCSS
        self.iconBase64 = iconBase64
        self.iconManuallyUnset = iconManuallyUnset
        self.isEncrypted = isEncrypted
        self.usesDiskutilSparseBundle = usesDiskutilSparseBundle
        self.hasMigratedMetadata = hasMigratedMetadata
        self.lockOnSwitchAway = lockOnSwitchAway
        self.lockAfterInactivity = lockAfterInactivity
        self.autoLockInactivityTimeout = autoLockInactivityTimeout
        self.preservePrompt = preservePrompt
        self.templateActionScriptSync = templateActionScriptSync
        self.templatePromptInputSelectorSync = templatePromptInputSelectorSync
        self.templateCustomCSSSync = templateCustomCSSSync
    }
    #endif

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Service"
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        focus_selector = try container.decodeIfPresent(String.self, forKey: .focus_selector) ?? ""
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
        #if os(macOS)
        activationShortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .activationShortcut)
        #endif

        if let decodedRules = try container.decodeIfPresent([RoutingRule].self, forKey: .routingRules) {
            self.routingRules = decodedRules
        } else {
            let associated = try container.decodeIfPresent([String].self, forKey: .associatedDomains) ?? []
            let friend = try container.decodeIfPresent([String].self, forKey: .friendDomains) ?? []

            if !associated.isEmpty || !friend.isEmpty {
                var rules: [RoutingRule] = []
                for pat in associated {
                    let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("!") {
                        rules.append(RoutingRule(pattern: String(trimmed.dropFirst()), action: .external))
                    } else if trimmed.hasPrefix("+") {
                        rules.append(RoutingRule(pattern: String(trimmed.dropFirst()), action: .popup))
                    } else {
                        rules.append(RoutingRule(pattern: trimmed, action: .internalStay))
                    }
                }
                for pat in friend {
                    let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("!") {
                        rules.append(RoutingRule(pattern: String(trimmed.dropFirst()), action: .external))
                    } else if trimmed.hasPrefix("+") {
                        rules.append(RoutingRule(pattern: String(trimmed.dropFirst()), action: .popup))
                    } else {
                        rules.append(RoutingRule(pattern: trimmed, action: .prompt))
                    }
                }
                self.routingRules = rules
            } else {
                self.routingRules = []
            }
        }

        customCSS = try container.decodeIfPresent(String.self, forKey: .customCSS)
        iconBase64 = try container.decodeIfPresent(String.self, forKey: .iconBase64)
        iconManuallyUnset = try container.decodeIfPresent(Bool.self, forKey: .iconManuallyUnset)
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
        usesDiskutilSparseBundle = try container.decodeIfPresent(Bool.self, forKey: .usesDiskutilSparseBundle) ?? false
        hasMigratedMetadata = try container.decodeIfPresent(Bool.self, forKey: .hasMigratedMetadata) ?? false

        let switchAway = try container.decodeIfPresent(Bool.self, forKey: .lockOnSwitchAway)
        let inactivity = try container.decodeIfPresent(Bool.self, forKey: .lockAfterInactivity)

        if let switchAway = switchAway, let inactivity = inactivity {
            self.lockOnSwitchAway = switchAway
            self.lockAfterInactivity = inactivity
        } else if let legacyPolicy = try container.decodeIfPresent(AutoLockPolicy.self, forKey: .autoLockPolicy) {
            self.lockOnSwitchAway = (legacyPolicy == .onSwitchAway)
            self.lockAfterInactivity = (legacyPolicy == .afterInactivity)
        } else {
            self.lockOnSwitchAway = true
            self.lockAfterInactivity = false
        }

        autoLockInactivityTimeout = try container.decodeIfPresent(Int.self, forKey: .autoLockInactivityTimeout) ?? 5
        preservePrompt = try container.decodeIfPresent(Bool.self, forKey: .preservePrompt) ?? true
        templateActionScriptSync = try container.decodeIfPresent([UUID: Bool].self, forKey: .templateActionScriptSync) ?? [:]
        templatePromptInputSelectorSync = try container.decodeIfPresent(Bool.self, forKey: .templatePromptInputSelectorSync) ?? false
        templateCustomCSSSync = try container.decodeIfPresent(Bool.self, forKey: .templateCustomCSSSync) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        #if os(macOS)
        if let activationShortcut {
            try container.encode(activationShortcut, forKey: .activationShortcut)
        }
        #endif

        let isMigrated = isEncrypted && hasMigratedMetadata
        if !isMigrated {
            try container.encode(url, forKey: .url)
            try container.encode(focus_selector, forKey: .focus_selector)
            if !actionScripts.isEmpty {
                try container.encode(actionScripts, forKey: .actionScripts)
            }
            if !routingRules.isEmpty {
                try container.encode(routingRules, forKey: .routingRules)
            }
            if let customCSS, !customCSS.isEmpty {
                try container.encode(customCSS, forKey: .customCSS)
            }
            if let iconBase64 {
                try container.encode(iconBase64, forKey: .iconBase64)
            }
            if let iconManuallyUnset {
                try container.encode(iconManuallyUnset, forKey: .iconManuallyUnset)
            }
            try container.encode(preservePrompt, forKey: .preservePrompt)
            if !templateActionScriptSync.isEmpty {
                try container.encode(templateActionScriptSync, forKey: .templateActionScriptSync)
            }
            if templatePromptInputSelectorSync {
                try container.encode(templatePromptInputSelectorSync, forKey: .templatePromptInputSelectorSync)
            }
            if templateCustomCSSSync {
                try container.encode(templateCustomCSSSync, forKey: .templateCustomCSSSync)
            }
        }

        try container.encode(isEncrypted, forKey: .isEncrypted)
        if usesDiskutilSparseBundle {
            try container.encode(usesDiskutilSparseBundle, forKey: .usesDiskutilSparseBundle)
        }
        if isEncrypted {
            try container.encode(hasMigratedMetadata, forKey: .hasMigratedMetadata)
        }
        try container.encode(lockOnSwitchAway, forKey: .lockOnSwitchAway)
        try container.encode(lockAfterInactivity, forKey: .lockAfterInactivity)
        try container.encode(autoLockInactivityTimeout, forKey: .autoLockInactivityTimeout)
    }
}

extension Service: Equatable {}

// MARK: - Custom action

struct CustomAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    #if os(macOS)
    var shortcut: HotkeyManager.Configuration?
    #endif

    enum CodingKeys: String, CodingKey {
        case id, name
        #if os(macOS)
        case shortcut
        #endif
    }

    #if os(macOS)
    init(id: UUID = UUID(), name: String, shortcut: HotkeyManager.Configuration? = nil) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
    }
    #else
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    #endif
}

extension CustomAction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        #if os(macOS)
        shortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .shortcut)
        #endif
    }

    #if os(macOS)
    var displayShortcut: String {
        guard let shortcut else { return "Not assigned" }
        return ShortcutFormatter.string(for: shortcut)
    }
    #endif
}

// MARK: - Tabs and prompt history

struct TabIdentifier: Equatable, Codable, Hashable {
    let serviceID: UUID
    let sessionIndex: Int
}

struct TabInputState: Codable, Equatable {
    var text: String
    var isContentEditable: Bool
    var start: Int
    var end: Int
}

struct PromptHistoryEntry: Codable, Equatable {
    var text: String
    var timestamp: Date
}

enum PromptHistoryPolicy {
    /// Builds a recordable history entry for a submitted prompt, or nil when the
    /// text is too short to keep. Stores the original (untrimmed) text.
    static func makeEntryIfEligible(submittedText: String) -> PromptHistoryEntry? {
        let trimmed = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        return PromptHistoryEntry(text: submittedText, timestamp: Date())
    }
}

enum TabSurvivalPolicy: String, Codable, CaseIterable, Identifiable {
    case always = "Always Restore"
    case askOnExit = "Ask on Exit"
    case never = "Never Restore"

    var id: String { rawValue }
}

// MARK: - Auto lock

enum AutoLockPolicy: String, Codable, CaseIterable, Identifiable {
    case onAppQuit = "On App Quit"
    case onSwitchAway = "On Switch Away"
    case afterInactivity = "After Inactivity"

    var id: String { rawValue }
}
