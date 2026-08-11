import Foundation

/// A logical, platform-neutral representation of an iOS/iPadOS key command.
///
/// UIKit and SwiftUI key commands are character based, unlike the physical
/// Carbon key codes used by macOS Quiper. Keeping this representation separate
/// prevents either platform from misinterpreting the other's persisted keys.
struct IOSKeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    var input: String
    var modifiers: IOSKeyboardModifiers

    init(_ input: String, modifiers: IOSKeyboardModifiers) {
        self.input = input
        self.modifiers = modifiers
    }
}

struct IOSKeyboardModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = IOSKeyboardModifiers(rawValue: 1 << 0)
    static let option = IOSKeyboardModifiers(rawValue: 1 << 1)
    static let control = IOSKeyboardModifiers(rawValue: 1 << 2)
    static let shift = IOSKeyboardModifiers(rawValue: 1 << 3)

    static let supported: IOSKeyboardModifiers = [.command, .option, .control, .shift]

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum IOSConfigurableKeyboardCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case nextSession
    case previousSession
    case nextEngine
    case previousEngine
    case lockCurrentEngine

    var id: String { rawValue }
}

struct IOSDualKeyboardBinding: Codable, Equatable, Sendable {
    var primary: IOSKeyboardShortcut?
    var alternate: IOSKeyboardShortcut?

    init(primary: IOSKeyboardShortcut? = nil, alternate: IOSKeyboardShortcut? = nil) {
        self.primary = primary
        self.alternate = alternate
    }
}

struct IOSDualModifierBinding: Codable, Equatable, Sendable {
    var primary: IOSKeyboardModifiers?
    var alternate: IOSKeyboardModifiers?

    init(primary: IOSKeyboardModifiers? = nil, alternate: IOSKeyboardModifiers? = nil) {
        self.primary = primary
        self.alternate = alternate
    }
}

/// A dictionary value that distinguishes an unconfigured item from one whose
/// default shortcut the user deliberately cleared.
struct IOSKeyboardShortcutOverride: Codable, Equatable, Sendable {
    var shortcut: IOSKeyboardShortcut?

    init(_ shortcut: IOSKeyboardShortcut?) {
        self.shortcut = shortcut
    }
}

struct IOSHardwareKeyboardSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let leftArrowInput = "\u{F702}"
    static let rightArrowInput = "\u{F703}"

    var version: Int
    var hasSeenHardwareKeyboard: Bool
    var commandBindings: [IOSConfigurableKeyboardCommand: IOSDualKeyboardBinding]
    var sessionDigitModifiers: IOSDualModifierBinding
    var engineDigitModifiers: IOSDualModifierBinding
    var actionBindings: [UUID: IOSKeyboardShortcutOverride]
    var engineBindings: [UUID: IOSKeyboardShortcutOverride]

    private enum CodingKeys: String, CodingKey {
        case version
        case hasSeenHardwareKeyboard
        case commandBindings
        case sessionDigitModifiers
        case engineDigitModifiers
        case actionBindings
        case engineBindings
    }

    init(
        version: Int = currentVersion,
        hasSeenHardwareKeyboard: Bool = false,
        commandBindings: [IOSConfigurableKeyboardCommand: IOSDualKeyboardBinding] = Self.defaultCommandBindings,
        sessionDigitModifiers: IOSDualModifierBinding = IOSDualModifierBinding(primary: .command),
        engineDigitModifiers: IOSDualModifierBinding = IOSDualModifierBinding(primary: [.command, .control]),
        actionBindings: [UUID: IOSKeyboardShortcutOverride] = Self.defaultActionBindings,
        engineBindings: [UUID: IOSKeyboardShortcutOverride] = [:]
    ) {
        self.version = version
        self.hasSeenHardwareKeyboard = hasSeenHardwareKeyboard
        self.commandBindings = commandBindings
        self.sessionDigitModifiers = sessionDigitModifiers
        self.engineDigitModifiers = engineDigitModifiers
        self.actionBindings = actionBindings
        self.engineBindings = engineBindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        hasSeenHardwareKeyboard = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasSeenHardwareKeyboard
        ) ?? false

        commandBindings = Self.defaultCommandBindings
        let decodedCommandBindings = try container.decodeIfPresent(
            [IOSConfigurableKeyboardCommand: IOSDualKeyboardBinding].self,
            forKey: .commandBindings
        ) ?? [:]
        commandBindings.merge(decodedCommandBindings) { _, decoded in decoded }

        sessionDigitModifiers = try container.decodeIfPresent(
            IOSDualModifierBinding.self,
            forKey: .sessionDigitModifiers
        ) ?? IOSDualModifierBinding(primary: .command)
        engineDigitModifiers = try container.decodeIfPresent(
            IOSDualModifierBinding.self,
            forKey: .engineDigitModifiers
        ) ?? IOSDualModifierBinding(primary: [.command, .control])
        actionBindings = try container.decodeIfPresent(
            [UUID: IOSKeyboardShortcutOverride].self,
            forKey: .actionBindings
        ) ?? Self.defaultActionBindings
        engineBindings = try container.decodeIfPresent(
            [UUID: IOSKeyboardShortcutOverride].self,
            forKey: .engineBindings
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(hasSeenHardwareKeyboard, forKey: .hasSeenHardwareKeyboard)

        var commandContainer = container.nestedUnkeyedContainer(forKey: .commandBindings)
        for command in commandBindings.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let binding = commandBindings[command] {
                try commandContainer.encode(command)
                try commandContainer.encode(binding)
            }
        }

        try container.encode(sessionDigitModifiers, forKey: .sessionDigitModifiers)
        try container.encode(engineDigitModifiers, forKey: .engineDigitModifiers)

        var actionContainer = container.nestedUnkeyedContainer(forKey: .actionBindings)
        for actionID in actionBindings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            if let binding = actionBindings[actionID] {
                try actionContainer.encode(actionID)
                try actionContainer.encode(binding)
            }
        }

        var engineContainer = container.nestedUnkeyedContainer(forKey: .engineBindings)
        for engineID in engineBindings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            if let binding = engineBindings[engineID] {
                try engineContainer.encode(engineID)
                try engineContainer.encode(binding)
            }
        }
    }

    static let defaults = IOSHardwareKeyboardSettings()

    static let defaultCommandBindings: [IOSConfigurableKeyboardCommand: IOSDualKeyboardBinding] = [
        .nextSession: IOSDualKeyboardBinding(
            primary: IOSKeyboardShortcut(rightArrowInput, modifiers: [.command, .shift])
        ),
        .previousSession: IOSDualKeyboardBinding(
            primary: IOSKeyboardShortcut(leftArrowInput, modifiers: [.command, .shift])
        ),
        .nextEngine: IOSDualKeyboardBinding(
            primary: IOSKeyboardShortcut(rightArrowInput, modifiers: [.command, .control])
        ),
        .previousEngine: IOSDualKeyboardBinding(
            primary: IOSKeyboardShortcut(leftArrowInput, modifiers: [.command, .control])
        ),
        .lockCurrentEngine: IOSDualKeyboardBinding(
            primary: IOSKeyboardShortcut("l", modifiers: [.command, .option])
        )
    ]

    static let defaultActionBindings: [UUID: IOSKeyboardShortcutOverride] = [
        DefaultEngineDefinitions.newSessionActionID:
            IOSKeyboardShortcutOverride(IOSKeyboardShortcut("n", modifiers: .command)),
        DefaultEngineDefinitions.newTemporarySessionActionID:
            IOSKeyboardShortcutOverride(IOSKeyboardShortcut("n", modifiers: [.command, .shift])),
        DefaultEngineDefinitions.shareActionID:
            IOSKeyboardShortcutOverride(IOSKeyboardShortcut("s", modifiers: [.command, .shift])),
        DefaultEngineDefinitions.historyActionID:
            IOSKeyboardShortcutOverride(IOSKeyboardShortcut("h", modifiers: [.command, .shift])),
        DefaultEngineDefinitions.openSettingsActionID:
            IOSKeyboardShortcutOverride(IOSKeyboardShortcut(",", modifiers: .command))
    ]

    func binding(for command: IOSConfigurableKeyboardCommand) -> IOSDualKeyboardBinding {
        commandBindings[command] ?? IOSDualKeyboardBinding()
    }

    func actionShortcut(for actionID: UUID) -> IOSKeyboardShortcut? {
        if let override = actionBindings[actionID] {
            return override.shortcut
        }
        return Self.defaultActionBindings[actionID]?.shortcut
    }

    func engineShortcut(for engineID: UUID) -> IOSKeyboardShortcut? {
        engineBindings[engineID]?.shortcut
    }

    mutating func restoreDefaults(preservingSeenState: Bool = true) {
        let hasSeen = hasSeenHardwareKeyboard
        self = .defaults
        if preservingSeenState {
            hasSeenHardwareKeyboard = hasSeen
        }
    }

    mutating func prune(validEngineIDs: Set<UUID>, validActionIDs: Set<UUID>) {
        engineBindings = engineBindings.filter { validEngineIDs.contains($0.key) }
        actionBindings = actionBindings.filter { validActionIDs.contains($0.key) }
    }
}

struct IOSFixedKeyboardShortcut: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let shortcut: IOSKeyboardShortcut

    static let all: [IOSFixedKeyboardShortcut] = [
        .init(id: "history", title: "Prompt History", shortcut: .init("y", modifiers: .command)),
        .init(id: "mru", title: "Next Recent Session", shortcut: .init("`", modifiers: .command)),
        .init(id: "mru-reverse", title: "Previous Recent Session", shortcut: .init("`", modifiers: [.command, .shift])),
        .init(id: "close", title: "Close Session", shortcut: .init("w", modifiers: .command)),
        .init(id: "reload", title: "Reload", shortcut: .init("r", modifiers: .command)),
        .init(id: "force-reload", title: "Force Reload", shortcut: .init("r", modifiers: [.command, .shift])),
        .init(id: "origin-reload", title: "Reload from Origin", shortcut: .init("r", modifiers: [.command, .option])),
        .init(id: "find", title: "Find in Page", shortcut: .init("f", modifiers: .command)),
        .init(id: "find-next", title: "Find Next", shortcut: .init("g", modifiers: .command)),
        .init(id: "find-previous", title: "Find Previous", shortcut: .init("g", modifiers: [.command, .shift])),
        .init(id: "settings", title: "Quiper Settings", shortcut: .init(",", modifiers: [.command, .shift])),
        .init(id: "zoom-in", title: "Zoom In", shortcut: .init("=", modifiers: .command)),
        .init(id: "zoom-out", title: "Zoom Out", shortcut: .init("-", modifiers: .command)),
        .init(id: "zoom-reset", title: "Actual Size", shortcut: .init("0", modifiers: [.command, .option]))
    ]
}

enum IOSKeyboardBindingIdentifier: Hashable, Sendable {
    enum Variant: Hashable, Sendable {
        case primary
        case alternate
    }

    case command(IOSConfigurableKeyboardCommand, Variant)
    case sessionDigits(Variant)
    case engineDigits(Variant)
    case action(UUID)
    case engine(UUID)
}

enum IOSKeyboardShortcutValidationError: LocalizedError, Equatable, Sendable {
    case modifierRequired
    case systemReserved
    case fixedCommand(String)
    case duplicate(String)
    case digitGroupConflict(String)

    var errorDescription: String? {
        switch self {
        case .modifierRequired:
            "Add Command, Option, or Control to this key."
        case .systemReserved:
            "That shortcut is reserved by iOS or iPadOS."
        case .fixedCommand(let title):
            "That shortcut is fixed for \(title)."
        case .duplicate(let title):
            "That shortcut is already assigned to \(title)."
        case .digitGroupConflict(let title):
            "One or more digit shortcuts conflict with \(title)."
        }
    }
}

enum IOSKeyboardShortcutValidator {
    static func validate(
        _ shortcut: IOSKeyboardShortcut,
        replacing identifier: IOSKeyboardBindingIdentifier,
        settings: IOSHardwareKeyboardSettings,
        actions: [CustomAction],
        engines: [Service]
    ) -> IOSKeyboardShortcutValidationError? {
        let normalized = normalize(shortcut)
        let applicationModifiers = normalized.modifiers.intersection([.command, .option, .control])
        if applicationModifiers.isEmpty && !isFunctionKey(normalized.input) {
            return .modifierRequired
        }

        var candidates = [normalized]
        if case .command(.lockCurrentEngine, _) = identifier {
            guard !normalized.modifiers.contains(.shift) else {
                return .duplicate("Lock All Protected Engines")
            }
            var lockAllModifiers = normalized.modifiers
            lockAllModifiers.insert(.shift)
            candidates.append(IOSKeyboardShortcut(normalized.input, modifiers: lockAllModifiers))
        }

        let assignments = configurableAssignments(
            settings: settings,
            actions: actions,
            engines: engines
        )
        for candidate in candidates {
            if isSystemReserved(candidate) {
                return .systemReserved
            }
            if let fixed = IOSFixedKeyboardShortcut.all.first(where: {
                normalize($0.shortcut) == candidate
            }) {
                return .fixedCommand(fixed.title)
            }
            if let duplicate = assignments.first(where: {
                $0.identifier != identifier && normalize($0.shortcut) == candidate
            }) {
                return .duplicate(duplicate.title)
            }
        }
        return nil
    }

    static func validateDigitModifiers(
        _ modifiers: IOSKeyboardModifiers,
        replacing identifier: IOSKeyboardBindingIdentifier,
        settings: IOSHardwareKeyboardSettings,
        actions: [CustomAction],
        engines: [Service]
    ) -> IOSKeyboardShortcutValidationError? {
        guard !modifiers.isEmpty else { return .modifierRequired }
        for index in SessionSlots.range {
            let candidate = IOSKeyboardShortcut(SessionSlots.label(for: index), modifiers: modifiers)
            if let issue = validate(
                candidate,
                replacing: identifier,
                settings: settings,
                actions: actions,
                engines: engines
            ) {
                switch issue {
                case .fixedCommand(let title), .duplicate(let title):
                    return .digitGroupConflict(title)
                default:
                    return issue
                }
            }
        }
        return nil
    }

    static func normalize(_ shortcut: IOSKeyboardShortcut) -> IOSKeyboardShortcut {
        let input = shortcut.input.count == 1 ? shortcut.input.lowercased() : shortcut.input
        return IOSKeyboardShortcut(input, modifiers: shortcut.modifiers.intersection(.supported))
    }

    private struct Assignment {
        let identifier: IOSKeyboardBindingIdentifier
        let title: String
        let shortcut: IOSKeyboardShortcut
    }

    private static func configurableAssignments(
        settings: IOSHardwareKeyboardSettings,
        actions: [CustomAction],
        engines: [Service]
    ) -> [Assignment] {
        var result: [Assignment] = []
        for command in IOSConfigurableKeyboardCommand.allCases {
            let binding = settings.binding(for: command)
            if let shortcut = binding.primary {
                result.append(.init(identifier: .command(command, .primary), title: command.displayTitle, shortcut: shortcut))
                appendLockAllVariation(
                    for: command,
                    shortcut: shortcut,
                    identifier: .command(command, .primary),
                    to: &result
                )
            }
            if let shortcut = binding.alternate {
                result.append(.init(identifier: .command(command, .alternate), title: command.displayTitle, shortcut: shortcut))
                appendLockAllVariation(
                    for: command,
                    shortcut: shortcut,
                    identifier: .command(command, .alternate),
                    to: &result
                )
            }
        }
        appendDigits(settings.sessionDigitModifiers.primary, identifier: .sessionDigits(.primary), title: "Session Selection", to: &result)
        appendDigits(settings.sessionDigitModifiers.alternate, identifier: .sessionDigits(.alternate), title: "Session Selection", to: &result)
        appendDigits(settings.engineDigitModifiers.primary, identifier: .engineDigits(.primary), title: "Engine Selection", to: &result)
        appendDigits(settings.engineDigitModifiers.alternate, identifier: .engineDigits(.alternate), title: "Engine Selection", to: &result)
        for action in actions {
            if let shortcut = settings.actionShortcut(for: action.id) {
                result.append(.init(identifier: .action(action.id), title: action.name, shortcut: shortcut))
            }
        }
        for engine in engines {
            if let shortcut = settings.engineShortcut(for: engine.id) {
                result.append(.init(identifier: .engine(engine.id), title: engine.name, shortcut: shortcut))
            }
        }
        return result
    }

    private static func appendDigits(
        _ modifiers: IOSKeyboardModifiers?,
        identifier: IOSKeyboardBindingIdentifier,
        title: String,
        to assignments: inout [Assignment]
    ) {
        guard let modifiers else { return }
        for index in SessionSlots.range {
            assignments.append(
                .init(
                    identifier: identifier,
                    title: title,
                    shortcut: IOSKeyboardShortcut(SessionSlots.label(for: index), modifiers: modifiers)
                )
            )
        }
    }

    private static func appendLockAllVariation(
        for command: IOSConfigurableKeyboardCommand,
        shortcut: IOSKeyboardShortcut,
        identifier: IOSKeyboardBindingIdentifier,
        to assignments: inout [Assignment]
    ) {
        guard command == .lockCurrentEngine else { return }
        var modifiers = shortcut.modifiers
        modifiers.insert(.shift)
        assignments.append(
            .init(
                identifier: identifier,
                title: "Lock All Protected Engines",
                shortcut: IOSKeyboardShortcut(shortcut.input, modifiers: modifiers)
            )
        )
    }

    /// UIKit represents F1–F35 with the same private Unicode range used by
    /// AppKit. Navigation keys deliberately do not qualify: leaving bare Tab,
    /// arrows, Space, and Escape alone is essential for text editing and Full
    /// Keyboard Access.
    private static func isFunctionKey(_ input: String) -> Bool {
        guard let scalar = input.unicodeScalars.first, input.unicodeScalars.count == 1 else { return false }
        return (0xF704...0xF726).contains(Int(scalar.value))
    }

    private static func isSystemReserved(_ shortcut: IOSKeyboardShortcut) -> Bool {
        if shortcut.modifiers.contains([.control, .option]) {
            return true
        }
        return systemReservedShortcuts.contains(shortcut)
    }

    private static let systemReservedShortcuts: Set<IOSKeyboardShortcut> = [
        IOSKeyboardShortcut("h", modifiers: .command),
        IOSKeyboardShortcut(" ", modifiers: .command),
        IOSKeyboardShortcut("\t", modifiers: .command),
        IOSKeyboardShortcut("d", modifiers: [.command, .option]),
        IOSKeyboardShortcut("3", modifiers: [.command, .shift]),
        IOSKeyboardShortcut("4", modifiers: [.command, .shift]),
        IOSKeyboardShortcut("5", modifiers: [.command, .shift]),
        IOSKeyboardShortcut(" ", modifiers: .control)
    ]
}

extension IOSConfigurableKeyboardCommand {
    var displayTitle: String {
        switch self {
        case .nextSession: "Next Session"
        case .previousSession: "Previous Session"
        case .nextEngine: "Next Engine"
        case .previousEngine: "Previous Engine"
        case .lockCurrentEngine: "Lock Current Engine"
        }
    }
}
