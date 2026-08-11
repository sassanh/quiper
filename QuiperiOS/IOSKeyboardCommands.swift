import SwiftUI

private struct IOSResolvedCommandShortcut: Identifiable {
    let id: String
    let title: String
    let command: IOSAppCommand
    let shortcut: IOSKeyboardShortcut
}

@MainActor
struct IOSKeyboardCommands: Commands {
    @ObservedObject var environment: AppEnvironment
    @FocusedValue(IOSSceneCommandContext.self) private var sceneContext

    var body: some Commands {
        CommandMenu("Quiper") {
            ForEach(configurableShortcuts) { item in
                commandButton(item)
            }

            Divider()

            ForEach(sessionDigitShortcuts) { item in
                commandButton(item)
            }
            ForEach(engineDigitShortcuts) { item in
                commandButton(item)
            }

            Divider()

            ForEach(actionShortcuts) { item in
                commandButton(item)
            }
            ForEach(engineShortcuts) { item in
                commandButton(item)
            }

            Divider()

            ForEach(Self.fixedShortcuts) { item in
                commandButton(item)
            }
        }
    }

    @ViewBuilder
    private func commandButton(_ item: IOSResolvedCommandShortcut) -> some View {
        if let shortcut = keyboardShortcut(from: item.shortcut), sceneContext?.isRecordingShortcut != true {
            Button(item.title) {
                execute(item.command)
            }
            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            .disabled(sceneContext == nil)
        } else {
            Button(item.title) {
                execute(item.command)
            }
            .disabled(sceneContext == nil || sceneContext?.isRecordingShortcut == true)
        }
    }

    private var configurableShortcuts: [IOSResolvedCommandShortcut] {
        var result: [IOSResolvedCommandShortcut] = []
        let settings = environment.iosHardwareKeyboardSettings
        for command in IOSConfigurableKeyboardCommand.allCases {
            let binding = settings.binding(for: command)
            let values: [(String, IOSKeyboardBindingIdentifier.Variant, IOSKeyboardShortcut?)] = [
                ("primary", .primary, binding.primary),
                ("alternate", .alternate, binding.alternate)
            ]
            for (variantName, variant, shortcut) in values {
                guard let shortcut,
                      isValid(shortcut, replacing: .command(command, variant)) else { continue }
                result.append(
                    IOSResolvedCommandShortcut(
                        id: "command-\(command.rawValue)-\(variantName)",
                        title: command.displayTitle,
                        command: command.appCommand,
                        shortcut: shortcut
                    )
                )
                if command == .lockCurrentEngine {
                    var modifiers = shortcut.modifiers
                    modifiers.insert(.shift)
                    result.append(
                        IOSResolvedCommandShortcut(
                            id: "command-lock-all-\(variantName)",
                            title: "Lock All Protected Engines",
                            command: .lock(.allProtected),
                            shortcut: IOSKeyboardShortcut(shortcut.input, modifiers: modifiers)
                        )
                    )
                }
            }
        }
        return result
    }

    private var sessionDigitShortcuts: [IOSResolvedCommandShortcut] {
        digitShortcuts(
            prefix: "session",
            title: "Open Session",
            modifiers: environment.iosHardwareKeyboardSettings.sessionDigitModifiers,
            identifier: { .sessionDigits($0) },
            indices: Array(SessionSlots.range),
            command: { .selectSession($0) }
        )
    }

    private var engineDigitShortcuts: [IOSResolvedCommandShortcut] {
        digitShortcuts(
            prefix: "engine",
            title: "Open Engine",
            modifiers: environment.iosHardwareKeyboardSettings.engineDigitModifiers,
            identifier: { .engineDigits($0) },
            indices: Array(environment.services.indices.prefix(SessionSlots.count)),
            command: { .selectEngine($0) }
        )
    }

    private func digitShortcuts(
        prefix: String,
        title: String,
        modifiers: IOSDualModifierBinding,
        identifier: (IOSKeyboardBindingIdentifier.Variant) -> IOSKeyboardBindingIdentifier,
        indices: [Int],
        command: (Int) -> IOSAppCommand
    ) -> [IOSResolvedCommandShortcut] {
        var result: [IOSResolvedCommandShortcut] = []
        let groups: [(String, IOSKeyboardBindingIdentifier.Variant, IOSKeyboardModifiers?)] = [
            ("primary", .primary, modifiers.primary),
            ("alternate", .alternate, modifiers.alternate)
        ]
        for (variantName, variant, modifierGroup) in groups {
            guard let modifierGroup,
                  IOSKeyboardShortcutValidator.validateDigitModifiers(
                      modifierGroup,
                      replacing: identifier(variant),
                      settings: environment.iosHardwareKeyboardSettings,
                      actions: environment.customActions,
                      engines: environment.services
                  ) == nil else { continue }
            for index in indices {
                let label = SessionSlots.label(for: index)
                result.append(
                    IOSResolvedCommandShortcut(
                        id: "\(prefix)-\(variantName)-\(index)",
                        title: "\(title) \(label)",
                        command: command(index),
                        shortcut: IOSKeyboardShortcut(label, modifiers: modifierGroup)
                    )
                )
            }
        }
        return result
    }

    private var actionShortcuts: [IOSResolvedCommandShortcut] {
        environment.customActions.compactMap { action in
            guard let shortcut = environment.iosHardwareKeyboardSettings.actionShortcut(for: action.id),
                  isValid(shortcut, replacing: .action(action.id)) else {
                return nil
            }
            return IOSResolvedCommandShortcut(
                id: "action-\(action.id)",
                title: action.name,
                command: .runAction(actionID: action.id, engineID: nil),
                shortcut: shortcut
            )
        }
    }

    private var engineShortcuts: [IOSResolvedCommandShortcut] {
        environment.services.compactMap { engine in
            guard let shortcut = environment.iosHardwareKeyboardSettings.engineShortcut(for: engine.id),
                  isValid(shortcut, replacing: .engine(engine.id)) else {
                return nil
            }
            return IOSResolvedCommandShortcut(
                id: "engine-binding-\(engine.id)",
                title: "Open \(engine.name)",
                command: .openEngine(engine.id),
                shortcut: shortcut
            )
        }
    }

    private func isValid(
        _ shortcut: IOSKeyboardShortcut,
        replacing identifier: IOSKeyboardBindingIdentifier
    ) -> Bool {
        IOSKeyboardShortcutValidator.validate(
            shortcut,
            replacing: identifier,
            settings: environment.iosHardwareKeyboardSettings,
            actions: environment.customActions,
            engines: environment.services
        ) == nil
    }

    private func execute(_ command: IOSAppCommand) {
        guard let sceneContext, !sceneContext.isRecordingShortcut else { return }
        Task {
            do {
                _ = try await environment.commandExecutor.execute(command, sceneContext: sceneContext)
            } catch {
                sceneContext.report(error)
            }
        }
    }

    private func keyboardShortcut(
        from shortcut: IOSKeyboardShortcut
    ) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        guard shortcut.input.count == 1, let character = shortcut.input.first else { return nil }
        return (KeyEquivalent(character), EventModifiers(shortcut.modifiers))
    }

    private static let fixedShortcuts: [IOSResolvedCommandShortcut] =
        IOSFixedKeyboardShortcut.all.compactMap { item in
            guard let command = fixedCommand(id: item.id) else { return nil }
            return .init(id: item.id, title: item.title, command: command, shortcut: item.shortcut)
        }

    private static func fixedCommand(id: String) -> IOSAppCommand? {
        switch id {
        case "history": .showHistory
        case "mru": .cycleMRU(reverse: false)
        case "mru-reverse": .cycleMRU(reverse: true)
        case "close": .closeSession
        case "reload": .reload(.normal)
        case "force-reload": .reload(.force)
        case "origin-reload": .reload(.fromOrigin)
        case "find": .find(.show)
        case "find-next": .find(.next)
        case "find-previous": .find(.previous)
        case "settings": .showSettings
        case "zoom-in": .zoom(.inStep)
        case "zoom-out": .zoom(.outStep)
        case "zoom-reset": .zoom(.reset)
        default: nil
        }
    }
}

private extension IOSConfigurableKeyboardCommand {
    var appCommand: IOSAppCommand {
        switch self {
        case .nextSession: .nextSession
        case .previousSession: .previousSession
        case .nextEngine: .nextEngine
        case .previousEngine: .previousEngine
        case .lockCurrentEngine: .lock(.current)
        }
    }
}

private extension EventModifiers {
    init(_ modifiers: IOSKeyboardModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
        if modifiers.contains(.shift) { insert(.shift) }
    }
}
