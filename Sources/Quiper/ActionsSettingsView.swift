import SwiftUI
import AppKit
import Carbon

struct KeyBindingsSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var captureMessage: String = "Waiting for key press…"
    @State private var captureSession: ShortcutCaptureSession?
    @State private var pendingDeletion: PendingDeletion?
    @State private var captureTarget: CaptureTarget?
    @State private var modifierMonitor: Any?

    var body: some View {
        ZStack {
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
                            onResetPrimary: { resetModifier(.serviceDigitsPrimary) },
                            onResetAlternate: { resetAlternateModifier(.serviceDigitsSecondary) }
                        )
                    }
                }
            }
            if captureTarget != nil {
                ShortcutCaptureOverlayView(message: captureMessage, onCancel: cancelCapture)
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
        captureTarget = .customAction(id)
        captureMessage = "Waiting for key press…"
        captureSession = ShortcutCaptureSession(onUpdate: { text in
            captureMessage = text
        }, completion: { configuration in
            if let configuration, let index = settings.customActions.firstIndex(where: { $0.id == id }) {
                settings.customActions[index].shortcut = configuration
                settings.saveSettings()
            }
            captureTarget = nil
            captureSession = nil
        })
    }

    private func clearShortcut(for id: UUID) {
        if let index = settings.customActions.firstIndex(where: { $0.id == id }) {
            settings.customActions[index].shortcut = nil
            settings.saveSettings()
        }
    }

    private func recordAppShortcut(_ key: AppShortcutBindings.Key, slot: CaptureSlot) {
        captureTarget = .appShortcut(key, slot)
        captureMessage = "Press the new shortcut"
        captureSession = ShortcutCaptureSession(onUpdate: { text in
            captureMessage = text
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
            captureTarget = nil
            captureSession = nil
        })
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

    private func recordModifierCapture(_ group: AppShortcutBindings.ModifierGroup, slot: CaptureSlot) {
        captureTarget = .modifierGroup(group, slot)
        captureMessage = "Press modifier + digit (1–0)"
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                endModifierCapture()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let keyCode = UInt16(event.keyCode)
            guard isDigitKey(keyCode), !modifiers.isEmpty else {
                NSSound.beep()
                captureMessage = "Use modifiers with digits 0–9"
                return nil
            }

            switch group {
            case .sessionDigits:
                if slot == .primary {
                    settings.appShortcutBindings.sessionDigitsModifiers = modifiers.rawValue
                } else {
                    settings.appShortcutBindings.sessionDigitsAlternateModifiers = modifiers.rawValue
                }
            case .serviceDigitsPrimary:
                if slot == .primary {
                    settings.appShortcutBindings.serviceDigitsPrimaryModifiers = modifiers.rawValue
                } else {
                    settings.appShortcutBindings.serviceDigitsSecondaryModifiers = modifiers.rawValue
                }
            case .serviceDigitsSecondary:
                if slot == .primary {
                    settings.appShortcutBindings.serviceDigitsPrimaryModifiers = modifiers.rawValue
                } else {
                    settings.appShortcutBindings.serviceDigitsSecondaryModifiers = modifiers.rawValue
                }
            }
            settings.saveSettings()
            endModifierCapture()
            return nil
        }
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
            settings.appShortcutBindings.sessionDigitsAlternateModifiers = nil
        case .serviceDigitsPrimary, .serviceDigitsSecondary:
            settings.appShortcutBindings.serviceDigitsSecondaryModifiers = nil
        }
        settings.saveSettings()
    }

    private func endModifierCapture() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        captureTarget = nil
    }

    private func cancelCapture() {
        captureSession?.cancel()
        captureSession = nil
        endModifierCapture()
        captureTarget = nil
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

private enum CaptureTarget: Equatable {
    case customAction(UUID)
    case appShortcut(AppShortcutBindings.Key, CaptureSlot)
    case modifierGroup(AppShortcutBindings.ModifierGroup, CaptureSlot)
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
                LabeledBadge(
                    label: "Primary",
                    text: primaryValue,
                    isPlaceholder: false,
                    onTap: onRecordPrimary,
                    onReset: onResetPrimary
                )
                LabeledBadge(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
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
                LabeledBadge(
                    label: "Primary",
                    text: primaryValue,
                    isPlaceholder: primaryValue == "Disabled",
                    onTap: onRecordPrimary,
                    onReset: onResetPrimary
                )
                LabeledBadge(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
                    onReset: onResetAlternate
                )
            }
        }
        .padding(.vertical, 10)
    }
}

private struct ShortcutBadge: View {
    var text: String
    var isPlaceholder: Bool = false
    var onTap: () -> Void
    var onReset: () -> Void
    var width: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: width, height: 40)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .frame(width: width - 28, alignment: .center) // leave space for reset icon

            HStack {
                Spacer()
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .padding(.top, 2)
            }
            .frame(width: width, height: 40, alignment: .topTrailing)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onTap()
        }
    }
}

private struct LabeledBadge: View {
    var label: String
    var text: String
    var isPlaceholder: Bool
    var onTap: () -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            ShortcutBadge(
                text: text,
                isPlaceholder: isPlaceholder,
                onTap: onTap,
                onReset: onReset,
                width: 180
            )
        }
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
            Button(action: onRecord) {
                Text(action.shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 140, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .overlay(alignment: .trailing) {
                if action.shortcut != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 6)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the recorded shortcut but keep the action")
                }
            }

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

private struct ShortcutCaptureOverlayView: View {
    var message: String
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Press the new shortcut")
                    .font(.headline)
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Cancel", action: onCancel)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
        }
    }
}

private final class ShortcutCaptureSession {
    private var monitor: Any?
    private let onUpdate: (String) -> Void
    private let completion: (HotkeyManager.Configuration?) -> Void

    init(onUpdate: @escaping (String) -> Void, completion: @escaping (HotkeyManager.Configuration?) -> Void) {
        self.onUpdate = onUpdate
        self.completion = completion
        attachKeyMonitor()
    }

    func cancel() {
        finish(nil)
    }

    private func attachKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.finish(nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if ShortcutValidator.isReservedActionShortcut(modifiers: modifiers, keyCode: event.keyCode) {
                NSSound.beep()
                self.onUpdate("Shortcut reserved by Quiper")
                return nil
            }
            let configuration = HotkeyManager.Configuration(keyCode: UInt32(event.keyCode), modifierFlags: modifiers.rawValue)
            guard ShortcutValidator.allows(configuration: configuration) else {
                NSSound.beep()
                self.onUpdate("Shortcut must include Command/Option/Control/Shift")
                return nil
            }
            self.onUpdate(ShortcutFormatter.string(for: modifiers, keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
            self.finish(configuration)
            return nil
        }
    }

    private func finish(_ configuration: HotkeyManager.Configuration?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        completion(configuration)
    }
}
