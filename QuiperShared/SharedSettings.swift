import Foundation
#if os(macOS)
import AppKit
#else
import SwiftUI
#endif

// MARK: - Appearance enums

enum DockVisibility: String, Codable, Equatable, CaseIterable, Identifiable {
    case never = "Never"
    case whenVisible = "When Visible"
    case always = "Always"

    var id: String { rawValue }
}

enum SelectorDisplayMode: String, Codable, CaseIterable, Identifiable {
    case expanded = "Expanded"   // Always show all segments
    case compact = "Compact"     // Collapsible, show one + expand on hover
    case auto = "Auto"           // Switch based on window width

    var id: String { rawValue }
}

enum TopBarVisibility: String, Codable, Equatable, CaseIterable, Identifiable {
    case visible = "Visible"
    case hidden = "Hidden"

    var id: String { rawValue }
}

enum DragAreaPosition: String, Codable, Equatable, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"

    var id: String { rawValue }
}

// MARK: - Update preferences

enum UpdateChannel: String, Codable, Equatable, CaseIterable, Identifiable {
    case stable = "Stable"
    case beta = "Beta"
    case nightly = "Nightly"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .stable: return "Production-ready builds"
        case .beta: return "Stable + Pre-releases"
        case .nightly: return "Stable + Beta + Nightlies"
        }
    }
}

struct UpdatePreferences: Codable, Equatable {
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var channel: UpdateChannel = .stable
    var lastAutomaticCheck: Date?
    var lastNotifiedVersion: String?
    var lastNotifiedDate: Date?

    private enum CodingKeys: String, CodingKey {
        case automaticallyChecksForUpdates
        case automaticallyDownloadsUpdates
        case channel
        case lastAutomaticCheck
        case lastNotifiedVersion
        case lastNotifiedDate

        // Legacy keys for migration (decoding only)
        case includeBetaChannel
        case includeNightlyChannel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(automaticallyChecksForUpdates, forKey: .automaticallyChecksForUpdates)
        try container.encode(automaticallyDownloadsUpdates, forKey: .automaticallyDownloadsUpdates)
        try container.encode(channel, forKey: .channel)
        try container.encodeIfPresent(lastAutomaticCheck, forKey: .lastAutomaticCheck)
        try container.encodeIfPresent(lastNotifiedVersion, forKey: .lastNotifiedVersion)
        try container.encodeIfPresent(lastNotifiedDate, forKey: .lastNotifiedDate)
    }
}

extension UpdatePreferences {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticallyChecksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
        automaticallyDownloadsUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyDownloadsUpdates) ?? false

        // Handle migration from individual toggles to hierarchical channel
        if let channel = try container.decodeIfPresent(UpdateChannel.self, forKey: .channel) {
            self.channel = channel
        } else {
            let nightly = try container.decodeIfPresent(Bool.self, forKey: .includeNightlyChannel) ?? false
            let beta = try container.decodeIfPresent(Bool.self, forKey: .includeBetaChannel) ?? false

            if nightly {
                self.channel = .nightly
            } else if beta {
                self.channel = .beta
            } else {
                self.channel = .stable
            }
        }

        lastAutomaticCheck = try container.decodeIfPresent(Date.self, forKey: .lastAutomaticCheck)
        lastNotifiedVersion = try container.decodeIfPresent(String.self, forKey: .lastNotifiedVersion)
        lastNotifiedDate = try container.decodeIfPresent(Date.self, forKey: .lastNotifiedDate)
    }
}

// MARK: - Color scheme

enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    #if os(macOS)
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    #else
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    #endif
}

enum SettingsColorStyle: String, Codable, CaseIterable, Identifiable {
    case colorful = "Colorful"
    case classic = "Classic"

    var id: String { rawValue }
}

enum PromptRecordingIndicatorStyle: String, Codable, CaseIterable, Identifiable {
    case glow = "Glow"
    case dashed = "Dashed"
    case off = "Off"

    var id: String { rawValue }
}

// MARK: - Window appearance

enum WindowBackgroundMode: String, Codable, CaseIterable, Identifiable {
    case macOSEffects = "macOS Effects"
    case solidColor = "Solid Color"

    var id: String { rawValue }

    // Custom decoder to migrate legacy "Blur Effect" value
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle legacy "Blur Effect" value
        if rawValue == "Blur Effect" {
            self = .macOSEffects
        } else if let mode = WindowBackgroundMode(rawValue: rawValue) {
            self = mode
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown WindowBackgroundMode: \(rawValue)")
        }
    }
}

enum WindowMaterial: String, Codable, CaseIterable, Identifiable {
    case underWindowBackground = "Under Window"
    case sidebar = "Sidebar"
    case hudWindow = "HUD"
    case popover = "Popover"
    case menu = "Menu"
    case headerView = "Header"
    case contentBackground = "Content"

    var id: String { rawValue }

    #if os(macOS)
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .underWindowBackground: return .underWindowBackground
        case .sidebar: return .sidebar
        case .hudWindow: return .hudWindow
        case .popover: return .popover
        case .menu: return .menu
        case .headerView: return .headerView
        case .contentBackground: return .contentBackground
        }
    }
    #endif
}

struct ThemeAppearanceSettings: Codable, Equatable {
    var mode: WindowBackgroundMode = .solidColor
    var material: WindowMaterial = .underWindowBackground
    var backgroundColor: CodableColor
    var blurRadius: Double = 1.0  // 1 = no blur, higher = more blur
    var outlineWidth: Double = 1.0
    var outlineColor: CodableColor

    static let defaultLight = ThemeAppearanceSettings(
        mode: .solidColor,
        material: .underWindowBackground,
        backgroundColor: CodableColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 0.60),
        blurRadius: 40.0,
        outlineWidth: 1.0,
        outlineColor: CodableColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    )

    static let defaultDark = ThemeAppearanceSettings(
        mode: .solidColor,
        material: .underWindowBackground,
        backgroundColor: CodableColor(red: 0.26, green: 0.20, blue: 0.23, alpha: 0.60),
        blurRadius: 40.0,
        outlineWidth: 1.5,
        outlineColor: CodableColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.40)
    )
}

extension ThemeAppearanceSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(WindowBackgroundMode.self, forKey: .mode) ?? .solidColor
        material = try container.decodeIfPresent(WindowMaterial.self, forKey: .material) ?? .underWindowBackground
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) ?? ThemeAppearanceSettings.defaultDark.backgroundColor
        blurRadius = try container.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 40.0
        outlineWidth = try container.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 1.0
        outlineColor = try container.decodeIfPresent(CodableColor.self, forKey: .outlineColor) ?? ThemeAppearanceSettings.defaultDark.outlineColor
    }
}

struct WindowAppearanceSettings: Codable, Equatable {
    var light: ThemeAppearanceSettings = .defaultLight
    var dark: ThemeAppearanceSettings = .defaultDark

    static let `default` = WindowAppearanceSettings()

    // Migration: decode old format into new format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if var light = try container.decodeIfPresent(ThemeAppearanceSettings.self, forKey: .light),
           let dark = try container.decodeIfPresent(ThemeAppearanceSettings.self, forKey: .dark) {
            // The ThemeAppearanceSettings decoder can't distinguish light vs dark,
            // so outlineColor falls back to defaultDark. Fix it for the light theme
            // if the decoded value matches the dark default (meaning it was missing).
            if light.outlineColor == ThemeAppearanceSettings.defaultDark.outlineColor {
                light.outlineColor = ThemeAppearanceSettings.defaultLight.outlineColor
            }
            self.light = light
            self.dark = dark
        } else {
            // Legacy format - migrate to new format
            let mode = try container.decodeIfPresent(WindowBackgroundMode.self, forKey: .mode) ?? .solidColor
            let material = try container.decodeIfPresent(WindowMaterial.self, forKey: .material) ?? .underWindowBackground
            let backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) ?? ThemeAppearanceSettings.defaultDark.backgroundColor

            let legacySettings = ThemeAppearanceSettings(mode: mode, material: material, backgroundColor: backgroundColor, blurRadius: 40.0, outlineWidth: 1.0, outlineColor: ThemeAppearanceSettings.defaultDark.outlineColor)
            self.dark = legacySettings
            self.light = .defaultLight
        }
    }

    init() {
        self.light = .defaultLight
        self.dark = .defaultDark
    }

    private enum CodingKeys: String, CodingKey {
        case light, dark
        // Legacy keys for migration
        case mode, material, backgroundColor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(light, forKey: .light)
        try container.encode(dark, forKey: .dark)
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    #if os(macOS)
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #endif

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    #if os(macOS)
    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }
    #endif

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        red = try container.decodeIfPresent(Double.self, forKey: .red) ?? 0.0
        green = try container.decodeIfPresent(Double.self, forKey: .green) ?? 0.0
        blue = try container.decodeIfPresent(Double.self, forKey: .blue) ?? 0.0
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
}

// MARK: - Persisted settings

struct PersistedSettings: Codable {
    var services: [Service]
    #if os(macOS)
    var hotkey: HotkeyManager.Configuration?
    #endif
    var customActions: [CustomAction]?
    var updatePreferences: UpdatePreferences?
    var serviceZoomLevels: [UUID: Double]?
    #if os(macOS)
    var appShortcuts: AppShortcutBindings?
    #endif
    var sessionDigitsAlternateModifiers: UInt?
    var dockVisibility: DockVisibility?
    var engineSelectorDisplayMode: SelectorDisplayMode?
    var sessionSelectorDisplayMode: SelectorDisplayMode?
    var topBarVisibility: TopBarVisibility?
    var dragAreaPosition: DragAreaPosition?
    var showHiddenBarOnModifiers: Bool?
    var windowAppearance: WindowAppearanceSettings?
    var colorScheme: AppColorScheme?
    var automaticallySwitchEngineOnLastSessionClose: Bool?
    var autoCreateSessionOnEmptyEngineActivation: Bool?
    var shouldPurgeDanglingWebData: Bool?
    var hasCompletedGhostOnboarding: Bool?
    var hasCompletedIOSOnboarding: Bool?
    var enableHUDDoubleTapCmd: Bool?
    var enableHUDCmdEscape: Bool?
    var showOnAllSpaces: Bool?
    var settingsColorStyle: SettingsColorStyle?
    var tabSurvivalPolicy: TabSurvivalPolicy?
    var persistedTabState: PersistedTabState?
    var enablePromptHistory: Bool?
    var promptRecordingIndicatorStyle: PromptRecordingIndicatorStyle?
    var promptHistoryRecordOnSubmit: Bool?
    var promptHistoryRecordOnCmdBackspace: Bool?
    var promptHistoryRecordOnSelectionClear: Bool?
    var promptHistoryLimit: Int?
    var tabNavigationRingSize: Int?
    var hideQuiperWhenRetriggeringActiveEngineShortcut: Bool?
    var hasDismissedEngineSettingsShortcutNotice: Bool?
    var globalEngineDigitShortcutsEnabled: Bool?
    var iosHardwareKeyboardSettings: IOSHardwareKeyboardSettings?
    var quiperVersion: String?
    var version: Int? = 1
    private(set) var didDecodeLegacySelectorDisplayMode = false
    private(set) var didDecodeLegacyServiceIdentifiers = false

    enum CodingKeys: String, CodingKey {
        case services, customActions, updatePreferences, serviceZoomLevels
        #if os(macOS)
        case hotkey, appShortcuts
        #endif
        case sessionDigitsAlternateModifiers, dockVisibility
        case engineSelectorDisplayMode, sessionSelectorDisplayMode, topBarVisibility
        case dragAreaPosition, showHiddenBarOnModifiers, windowAppearance, colorScheme, version
        case automaticallySwitchEngineOnLastSessionClose
        case autoCreateSessionOnEmptyEngineActivation
        case shouldPurgeDanglingWebData
        case hasCompletedGhostOnboarding
        case hasCompletedIOSOnboarding
        case enableHUDDoubleTapCmd
        case enableHUDCmdEscape
        case showOnAllSpaces
        case settingsColorStyle
        case tabSurvivalPolicy
        case persistedTabState
        case enablePromptHistory
        case promptRecordingIndicatorStyle
        case promptHistoryRecordOnSubmit
        case promptHistoryRecordOnCmdBackspace
        case promptHistoryRecordOnSelectionClear
        case promptHistoryLimit
        case tabNavigationRingSize
        case hideQuiperWhenRetriggeringActiveEngineShortcut
        case hasDismissedEngineSettingsShortcutNotice
        case globalEngineDigitShortcutsEnabled
        case iosHardwareKeyboardSettings
        case quiperVersion
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case showPromptRecordingGlow
        // The shared selector mode shipped in v2.3.0. It is decoded only to populate
        // the current per-selector fields and is never retained or encoded again.
        case selectorDisplayMode
    }

    #if os(macOS)
    init(services: [Service],
         hotkey: HotkeyManager.Configuration? = nil,
         customActions: [CustomAction]? = nil,
         updatePreferences: UpdatePreferences? = nil,
         serviceZoomLevels: [UUID: Double]? = nil,
         appShortcuts: AppShortcutBindings? = nil,
         sessionDigitsAlternateModifiers: UInt? = nil,
         dockVisibility: DockVisibility? = nil,
         engineSelectorDisplayMode: SelectorDisplayMode? = nil,
         sessionSelectorDisplayMode: SelectorDisplayMode? = nil,
         topBarVisibility: TopBarVisibility? = nil,
         dragAreaPosition: DragAreaPosition? = nil,
         showHiddenBarOnModifiers: Bool? = nil,
         windowAppearance: WindowAppearanceSettings? = nil,
         colorScheme: AppColorScheme? = nil,
         automaticallySwitchEngineOnLastSessionClose: Bool? = nil,
         autoCreateSessionOnEmptyEngineActivation: Bool? = nil,
         shouldPurgeDanglingWebData: Bool? = nil,
         hasCompletedGhostOnboarding: Bool? = nil,
         hasCompletedIOSOnboarding: Bool? = nil,
         enableHUDDoubleTapCmd: Bool? = nil,
         enableHUDCmdEscape: Bool? = nil,
         showOnAllSpaces: Bool? = nil,
         settingsColorStyle: SettingsColorStyle? = nil,
         tabSurvivalPolicy: TabSurvivalPolicy? = nil,
         persistedTabState: PersistedTabState? = nil,
         enablePromptHistory: Bool? = nil,
         promptRecordingIndicatorStyle: PromptRecordingIndicatorStyle? = nil,
         promptHistoryRecordOnSubmit: Bool? = nil,
         promptHistoryRecordOnCmdBackspace: Bool? = nil,
         promptHistoryRecordOnSelectionClear: Bool? = nil,
         promptHistoryLimit: Int? = nil,
         tabNavigationRingSize: Int? = nil,
         hideQuiperWhenRetriggeringActiveEngineShortcut: Bool? = nil,
         hasDismissedEngineSettingsShortcutNotice: Bool? = nil,
         globalEngineDigitShortcutsEnabled: Bool? = nil,
         iosHardwareKeyboardSettings: IOSHardwareKeyboardSettings? = nil,
         quiperVersion: String? = nil,
         version: Int? = 1) {
        self.services = services
        self.hotkey = hotkey
        self.customActions = customActions
        self.updatePreferences = updatePreferences
        self.serviceZoomLevels = serviceZoomLevels
        self.appShortcuts = appShortcuts
        self.sessionDigitsAlternateModifiers = sessionDigitsAlternateModifiers
        self.dockVisibility = dockVisibility
        self.engineSelectorDisplayMode = engineSelectorDisplayMode
        self.sessionSelectorDisplayMode = sessionSelectorDisplayMode
        self.topBarVisibility = topBarVisibility
        self.dragAreaPosition = dragAreaPosition
        self.showHiddenBarOnModifiers = showHiddenBarOnModifiers
        self.windowAppearance = windowAppearance
        self.colorScheme = colorScheme
        self.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        self.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        self.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        self.hasCompletedGhostOnboarding = hasCompletedGhostOnboarding
        self.hasCompletedIOSOnboarding = hasCompletedIOSOnboarding
        self.enableHUDDoubleTapCmd = enableHUDDoubleTapCmd
        self.enableHUDCmdEscape = enableHUDCmdEscape
        self.showOnAllSpaces = showOnAllSpaces
        self.settingsColorStyle = settingsColorStyle
        self.tabSurvivalPolicy = tabSurvivalPolicy
        self.persistedTabState = persistedTabState
        self.enablePromptHistory = enablePromptHistory
        self.promptRecordingIndicatorStyle = promptRecordingIndicatorStyle
        self.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        self.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        self.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        self.promptHistoryLimit = promptHistoryLimit
        self.tabNavigationRingSize = tabNavigationRingSize
        self.hideQuiperWhenRetriggeringActiveEngineShortcut = hideQuiperWhenRetriggeringActiveEngineShortcut
        self.hasDismissedEngineSettingsShortcutNotice = hasDismissedEngineSettingsShortcutNotice
        self.globalEngineDigitShortcutsEnabled = globalEngineDigitShortcutsEnabled
        self.iosHardwareKeyboardSettings = iosHardwareKeyboardSettings
        self.quiperVersion = quiperVersion
        self.version = version
    }
    #else
    init(services: [Service],
         customActions: [CustomAction]? = nil,
         updatePreferences: UpdatePreferences? = nil,
         serviceZoomLevels: [UUID: Double]? = nil,
         sessionDigitsAlternateModifiers: UInt? = nil,
         dockVisibility: DockVisibility? = nil,
         engineSelectorDisplayMode: SelectorDisplayMode? = nil,
         sessionSelectorDisplayMode: SelectorDisplayMode? = nil,
         topBarVisibility: TopBarVisibility? = nil,
         dragAreaPosition: DragAreaPosition? = nil,
         showHiddenBarOnModifiers: Bool? = nil,
         windowAppearance: WindowAppearanceSettings? = nil,
         colorScheme: AppColorScheme? = nil,
         automaticallySwitchEngineOnLastSessionClose: Bool? = nil,
         autoCreateSessionOnEmptyEngineActivation: Bool? = nil,
         shouldPurgeDanglingWebData: Bool? = nil,
         hasCompletedGhostOnboarding: Bool? = nil,
         hasCompletedIOSOnboarding: Bool? = nil,
         enableHUDDoubleTapCmd: Bool? = nil,
         enableHUDCmdEscape: Bool? = nil,
         showOnAllSpaces: Bool? = nil,
         settingsColorStyle: SettingsColorStyle? = nil,
         tabSurvivalPolicy: TabSurvivalPolicy? = nil,
         persistedTabState: PersistedTabState? = nil,
         enablePromptHistory: Bool? = nil,
         promptRecordingIndicatorStyle: PromptRecordingIndicatorStyle? = nil,
         promptHistoryRecordOnSubmit: Bool? = nil,
         promptHistoryRecordOnCmdBackspace: Bool? = nil,
         promptHistoryRecordOnSelectionClear: Bool? = nil,
         promptHistoryLimit: Int? = nil,
         tabNavigationRingSize: Int? = nil,
         hideQuiperWhenRetriggeringActiveEngineShortcut: Bool? = nil,
         hasDismissedEngineSettingsShortcutNotice: Bool? = nil,
         globalEngineDigitShortcutsEnabled: Bool? = nil,
         iosHardwareKeyboardSettings: IOSHardwareKeyboardSettings? = nil,
         quiperVersion: String? = nil,
         version: Int? = 1) {
        self.services = services
        self.customActions = customActions
        self.updatePreferences = updatePreferences
        self.serviceZoomLevels = serviceZoomLevels
        self.sessionDigitsAlternateModifiers = sessionDigitsAlternateModifiers
        self.dockVisibility = dockVisibility
        self.engineSelectorDisplayMode = engineSelectorDisplayMode
        self.sessionSelectorDisplayMode = sessionSelectorDisplayMode
        self.topBarVisibility = topBarVisibility
        self.dragAreaPosition = dragAreaPosition
        self.showHiddenBarOnModifiers = showHiddenBarOnModifiers
        self.windowAppearance = windowAppearance
        self.colorScheme = colorScheme
        self.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        self.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        self.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        self.hasCompletedGhostOnboarding = hasCompletedGhostOnboarding
        self.hasCompletedIOSOnboarding = hasCompletedIOSOnboarding
        self.enableHUDDoubleTapCmd = enableHUDDoubleTapCmd
        self.enableHUDCmdEscape = enableHUDCmdEscape
        self.showOnAllSpaces = showOnAllSpaces
        self.settingsColorStyle = settingsColorStyle
        self.tabSurvivalPolicy = tabSurvivalPolicy
        self.persistedTabState = persistedTabState
        self.enablePromptHistory = enablePromptHistory
        self.promptRecordingIndicatorStyle = promptRecordingIndicatorStyle
        self.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        self.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        self.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        self.promptHistoryLimit = promptHistoryLimit
        self.tabNavigationRingSize = tabNavigationRingSize
        self.hideQuiperWhenRetriggeringActiveEngineShortcut = hideQuiperWhenRetriggeringActiveEngineShortcut
        self.hasDismissedEngineSettingsShortcutNotice = hasDismissedEngineSettingsShortcutNotice
        self.globalEngineDigitShortcutsEnabled = globalEngineDigitShortcutsEnabled
        self.iosHardwareKeyboardSettings = iosHardwareKeyboardSettings
        self.quiperVersion = quiperVersion
        self.version = version
    }
    #endif

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        services = try container.decodeIfPresent([Service].self, forKey: .services) ?? []
        #if os(macOS)
        hotkey = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .hotkey)
        #endif
        customActions = try container.decodeIfPresent([CustomAction].self, forKey: .customActions)
        updatePreferences = try container.decodeIfPresent(UpdatePreferences.self, forKey: .updatePreferences)
        if !container.contains(.serviceZoomLevels) {
            serviceZoomLevels = nil
        } else if try container.decodeNil(forKey: .serviceZoomLevels) {
            serviceZoomLevels = nil
        } else if let currentZoomLevels = try? container.decode(
            [UUID: Double].self,
            forKey: .serviceZoomLevels
        ) {
            serviceZoomLevels = currentZoomLevels
        } else if let legacyZoomLevels = try? container.decode(
            [String: Double].self,
            forKey: .serviceZoomLevels
        ) {
            var migratedZoomLevels: [UUID: Double] = [:]
            for (serviceURL, zoomLevel) in legacyZoomLevels {
                // URL-keyed zoom levels applied to every engine sharing that URL.
                for service in services where service.url == serviceURL {
                    migratedZoomLevels[service.id] = zoomLevel
                }
            }
            serviceZoomLevels = migratedZoomLevels
            didDecodeLegacyServiceIdentifiers = true
        } else {
            // Old files sometimes encoded empty serviceZoomLevels as [] (array) or had unexpected type.
            // Treat any unparseable value as empty to keep the file readable.
            serviceZoomLevels = [:]
        }
        #if os(macOS)
        appShortcuts = try container.decodeIfPresent(AppShortcutBindings.self, forKey: .appShortcuts)
        #endif
        sessionDigitsAlternateModifiers = try container.decodeIfPresent(UInt.self, forKey: .sessionDigitsAlternateModifiers)
        dockVisibility = try container.decodeIfPresent(DockVisibility.self, forKey: .dockVisibility)
        let decodedEngineSelectorDisplayMode =
            try container.decodeIfPresent(SelectorDisplayMode.self, forKey: .engineSelectorDisplayMode)
        let decodedSessionSelectorDisplayMode =
            try container.decodeIfPresent(SelectorDisplayMode.self, forKey: .sessionSelectorDisplayMode)
        let legacySelectorDisplayMode = try legacyContainer.decodeIfPresent(
            SelectorDisplayMode.self,
            forKey: .selectorDisplayMode
        )
        engineSelectorDisplayMode = decodedEngineSelectorDisplayMode ?? legacySelectorDisplayMode
        sessionSelectorDisplayMode = decodedSessionSelectorDisplayMode ?? legacySelectorDisplayMode
        didDecodeLegacySelectorDisplayMode =
            legacySelectorDisplayMode != nil
            && (decodedEngineSelectorDisplayMode == nil || decodedSessionSelectorDisplayMode == nil)
        topBarVisibility = try container.decodeIfPresent(TopBarVisibility.self, forKey: .topBarVisibility)
        dragAreaPosition = try container.decodeIfPresent(DragAreaPosition.self, forKey: .dragAreaPosition)
        showHiddenBarOnModifiers = try container.decodeBoolIfPresent(forKey: .showHiddenBarOnModifiers)
        windowAppearance = try container.decodeIfPresent(WindowAppearanceSettings.self, forKey: .windowAppearance)
        colorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme)
        automaticallySwitchEngineOnLastSessionClose = try container.decodeBoolIfPresent(forKey: .automaticallySwitchEngineOnLastSessionClose)
        autoCreateSessionOnEmptyEngineActivation = try container.decodeBoolIfPresent(forKey: .autoCreateSessionOnEmptyEngineActivation)
        shouldPurgeDanglingWebData = try container.decodeBoolIfPresent(forKey: .shouldPurgeDanglingWebData)
        hasCompletedGhostOnboarding = try container.decodeBoolIfPresent(forKey: .hasCompletedGhostOnboarding)
        hasCompletedIOSOnboarding = try container.decodeBoolIfPresent(forKey: .hasCompletedIOSOnboarding)
        enableHUDDoubleTapCmd = try container.decodeBoolIfPresent(forKey: .enableHUDDoubleTapCmd)
        enableHUDCmdEscape = try container.decodeBoolIfPresent(forKey: .enableHUDCmdEscape)
        showOnAllSpaces = try container.decodeBoolIfPresent(forKey: .showOnAllSpaces)
        settingsColorStyle = try container.decodeIfPresent(SettingsColorStyle.self, forKey: .settingsColorStyle)
        tabSurvivalPolicy = try container.decodeIfPresent(TabSurvivalPolicy.self, forKey: .tabSurvivalPolicy)
        if !container.contains(.persistedTabState) {
            persistedTabState = nil
        } else if try container.decodeNil(forKey: .persistedTabState) {
            persistedTabState = nil
        } else {
            let decodedTabState = try PersistedTabState.decode(
                from: container.superDecoder(forKey: .persistedTabState),
                services: services
            )
            persistedTabState = decodedTabState.state
            didDecodeLegacyServiceIdentifiers =
                didDecodeLegacyServiceIdentifiers || decodedTabState.didMigrateLegacyIdentifiers
        }
        enablePromptHistory = try container.decodeBoolIfPresent(forKey: .enablePromptHistory)

        if let style = try container.decodeIfPresent(PromptRecordingIndicatorStyle.self, forKey: .promptRecordingIndicatorStyle) {
            promptRecordingIndicatorStyle = style
        } else if let legacyGlow = try legacyContainer.decodeBoolIfPresent(forKey: .showPromptRecordingGlow) {
            promptRecordingIndicatorStyle = legacyGlow ? .dashed : .off
        } else {
            promptRecordingIndicatorStyle = .dashed
        }

        promptHistoryRecordOnSubmit = try container.decodeBoolIfPresent(forKey: .promptHistoryRecordOnSubmit)
        promptHistoryRecordOnCmdBackspace = try container.decodeBoolIfPresent(forKey: .promptHistoryRecordOnCmdBackspace)
        promptHistoryRecordOnSelectionClear = try container.decodeBoolIfPresent(forKey: .promptHistoryRecordOnSelectionClear)
        promptHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .promptHistoryLimit)
        tabNavigationRingSize = try container.decodeIfPresent(Int.self, forKey: .tabNavigationRingSize)
        hideQuiperWhenRetriggeringActiveEngineShortcut = try container.decodeBoolIfPresent(forKey: .hideQuiperWhenRetriggeringActiveEngineShortcut)
        hasDismissedEngineSettingsShortcutNotice = try container.decodeBoolIfPresent(forKey: .hasDismissedEngineSettingsShortcutNotice)
        globalEngineDigitShortcutsEnabled = try container.decodeBoolIfPresent(forKey: .globalEngineDigitShortcutsEnabled)
        iosHardwareKeyboardSettings = try container.decodeIfPresent(
            IOSHardwareKeyboardSettings.self,
            forKey: .iosHardwareKeyboardSettings
        )
        quiperVersion = try container.decodeIfPresent(String.self, forKey: .quiperVersion)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
    }
}

extension KeyedDecodingContainer {
    func decodeBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let lower = s.lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return nil
    }
}

// MARK: - Persisted tab state

struct PersistedTabState: Codable {
    var activeServiceID: UUID?
    var activeIndicesByID: [UUID: Int] = [:]
    var openTabs: [UUID: [Int: String]] = [:] // serviceID -> [sessionIndex: currentURL]
    var tabTitles: [UUID: [Int: String]] = [:] // serviceID -> [sessionIndex: last non-empty title]
    var tabInputs: [UUID: [Int: TabInputState]] = [:] // serviceID -> [sessionIndex: TabInputState]
    var tabPromptHistories: [UUID: [Int: [PromptHistoryEntry]]] = [:] // serviceID -> [sessionIndex: [PromptHistoryEntry]]
    var tabPromptHistoryEnabledOverrides: [UUID: [Int: Bool]] = [:] // serviceID -> [sessionIndex: Bool]
    var tabHistory: [TabIdentifier]?

    enum CodingKeys: String, CodingKey {
        case activeServiceID
        case activeIndicesByID
        case openTabs
        case tabTitles
        case tabInputs
        case tabPromptHistories
        case tabPromptHistoryEnabledOverrides
        case tabHistory
    }

    init(activeServiceID: UUID? = nil, activeIndicesByID: [UUID: Int] = [:], openTabs: [UUID: [Int: String]] = [:], tabTitles: [UUID: [Int: String]] = [:], tabInputs: [UUID: [Int: TabInputState]] = [:], tabPromptHistories: [UUID: [Int: [PromptHistoryEntry]]] = [:], tabPromptHistoryEnabledOverrides: [UUID: [Int: Bool]] = [:], tabHistory: [TabIdentifier]? = nil) {
        self.activeServiceID = activeServiceID
        self.activeIndicesByID = activeIndicesByID
        self.openTabs = openTabs
        self.tabTitles = tabTitles
        self.tabInputs = tabInputs
        self.tabPromptHistories = tabPromptHistories
        self.tabPromptHistoryEnabledOverrides = tabPromptHistoryEnabledOverrides
        self.tabHistory = tabHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeServiceID = try container.decodeIfPresent(UUID.self, forKey: .activeServiceID)
        activeIndicesByID = try container.decodeIfPresent([UUID: Int].self, forKey: .activeIndicesByID) ?? [:]
        openTabs = try container.decodeIfPresent([UUID: [Int: String]].self, forKey: .openTabs) ?? [:]
        tabTitles = try container.decodeIfPresent([UUID: [Int: String]].self, forKey: .tabTitles) ?? [:]
        tabInputs = try container.decodeIfPresent([UUID: [Int: TabInputState]].self, forKey: .tabInputs) ?? [:]
        tabPromptHistories = try container.decodeIfPresent([UUID: [Int: [PromptHistoryEntry]]].self, forKey: .tabPromptHistories) ?? [:]
        tabPromptHistoryEnabledOverrides = try container.decodeIfPresent([UUID: [Int: Bool]].self, forKey: .tabPromptHistoryEnabledOverrides) ?? [:]
        tabHistory = try container.decodeIfPresent([TabIdentifier].self, forKey: .tabHistory)
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case activeServiceURL
        case activeIndicesByURL
        case openTabs
        case tabTitles
        case tabInputs
        case tabPromptHistories
        case tabPromptHistoryEnabledOverrides
        case tabHistory
    }

    private struct LegacyTabIdentifier: Decodable {
        let serviceURL: String
        let sessionIndex: Int
    }

    static func decode(
        from decoder: Decoder,
        services: [Service]
    ) throws -> (state: PersistedTabState, didMigrateLegacyIdentifiers: Bool) {
        let currentContainer = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        var didMigrateLegacyIdentifiers =
            legacyContainer.contains(.activeServiceURL)
            || legacyContainer.contains(.activeIndicesByURL)

        let activeServiceID: UUID?
        if let currentServiceID = try currentContainer.decodeIfPresent(
            UUID.self,
            forKey: .activeServiceID
        ) {
            activeServiceID = currentServiceID
        } else if let legacyServiceURL = try legacyContainer.decodeIfPresent(
            String.self,
            forKey: .activeServiceURL
        ) {
            activeServiceID = services.first(where: { $0.url == legacyServiceURL })?.id
            didMigrateLegacyIdentifiers = true
        } else {
            activeServiceID = nil
        }

        let activeIndices = try decodeServiceDictionary(
            currentType: [UUID: Int].self,
            legacyType: [String: Int].self,
            currentContainer: currentContainer,
            currentKey: .activeIndicesByID,
            legacyContainer: legacyContainer,
            legacyKey: .activeIndicesByURL,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers || activeIndices.didMigrateLegacyIdentifiers

        let openTabs = try decodeServiceDictionary(
            currentType: [UUID: [Int: String]].self,
            legacyType: [String: [Int: String]].self,
            currentContainer: currentContainer,
            currentKey: .openTabs,
            legacyContainer: legacyContainer,
            legacyKey: .openTabs,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers || openTabs.didMigrateLegacyIdentifiers

        let tabTitles = try decodeServiceDictionary(
            currentType: [UUID: [Int: String]].self,
            legacyType: [String: [Int: String]].self,
            currentContainer: currentContainer,
            currentKey: .tabTitles,
            legacyContainer: legacyContainer,
            legacyKey: .tabTitles,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers || tabTitles.didMigrateLegacyIdentifiers

        let tabInputs = try decodeServiceDictionary(
            currentType: [UUID: [Int: TabInputState]].self,
            legacyType: [String: [Int: TabInputState]].self,
            currentContainer: currentContainer,
            currentKey: .tabInputs,
            legacyContainer: legacyContainer,
            legacyKey: .tabInputs,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers || tabInputs.didMigrateLegacyIdentifiers

        let tabPromptHistories = try decodeServiceDictionary(
            currentType: [UUID: [Int: [PromptHistoryEntry]]].self,
            legacyType: [String: [Int: [PromptHistoryEntry]]].self,
            currentContainer: currentContainer,
            currentKey: .tabPromptHistories,
            legacyContainer: legacyContainer,
            legacyKey: .tabPromptHistories,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers || tabPromptHistories.didMigrateLegacyIdentifiers

        let tabPromptHistoryEnabledOverrides = try decodeServiceDictionary(
            currentType: [UUID: [Int: Bool]].self,
            legacyType: [String: [Int: Bool]].self,
            currentContainer: currentContainer,
            currentKey: .tabPromptHistoryEnabledOverrides,
            legacyContainer: legacyContainer,
            legacyKey: .tabPromptHistoryEnabledOverrides,
            services: services
        )
        didMigrateLegacyIdentifiers =
            didMigrateLegacyIdentifiers
            || tabPromptHistoryEnabledOverrides.didMigrateLegacyIdentifiers

        let tabHistory: [TabIdentifier]?
        if !currentContainer.contains(.tabHistory) {
            tabHistory = nil
        } else if try currentContainer.decodeNil(forKey: .tabHistory) {
            tabHistory = nil
        } else if let currentTabHistory = try? currentContainer.decode(
            [TabIdentifier].self,
            forKey: .tabHistory
        ) {
            tabHistory = currentTabHistory
        } else if let legacyTabHistory = try? legacyContainer.decode(
            [LegacyTabIdentifier].self,
            forKey: .tabHistory
        ) {
            tabHistory = legacyTabHistory.compactMap { tab in
                guard let serviceID = services.first(where: { $0.url == tab.serviceURL })?.id else {
                    return nil
                }
                return TabIdentifier(serviceID: serviceID, sessionIndex: tab.sessionIndex)
            }
            didMigrateLegacyIdentifiers = true
        } else {
            tabHistory = nil
        }

        return (
            PersistedTabState(
                activeServiceID: activeServiceID,
                activeIndicesByID: activeIndices.value,
                openTabs: openTabs.value,
                tabTitles: tabTitles.value,
                tabInputs: tabInputs.value,
                tabPromptHistories: tabPromptHistories.value,
                tabPromptHistoryEnabledOverrides: tabPromptHistoryEnabledOverrides.value,
                tabHistory: tabHistory
            ),
            didMigrateLegacyIdentifiers
        )
    }

    private static func decodeServiceDictionary<Value: Decodable>(
        currentType: [UUID: Value].Type,
        legacyType: [String: Value].Type,
        currentContainer: KeyedDecodingContainer<CodingKeys>,
        currentKey: CodingKeys,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>,
        legacyKey: LegacyCodingKeys,
        services: [Service]
    ) throws -> (value: [UUID: Value], didMigrateLegacyIdentifiers: Bool) {
        guard currentContainer.contains(currentKey)
            || legacyContainer.contains(legacyKey) else {
            return ([:], false)
        }

        if currentContainer.contains(currentKey),
           !(try currentContainer.decodeNil(forKey: currentKey)),
           let currentValue = try? currentContainer.decode(currentType, forKey: currentKey) {
            return (currentValue, false)
        }

        guard legacyContainer.contains(legacyKey),
              !(try legacyContainer.decodeNil(forKey: legacyKey)) else {
            return ([:], false)
        }

        guard let legacyValue = try? legacyContainer.decode(legacyType, forKey: legacyKey) else {
            return ([:], false)
        }
        var migratedValue: [UUID: Value] = [:]
        for (serviceURL, value) in legacyValue {
            // Legacy tab state selected the first engine matching a URL.
            if let serviceID = services.first(where: { $0.url == serviceURL })?.id {
                migratedValue[serviceID] = value
            }
        }
        return (migratedValue, true)
    }
}
