import Foundation
import AppKit
import SwiftUI
import Carbon

enum AutoLockPolicy: String, Codable, CaseIterable, Identifiable {
    case onAppQuit = "On App Quit"
    case onSwitchAway = "On Switch Away"
    case afterInactivity = "After Inactivity"
    
    var id: String { rawValue }
}

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

enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
    
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum SettingsColorStyle: String, Codable, CaseIterable, Identifiable {
    case colorful = "Colorful"
    case classic = "Classic"
    
    var id: String { rawValue }
}

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
    
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }

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

struct AppShortcutBindings: Codable, Equatable {
    enum Key: String, CaseIterable, Codable, Identifiable {
        case nextSession
        case previousSession
        case nextService
        case previousService
        case lockCurrentEngine

        var id: String { rawValue }
    }

    enum ModifierGroup {
        case sessionDigits
        case serviceDigitsPrimary
        case serviceDigitsSecondary
    }

    var nextSession: HotkeyManager.Configuration
    var previousSession: HotkeyManager.Configuration
    var nextService: HotkeyManager.Configuration
    var previousService: HotkeyManager.Configuration
    var lockCurrentEngine: HotkeyManager.Configuration
    var alternateNextSession: HotkeyManager.Configuration?
    var alternatePreviousSession: HotkeyManager.Configuration?
    var alternateNextService: HotkeyManager.Configuration?
    var alternatePreviousService: HotkeyManager.Configuration?
    var alternateLockCurrentEngine: HotkeyManager.Configuration?
    var sessionDigitsModifiers: UInt
    var sessionDigitsAlternateModifiers: UInt?
    var serviceDigitsModifiers: UInt?
    var serviceDigitsPrimaryModifiers: UInt
    var serviceDigitsSecondaryModifiers: UInt?

    private enum CodingKeys: String, CodingKey {
        case nextSession, previousSession, nextService, previousService, lockCurrentEngine
        case alternateNextSession, alternatePreviousSession, alternateNextService, alternatePreviousService, alternateLockCurrentEngine
        case sessionDigitsModifiers, sessionDigitsAlternateModifiers
        case serviceDigitsModifiers, serviceDigitsPrimaryModifiers, serviceDigitsSecondaryModifiers
    }

    static let defaults = AppShortcutBindings(
        nextSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        previousSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        nextService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        previousService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        lockCurrentEngine: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_L),
            modifierFlags: NSEvent.ModifierFlags([.command, .option]).rawValue
        ),
        alternateNextSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_L),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        ),
        alternatePreviousSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_H),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        ),
        alternateNextService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_L),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        alternatePreviousService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_H),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        alternateLockCurrentEngine: nil,
        sessionDigitsModifiers: NSEvent.ModifierFlags.command.rawValue,
        sessionDigitsAlternateModifiers: nil,
        serviceDigitsModifiers: nil,
        serviceDigitsPrimaryModifiers: NSEvent.ModifierFlags([.command, .control]).rawValue,
        serviceDigitsSecondaryModifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
    )

    func configuration(for key: Key) -> HotkeyManager.Configuration {
        switch key {
        case .nextSession: return nextSession
        case .previousSession: return previousSession
        case .nextService: return nextService
        case .previousService: return previousService
        case .lockCurrentEngine: return lockCurrentEngine
        }
    }

    func alternateConfiguration(for key: Key) -> HotkeyManager.Configuration? {
        switch key {
        case .nextSession: return alternateNextSession
        case .previousSession: return alternatePreviousSession
        case .nextService: return alternateNextService
        case .previousService: return alternatePreviousService
        case .lockCurrentEngine: return alternateLockCurrentEngine
        }
    }

    func defaultConfiguration(for key: Key) -> HotkeyManager.Configuration {
        AppShortcutBindings.defaults.configuration(for: key)
    }

    mutating func setConfiguration(_ configuration: HotkeyManager.Configuration, for key: Key) {
        switch key {
        case .nextSession: nextSession = configuration
        case .previousSession: previousSession = configuration
        case .nextService: nextService = configuration
        case .previousService: previousService = configuration
        case .lockCurrentEngine: lockCurrentEngine = configuration
        }
    }

    mutating func setAlternateConfiguration(_ configuration: HotkeyManager.Configuration?, for key: Key) {
        switch key {
        case .nextSession: alternateNextSession = configuration
        case .previousSession: alternatePreviousSession = configuration
        case .nextService: alternateNextService = configuration
        case .previousService: alternatePreviousService = configuration
        case .lockCurrentEngine: alternateLockCurrentEngine = configuration
        }
    }
}

extension AppShortcutBindings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextSession = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .nextSession) ?? AppShortcutBindings.defaults.nextSession
        previousSession = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .previousSession) ?? AppShortcutBindings.defaults.previousSession
        nextService = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .nextService) ?? AppShortcutBindings.defaults.nextService
        previousService = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .previousService) ?? AppShortcutBindings.defaults.previousService
        lockCurrentEngine = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .lockCurrentEngine) ?? AppShortcutBindings.defaults.lockCurrentEngine
        alternateNextSession = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .alternateNextSession)
        alternatePreviousSession = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .alternatePreviousSession)
        alternateNextService = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .alternateNextService)
        alternatePreviousService = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .alternatePreviousService)
        alternateLockCurrentEngine = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .alternateLockCurrentEngine)
        sessionDigitsModifiers = try container.decodeIfPresent(UInt.self, forKey: .sessionDigitsModifiers) ?? AppShortcutBindings.defaults.sessionDigitsModifiers
        sessionDigitsAlternateModifiers = try container.decodeIfPresent(UInt.self, forKey: .sessionDigitsAlternateModifiers)
        serviceDigitsModifiers = try container.decodeIfPresent(UInt.self, forKey: .serviceDigitsModifiers)
        serviceDigitsPrimaryModifiers = try container.decodeIfPresent(UInt.self, forKey: .serviceDigitsPrimaryModifiers) ?? AppShortcutBindings.defaults.serviceDigitsPrimaryModifiers
        serviceDigitsSecondaryModifiers = try container.decodeIfPresent(UInt.self, forKey: .serviceDigitsSecondaryModifiers)
    }
}

struct PersistedSettings: Codable {
    var services: [Service]
    var hotkey: HotkeyManager.Configuration?
    var customActions: [CustomAction]?
    var updatePreferences: UpdatePreferences?
    var serviceZoomLevels: [String: Double]?
    var appShortcuts: AppShortcutBindings?
    var sessionDigitsAlternateModifiers: UInt?
    var dockVisibility: DockVisibility?
    var selectorDisplayMode: SelectorDisplayMode?
    var topBarVisibility: TopBarVisibility?
    var dragAreaPosition: DragAreaPosition?
    var showHiddenBarOnModifiers: Bool?
    var windowAppearance: WindowAppearanceSettings?
    var colorScheme: AppColorScheme?
    var automaticallySwitchEngineOnLastSessionClose: Bool?
    var autoCreateSessionOnEmptyEngineActivation: Bool?
    var shouldPurgeDanglingWebData: Bool?
    var hasCompletedGhostOnboarding: Bool?
    var enableHUDDoubleTapCmd: Bool?
    var enableHUDCmdEscape: Bool?
    var showOnAllSpaces: Bool?
    var settingsColorStyle: SettingsColorStyle?
    var tabSurvivalPolicy: TabSurvivalPolicy?
    var persistedTabState: PersistedTabState?
    var enablePromptHistory: Bool?
    var promptHistoryRecordOnSubmit: Bool?
    var promptHistoryRecordOnCmdBackspace: Bool?
    var promptHistoryRecordOnSelectionClear: Bool?
    var version: Int? = 1

    enum CodingKeys: String, CodingKey {
        case services, hotkey, customActions, updatePreferences, serviceZoomLevels, appShortcuts
        case sessionDigitsAlternateModifiers, dockVisibility, selectorDisplayMode, topBarVisibility
        case dragAreaPosition, showHiddenBarOnModifiers, windowAppearance, colorScheme, version
        case automaticallySwitchEngineOnLastSessionClose
        case autoCreateSessionOnEmptyEngineActivation
        case shouldPurgeDanglingWebData
        case hasCompletedGhostOnboarding
        case enableHUDDoubleTapCmd
        case enableHUDCmdEscape
        case showOnAllSpaces
        case settingsColorStyle
        case tabSurvivalPolicy
        case persistedTabState
        case enablePromptHistory
        case promptHistoryRecordOnSubmit
        case promptHistoryRecordOnCmdBackspace
        case promptHistoryRecordOnSelectionClear
    }

    init(services: [Service],
         hotkey: HotkeyManager.Configuration? = nil,
         customActions: [CustomAction]? = nil,
         updatePreferences: UpdatePreferences? = nil,
         serviceZoomLevels: [String: Double]? = nil,
         appShortcuts: AppShortcutBindings? = nil,
         sessionDigitsAlternateModifiers: UInt? = nil,
         dockVisibility: DockVisibility? = nil,
         selectorDisplayMode: SelectorDisplayMode? = nil,
         topBarVisibility: TopBarVisibility? = nil,
         dragAreaPosition: DragAreaPosition? = nil,
         showHiddenBarOnModifiers: Bool? = nil,
         windowAppearance: WindowAppearanceSettings? = nil,
         colorScheme: AppColorScheme? = nil,
         automaticallySwitchEngineOnLastSessionClose: Bool? = nil,
         autoCreateSessionOnEmptyEngineActivation: Bool? = nil,
         shouldPurgeDanglingWebData: Bool? = nil,
         hasCompletedGhostOnboarding: Bool? = nil,
         enableHUDDoubleTapCmd: Bool? = nil,
         enableHUDCmdEscape: Bool? = nil,
         showOnAllSpaces: Bool? = nil,
         settingsColorStyle: SettingsColorStyle? = nil,
         tabSurvivalPolicy: TabSurvivalPolicy? = nil,
         persistedTabState: PersistedTabState? = nil,
         enablePromptHistory: Bool? = nil,
         promptHistoryRecordOnSubmit: Bool? = nil,
         promptHistoryRecordOnCmdBackspace: Bool? = nil,
         promptHistoryRecordOnSelectionClear: Bool? = nil,
         version: Int? = 1) {
        self.services = services
        self.hotkey = hotkey
        self.customActions = customActions
        self.updatePreferences = updatePreferences
        self.serviceZoomLevels = serviceZoomLevels
        self.appShortcuts = appShortcuts
        self.sessionDigitsAlternateModifiers = sessionDigitsAlternateModifiers
        self.dockVisibility = dockVisibility
        self.selectorDisplayMode = selectorDisplayMode
        self.topBarVisibility = topBarVisibility
        self.dragAreaPosition = dragAreaPosition
        self.showHiddenBarOnModifiers = showHiddenBarOnModifiers
        self.windowAppearance = windowAppearance
        self.colorScheme = colorScheme
        self.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        self.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        self.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        self.hasCompletedGhostOnboarding = hasCompletedGhostOnboarding
        self.enableHUDDoubleTapCmd = enableHUDDoubleTapCmd
        self.enableHUDCmdEscape = enableHUDCmdEscape
        self.showOnAllSpaces = showOnAllSpaces
        self.settingsColorStyle = settingsColorStyle
        self.tabSurvivalPolicy = tabSurvivalPolicy
        self.persistedTabState = persistedTabState
        self.enablePromptHistory = enablePromptHistory
        self.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        self.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        self.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decodeIfPresent([Service].self, forKey: .services) ?? []
        hotkey = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .hotkey)
        customActions = try container.decodeIfPresent([CustomAction].self, forKey: .customActions)
        updatePreferences = try container.decodeIfPresent(UpdatePreferences.self, forKey: .updatePreferences)
        serviceZoomLevels = try container.decodeIfPresent([String: Double].self, forKey: .serviceZoomLevels)
        appShortcuts = try container.decodeIfPresent(AppShortcutBindings.self, forKey: .appShortcuts)
        sessionDigitsAlternateModifiers = try container.decodeIfPresent(UInt.self, forKey: .sessionDigitsAlternateModifiers)
        dockVisibility = try container.decodeIfPresent(DockVisibility.self, forKey: .dockVisibility)
        selectorDisplayMode = try container.decodeIfPresent(SelectorDisplayMode.self, forKey: .selectorDisplayMode)
        topBarVisibility = try container.decodeIfPresent(TopBarVisibility.self, forKey: .topBarVisibility)
        dragAreaPosition = try container.decodeIfPresent(DragAreaPosition.self, forKey: .dragAreaPosition)
        showHiddenBarOnModifiers = try container.decodeIfPresent(Bool.self, forKey: .showHiddenBarOnModifiers)
        windowAppearance = try container.decodeIfPresent(WindowAppearanceSettings.self, forKey: .windowAppearance)
        colorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme)
        automaticallySwitchEngineOnLastSessionClose = try container.decodeIfPresent(Bool.self, forKey: .automaticallySwitchEngineOnLastSessionClose)
        autoCreateSessionOnEmptyEngineActivation = try container.decodeIfPresent(Bool.self, forKey: .autoCreateSessionOnEmptyEngineActivation)
        shouldPurgeDanglingWebData = try container.decodeIfPresent(Bool.self, forKey: .shouldPurgeDanglingWebData)
        hasCompletedGhostOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedGhostOnboarding)
        enableHUDDoubleTapCmd = try container.decodeIfPresent(Bool.self, forKey: .enableHUDDoubleTapCmd)
        enableHUDCmdEscape = try container.decodeIfPresent(Bool.self, forKey: .enableHUDCmdEscape)
        showOnAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces)
        settingsColorStyle = try container.decodeIfPresent(SettingsColorStyle.self, forKey: .settingsColorStyle)
        tabSurvivalPolicy = try container.decodeIfPresent(TabSurvivalPolicy.self, forKey: .tabSurvivalPolicy)
        persistedTabState = try container.decodeIfPresent(PersistedTabState.self, forKey: .persistedTabState)
        enablePromptHistory = try container.decodeIfPresent(Bool.self, forKey: .enablePromptHistory)
        promptHistoryRecordOnSubmit = try container.decodeIfPresent(Bool.self, forKey: .promptHistoryRecordOnSubmit)
        promptHistoryRecordOnCmdBackspace = try container.decodeIfPresent(Bool.self, forKey: .promptHistoryRecordOnCmdBackspace)
        promptHistoryRecordOnSelectionClear = try container.decodeIfPresent(Bool.self, forKey: .promptHistoryRecordOnSelectionClear)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
    }
}

enum TabSurvivalPolicy: String, Codable, CaseIterable, Identifiable {
    case always = "Always Restore"
    case askOnExit = "Ask on Exit"
    case never = "Never Restore"

    var id: String { rawValue }
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

struct PersistedTabState: Codable {
    var activeServiceURL: String?
    var activeIndicesByURL: [String: Int] = [:]
    var openTabs: [String: [Int: String]] = [:] // serviceURL -> [sessionIndex: currentURL]
    var tabInputs: [String: [Int: TabInputState]] = [:] // serviceURL -> [sessionIndex: TabInputState]
    var tabPromptHistories: [String: [Int: [PromptHistoryEntry]]] = [:] // serviceURL -> [sessionIndex: [PromptHistoryEntry]]
    var tabPromptHistoryEnabledOverrides: [String: [Int: Bool]] = [:] // serviceURL -> [sessionIndex: Bool]

    enum CodingKeys: String, CodingKey {
        case activeServiceURL
        case activeIndicesByURL
        case openTabs
        case tabInputs
        case tabPromptHistories
        case tabPromptHistoryEnabledOverrides
    }

    init(activeServiceURL: String? = nil, activeIndicesByURL: [String: Int] = [:], openTabs: [String: [Int: String]] = [:], tabInputs: [String: [Int: TabInputState]] = [:], tabPromptHistories: [String: [Int: [PromptHistoryEntry]]] = [:], tabPromptHistoryEnabledOverrides: [String: [Int: Bool]] = [:]) {
        self.activeServiceURL = activeServiceURL
        self.activeIndicesByURL = activeIndicesByURL
        self.openTabs = openTabs
        self.tabInputs = tabInputs
        self.tabPromptHistories = tabPromptHistories
        self.tabPromptHistoryEnabledOverrides = tabPromptHistoryEnabledOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeServiceURL = try container.decodeIfPresent(String.self, forKey: .activeServiceURL)
        activeIndicesByURL = try container.decodeIfPresent([String: Int].self, forKey: .activeIndicesByURL) ?? [:]
        openTabs = try container.decodeIfPresent([String: [Int: String]].self, forKey: .openTabs) ?? [:]
        tabInputs = try container.decodeIfPresent([String: [Int: TabInputState]].self, forKey: .tabInputs) ?? [:]
        tabPromptHistories = try container.decodeIfPresent([String: [Int: [PromptHistoryEntry]]].self, forKey: .tabPromptHistories) ?? [:]
        tabPromptHistoryEnabledOverrides = try container.decodeIfPresent([String: [Int: Bool]].self, forKey: .tabPromptHistoryEnabledOverrides) ?? [:]
    }
}
