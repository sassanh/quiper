import Foundation

/// All engine metadata that should be stored exclusively in the secure bundle
/// once migration is complete. Separated from behavioral settings that remain
/// in plaintext settings.json. This includes the engine's external link
/// routing records: while the volume is locked nothing outside it carries
/// the claimed domains, so a locked engine claims no links.
struct SecuredEngineMetadata: Codable, Equatable {
    var url: String
    var engineType: EngineType = .singleURL
    var pinnedTabURLs: [String] = []
    var focusSelector: String
    var iconBase64: String?
    var iconManuallyUnset: Bool?
    #if os(macOS)
    var legacyActivationShortcut: HotkeyConfiguration?
    #endif
    var customCSS: String?
    var routingRules: [RoutingRule]
    var actionScripts: [UUID: String]
    var preservePrompt: Bool
    var templateActionScriptSync: [UUID: Bool]
    var templatePromptInputSelectorSync: Bool
    var templateCustomCSSSync: Bool
    var lockOnSwitchAway: Bool?
    var lockAfterInactivity: Bool?
    var autoLockInactivityTimeout: Int?
    var externalLinkHandler: ExternalLinkHandler = ExternalLinkHandler()

    enum CodingKeys: String, CodingKey {
        case url, engineType, pinnedTabURLs, focusSelector, iconBase64, iconManuallyUnset
        #if os(macOS)
        case legacyActivationShortcut = "activationShortcut"
        #endif
        case customCSS, routingRules, actionScripts
        case preservePrompt, templateActionScriptSync
        case templatePromptInputSelectorSync, templateCustomCSSSync
        case lockOnSwitchAway, lockAfterInactivity, autoLockInactivityTimeout
        case externalLinkHandler
    }

    init(from service: Service) {
        self.url = service.url
        self.engineType = service.engineType
        self.pinnedTabURLs = service.pinnedTabURLs
        self.focusSelector = service.focus_selector
        self.iconBase64 = service.iconBase64
        self.iconManuallyUnset = service.iconManuallyUnset
        #if os(macOS)
        self.legacyActivationShortcut = nil
        #endif
        self.customCSS = service.customCSS
        self.routingRules = service.routingRules
        self.actionScripts = service.actionScripts
        self.preservePrompt = service.preservePrompt
        self.templateActionScriptSync = service.templateActionScriptSync
        self.templatePromptInputSelectorSync = service.templatePromptInputSelectorSync
        self.templateCustomCSSSync = service.templateCustomCSSSync
        self.lockOnSwitchAway = service.lockOnSwitchAway
        self.lockAfterInactivity = service.lockAfterInactivity
        self.autoLockInactivityTimeout = service.autoLockInactivityTimeout
        self.externalLinkHandler = service.externalLinkHandler
    }

    /// Whether the bundle carries no metadata worth keeping. Guards the
    /// persistence gate against overwriting secure storage with empty values.
    var isEmpty: Bool {
        let hasPinnedURLs = pinnedTabURLs.contains(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        return url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasPinnedURLs
            && focusSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && actionScripts.isEmpty
            && routingRules.isEmpty
            && !externalLinkHandler.isConfigured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        engineType = try container.decodeIfPresent(EngineType.self, forKey: .engineType) ?? .singleURL
        let decodedPinned = try container.decodeIfPresent([String].self, forKey: .pinnedTabURLs) ?? []
        pinnedTabURLs = engineType == .pinnedTabs
            ? Service.normalizedPinnedTabURLs(decodedPinned)
            : []
        focusSelector = try container.decodeIfPresent(String.self, forKey: .focusSelector) ?? ""
        iconBase64 = try container.decodeIfPresent(String.self, forKey: .iconBase64)
        iconManuallyUnset = try container.decodeIfPresent(Bool.self, forKey: .iconManuallyUnset)
        #if os(macOS)
        legacyActivationShortcut = try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .legacyActivationShortcut)
        #endif
        customCSS = try container.decodeIfPresent(String.self, forKey: .customCSS)
        routingRules = try container.decodeIfPresent([RoutingRule].self, forKey: .routingRules) ?? []
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
        preservePrompt = try container.decodeIfPresent(Bool.self, forKey: .preservePrompt) ?? true
        templateActionScriptSync = try container.decodeIfPresent([UUID: Bool].self, forKey: .templateActionScriptSync) ?? [:]
        templatePromptInputSelectorSync = try container.decodeIfPresent(Bool.self, forKey: .templatePromptInputSelectorSync) ?? false
        templateCustomCSSSync = try container.decodeIfPresent(Bool.self, forKey: .templateCustomCSSSync) ?? false
        lockOnSwitchAway = try container.decodeIfPresent(Bool.self, forKey: .lockOnSwitchAway)
        lockAfterInactivity = try container.decodeIfPresent(Bool.self, forKey: .lockAfterInactivity)
        autoLockInactivityTimeout = try container.decodeIfPresent(Int.self, forKey: .autoLockInactivityTimeout)
        externalLinkHandler = try container.decodeIfPresent(ExternalLinkHandler.self, forKey: .externalLinkHandler)
            ?? ExternalLinkHandler()
    }

    func apply(to service: inout Service) {
        service.url = url
        service.engineType = engineType
        service.pinnedTabURLs = engineType == .pinnedTabs
            ? Service.normalizedPinnedTabURLs(pinnedTabURLs)
            : []
        service.focus_selector = focusSelector
        service.iconBase64 = iconBase64
        service.iconManuallyUnset = iconManuallyUnset
        service.customCSS = customCSS
        service.routingRules = routingRules
        service.actionScripts = actionScripts
        service.preservePrompt = preservePrompt
        service.templateActionScriptSync = templateActionScriptSync
        service.templatePromptInputSelectorSync = templatePromptInputSelectorSync
        service.templateCustomCSSSync = templateCustomCSSSync
        service.externalLinkHandler = externalLinkHandler
        if let lockOnSwitchAway {
            service.lockOnSwitchAway = lockOnSwitchAway
        }
        if let lockAfterInactivity {
            service.lockAfterInactivity = lockAfterInactivity
        }
        if let autoLockInactivityTimeout {
            service.autoLockInactivityTimeout = autoLockInactivityTimeout
        }
    }
}
