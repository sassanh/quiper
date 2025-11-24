import SwiftUI
import AppKit
import Carbon

struct KeyBindingsSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @EnvironmentObject var shortcutState: ShortcutRecordingState
    @State private var pendingDeletion: PendingDeletion?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                List {
                    Section("Actions") {
                        ForEach(Array(settings.customActions.indices), id: \.self) { index in
                            ActionRow(
                                action: $settings.customActions[index],
                                onRecord: { recordShortcut(for: settings.customActions[index].id) },
                                onClear: { clearShortcut(for: settings.customActions[index].id) },
                                onDelete: { confirmDeletion(for: settings.customActions[index]) }
                            )
                        }
                    }

                    Section("App Shortcuts") {
                        ForEach(AppShortcutBindings.Key.allCases) { key in
                            AppShortcutRow(
                                title: title(for: key),
                                detail: detail(for: key),
                                primaryValue: ShortcutFormatter.string(for: settings.appShortcutBindings.configuration(for: key)),
                                alternateValue: settings.appShortcutBindings.alternateConfiguration(for: key).map { ShortcutFormatter.string(for: $0) } ?? "Disabled",
                                onRecordPrimary: { recordAppShortcut(key, slot: .primary) },
                                onRecordAlternate: { recordAppShortcut(key, slot: .alternate) },
                                onClearPrimary: { clearPrimaryAppShortcut(key) },
                                onClearAlternate: { clearAlternateAppShortcut(key) },
                                onResetPrimary: { resetPrimaryAppShortcut(key) },
                                onResetAlternate: { resetAlternateAppShortcut(key) }
                            )
                        }

                        DigitModifierRow(
                            title: "Go to session 1–10",
                            detail: "Modifier + number picks a session slot (1–0).",
                            primaryValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.sessionDigitsModifiers, digitLabel: "1–0"),
                            alternateValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.sessionDigitsAlternateModifiers, digitLabel: "1–0"),
                            onRecordPrimary: { recordModifierCapture(.sessionDigits, slot: .primary) },
                            onRecordAlternate: { recordModifierCapture(.sessionDigits, slot: .alternate) },
                            onClearPrimary: { clearModifier(.sessionDigits) },
                            onClearAlternate: { clearAlternateModifier(.sessionDigits) },
                            onResetPrimary: { resetModifier(.sessionDigits) },
                            onResetAlternate: { resetAlternateModifier(.sessionDigits) }
                        )

                        DigitModifierRow(
                            title: "Go to service 1–10",
                            detail: "Modifier + number selects a service slot (1–10).",
                            primaryValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.serviceDigitsPrimaryModifiers, digitLabel: "1–0"),
                            alternateValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.serviceDigitsSecondaryModifiers, digitLabel: "1–0"),
                            onRecordPrimary: { recordModifierCapture(.serviceDigitsPrimary, slot: .primary) },
                            onRecordAlternate: { recordModifierCapture(.serviceDigitsSecondary, slot: .alternate) },
                            onClearPrimary: { clearModifier(.serviceDigitsPrimary) },
                            onClearAlternate: { clearAlternateModifier(.serviceDigitsSecondary) },
                            onResetPrimary: { resetModifier(.serviceDigitsPrimary) },
                            onResetAlternate: { resetAlternateModifier(.serviceDigitsSecondary) }
                        )
                    }
            }
        }
        .padding()
        .toolbar {
            ToolbarItem {
                Button(action: addAction) {
                    Label("Add Action", systemImage: "plus")
                }
            }
        }
        .onChange(of: settings.customActions) { _, _ in
            settings.saveSettings()
        }
        .alert(item: $pendingDeletion) { pending in
            Alert(
                title: Text("Delete \(pending.displayName)?"),
                message: Text("This removes the shortcut and any custom scripts bound to this action across your services."),
                primaryButton: .destructive(Text("Delete")) {
                    removeAction(id: pending.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func addAction() {
        settings.customActions.append(CustomAction(name: "New Action"))
    }

    private func removeAction(id: UUID) {
        guard let index = settings.customActions.firstIndex(where: { $0.id == id }) else { return }
        settings.customActions.remove(at: index)
        settings.deleteScripts(for: id)
    }

    private func confirmDeletion(for action: CustomAction) {
        pendingDeletion = PendingDeletion(id: action.id, name: action.name)
    }

    private func recordShortcut(for id: UUID) {
        let session = StandardShortcutSession(onUpdate: { update in
            shortcutState.updateMessage(update)
        }, onFinish: {
            shortcutState.cancel()
        }, additionalValidation: { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if let name = ShortcutValidator.reservedActionName(modifiers: modifiers, keyCode: event.keyCode) {
                return "Shortcut reserved for \(name)"
            }
            return nil
        }, completion: { configuration in
            if let configuration, let index = settings.customActions.firstIndex(where: { $0.id == id }) {
                settings.customActions[index].shortcut = configuration
                settings.saveSettings()
            }
        })
        shortcutState.start(session: session)
    }

    private func clearShortcut(for id: UUID) {
        if let index = settings.customActions.firstIndex(where: { $0.id == id }) {
            settings.customActions[index].shortcut = nil
            settings.saveSettings()
        }
    }

    private func recordAppShortcut(_ key: AppShortcutBindings.Key, slot: CaptureSlot) {
        let session = StandardShortcutSession(onUpdate: { update in
            shortcutState.updateMessage(update)
        }, onFinish: {
            shortcutState.cancel()
        }, completion: { configuration in
            if let configuration {
                switch slot {
                case .primary:
                    settings.appShortcutBindings.setConfiguration(configuration, for: key)
                case .alternate:
                    settings.appShortcutBindings.setAlternateConfiguration(configuration, for: key)
                }
                settings.saveSettings()
            }
        })
        shortcutState.start(session: session)
    }

    private func resetPrimaryAppShortcut(_ key: AppShortcutBindings.Key) {
        settings.appShortcutBindings.setConfiguration(settings.appShortcutBindings.defaultConfiguration(for: key), for: key)
        settings.saveSettings()
    }

    private func resetAlternateAppShortcut(_ key: AppShortcutBindings.Key) {
        let defaultAlt = AppShortcutBindings.defaults.alternateConfiguration(for: key)
        settings.appShortcutBindings.setAlternateConfiguration(defaultAlt, for: key)
        settings.saveSettings()
    }
    
    private func clearPrimaryAppShortcut(_ key: AppShortcutBindings.Key) {
        settings.appShortcutBindings.setConfiguration(HotkeyManager.Configuration(keyCode: 0, modifierFlags: 0), for: key)
        settings.saveSettings()
    }
    
    private func clearAlternateAppShortcut(_ key: AppShortcutBindings.Key) {
        settings.appShortcutBindings.setAlternateConfiguration(nil, for: key)
        settings.saveSettings()
    }

    private func recordModifierCapture(_ group: AppShortcutBindings.ModifierGroup, slot: CaptureSlot) {
        let session = ModifierCaptureSession(onUpdate: { update in
            shortcutState.updateMessage(update)
        }, onFinish: {
            shortcutState.cancel()
        }, completion: { modifiers, keyCode in
            switch group {
            case .sessionDigits:
                if slot == .primary {
                    settings.appShortcutBindings.sessionDigitsModifiers = modifiers
                } else {
                    settings.appShortcutBindings.sessionDigitsAlternateModifiers = modifiers
                }
            case .serviceDigitsPrimary:
                if slot == .primary {
                    settings.appShortcutBindings.serviceDigitsPrimaryModifiers = modifiers
                } else {
                    settings.appShortcutBindings.serviceDigitsSecondaryModifiers = modifiers
                }
            case .serviceDigitsSecondary:
                if slot == .primary {
                    settings.appShortcutBindings.serviceDigitsPrimaryModifiers = modifiers
                } else {
                    settings.appShortcutBindings.serviceDigitsSecondaryModifiers = modifiers
                }
            }
            settings.saveSettings()
        })
        shortcutState.start(session: session)
    }

    private func resetModifier(_ group: AppShortcutBindings.ModifierGroup) {
        switch group {
        case .sessionDigits:
            settings.appShortcutBindings.sessionDigitsModifiers = AppShortcutBindings.defaults.sessionDigitsModifiers
        case .serviceDigitsPrimary:
            settings.appShortcutBindings.serviceDigitsPrimaryModifiers = AppShortcutBindings.defaults.serviceDigitsPrimaryModifiers
        case .serviceDigitsSecondary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = AppShortcutBindings.defaults.serviceDigitsSecondaryModifiers
        }
        settings.saveSettings()
    }

    private func resetAlternateModifier(_ group: AppShortcutBindings.ModifierGroup) {
        switch group {
        case .sessionDigits:
            settings.appShortcutBindings.sessionDigitsAlternateModifiers = AppShortcutBindings.defaults.sessionDigitsAlternateModifiers
        case .serviceDigitsPrimary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = AppShortcutBindings.defaults.serviceDigitsSecondaryModifiers
        case .serviceDigitsSecondary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = AppShortcutBindings.defaults.serviceDigitsSecondaryModifiers
        }
        settings.saveSettings()
    }
    
    private func clearModifier(_ group: AppShortcutBindings.ModifierGroup) {
        switch group {
        case .sessionDigits:
            settings.appShortcutBindings.sessionDigitsModifiers = 0
        case .serviceDigitsPrimary:
            settings.appShortcutBindings.serviceDigitsPrimaryModifiers = 0
        case .serviceDigitsSecondary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = 0
        }
        settings.saveSettings()
    }
    
    private func clearAlternateModifier(_ group: AppShortcutBindings.ModifierGroup) {
        switch group {
        case .sessionDigits:
            settings.appShortcutBindings.sessionDigitsAlternateModifiers = nil
        case .serviceDigitsPrimary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = nil
        case .serviceDigitsSecondary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = nil
        }
        settings.saveSettings()
    }



    private func title(for key: AppShortcutBindings.Key) -> String {
        switch key {
        case .previousSession: return "Previous session"
        case .nextSession: return "Next session"
        case .previousService: return "Previous service"
        case .nextService: return "Next service"
        }
    }

    private func detail(for key: AppShortcutBindings.Key) -> String {
        switch key {
        case .previousSession: return "Cycle to the session on the left."
        case .nextSession: return "Cycle to the session on the right."
        case .previousService: return "Move to the previous service."
        case .nextService: return "Move to the next service."
        }
    }

    private func modifierDisplay(rawModifiers: UInt?, digitLabel: String) -> String {
        guard let rawModifiers else { return "Disabled" }
        let mods = NSEvent.ModifierFlags(rawValue: rawModifiers)
        var string = ""
        if mods.contains(.control) { string += "⌃" }
        if mods.contains(.option) { string += "⌥" }
        if mods.contains(.shift) { string += "⇧" }
        if mods.contains(.command) { string += "⌘" }
        if string.isEmpty { string = "None" }
        return "\(string) + \(digitLabel)"
    }

    private func isDigitKey(_ keyCode: UInt16) -> Bool {
        return ShortcutValidatorIsDigitKey.keyCodes.contains(keyCode)
    }
}



private enum CaptureSlot {
    case primary
    case alternate
}

private struct AppShortcutRow: View {
    let title: String
    let detail: String
    let primaryValue: String
    let alternateValue: String
    var onRecordPrimary: () -> Void
    var onRecordAlternate: () -> Void
    var onClearPrimary: () -> Void
    var onClearAlternate: () -> Void
    var onResetPrimary: () -> Void
    var onResetAlternate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)
            Spacer()
            HStack(alignment: .top, spacing: 20) {
                LabeledShortcutButton(
                    label: "Primary",
                    text: primaryValue,
                    isPlaceholder: false,
                    onTap: onRecordPrimary,
                    onClear: onClearPrimary,
                    onReset: onResetPrimary
                )
                LabeledShortcutButton(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
                    onClear: onClearAlternate,
                    onReset: onResetAlternate
                )
            }
        }
        .padding(.vertical, 10)
    }
}

private struct DigitModifierRow: View {
    let title: String
    let detail: String
    let primaryValue: String
    let alternateValue: String
    var onRecordPrimary: () -> Void
    var onRecordAlternate: () -> Void
    var onClearPrimary: () -> Void
    var onClearAlternate: () -> Void
    var onResetPrimary: () -> Void
    var onResetAlternate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)
            Spacer()
            HStack(alignment: .top, spacing: 20) {
                LabeledShortcutButton(
                    label: "Primary",
                    text: primaryValue,
                    isPlaceholder: primaryValue == "Disabled",
                    onTap: onRecordPrimary,
                    onClear: onClearPrimary,
                    onReset: onResetPrimary
                )
                LabeledShortcutButton(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
                    onClear: onClearAlternate,
                    onReset: onResetAlternate
                )
            }
        }
        .padding(.vertical, 10)
    }
}



private enum ShortcutValidatorIsDigitKey {
    static let keyCodes: Set<UInt16> = [
        UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_Keypad0), UInt16(kVK_ANSI_Keypad1), UInt16(kVK_ANSI_Keypad2),
        UInt16(kVK_ANSI_Keypad3), UInt16(kVK_ANSI_Keypad4), UInt16(kVK_ANSI_Keypad5),
        UInt16(kVK_ANSI_Keypad6), UInt16(kVK_ANSI_Keypad7), UInt16(kVK_ANSI_Keypad8),
        UInt16(kVK_ANSI_Keypad9)
    ]
}

private struct ActionRow: View {
    @Binding var action: CustomAction
    var onRecord: () -> Void
    var onClear: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Action name", text: $action.name)
            Spacer()
            ShortcutButton(
                text: action.shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut",
                isPlaceholder: action.shortcut == nil,
                onTap: onRecord,
                onClear: action.shortcut != nil ? onClear : nil,
                onReset: nil,
                width: 160
            )

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete action")
        }
    }
}

private struct PendingDeletion: Identifiable {
    let id: UUID
    let name: String

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this action" : "\(trimmed)"
    }
}

private final class ModifierCaptureSession: CancellableSession {
    private var monitor: Any?
    private let onUpdate: (String) -> Void
    private let onFinish: () -> Void
    private let completion: (UInt, UInt16) -> Void

    init(onUpdate: @escaping (String) -> Void, onFinish: @escaping () -> Void, completion: @escaping (UInt, UInt16) -> Void) {
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        self.completion = completion
        self.onUpdate("Press modifier + digit (1–0)")
        attachKeyMonitor()
    }

    func cancel() {
        finish(nil, nil)
    }

    private func attachKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.finish(nil, nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let keyCode = UInt16(event.keyCode)
            
            guard ShortcutValidatorIsDigitKey.keyCodes.contains(keyCode), !modifiers.isEmpty else {
                NSSound.beep()
                self.onUpdate("Use modifiers with digits 0–9")
                return nil
            }
            
            self.finish(modifiers.rawValue, keyCode)
            return nil
        }
    }

    private var isFinished = false

    private func finish(_ modifiers: UInt?, _ keyCode: UInt16?) {
        guard !isFinished else { return }
        isFinished = true
        
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let modifiers, let keyCode {
            completion(modifiers, keyCode)
        }
        onFinish()
    }
}
