import AppKit
import Carbon

// Models extracted to QuiperShared/SharedModels.swift and QuiperShared/SharedSettings.swift

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
        alternateNextSession: nil,
        alternatePreviousSession: nil,
        alternateNextService: nil,
        alternatePreviousService: nil,
        alternateLockCurrentEngine: nil,
        sessionDigitsModifiers: NSEvent.ModifierFlags.command.rawValue,
        sessionDigitsAlternateModifiers: nil,
        serviceDigitsModifiers: nil,
        serviceDigitsPrimaryModifiers: NSEvent.ModifierFlags([.command, .control]).rawValue,
        serviceDigitsSecondaryModifiers: nil
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
