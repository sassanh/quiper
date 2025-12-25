import SwiftUI
import AppKit
import Carbon

struct KeyBindingsSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @EnvironmentObject var shortcutState: ShortcutRecordingState
    @State private var pendingDeletion: PendingDeletion?
    @State private var activationStatus: [UUID: String] = [:]
    @State private var globalHotkeyStatus = ""
    var appController: AppController?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List {
                Section("Custom Actions") {
                    ForEach(Array(settings.customActions.indices), id: \.self) { index in
                        ActionRow(
                            action: $settings.customActions[index],
                            onRecord: { recordShortcut(for: settings.customActions[index].id) },
                            onClear: { clearShortcut(for: settings.customActions[index].id) },
                            onDelete: { confirmDeletion(for: settings.customActions[index]) }
                        )
                    }
                }
                
                Section("Global") {
                    GlobalShortcutRow(
                        title: "Show/Hide Quiper",
                        detail: "Defaults to ⌥Space. When running inside Xcode, ⌃Space also works for convenience.",
                        value: currentGlobalHotkeyLabel,
                        statusMessage: globalHotkeyStatus,
                        onRecord: startGlobalHotkeyCapture,
                        onClear: globalHotkeyClearAction,
                        onReset: globalHotkeyResetAction,
                        axIdentifier: "GlobalShortcutButton"
                    )
                }

                Section("App Shortcuts") {
                    ForEach(AppShortcutBindings.Key.allCases) { key in
                        let primary = settings.appShortcutBindings.configuration(for: key)
                        let alternate = settings.appShortcutBindings.alternateConfiguration(for: key)
                        let defaultPrimary = AppShortcutBindings.defaults.configuration(for: key)
                        let defaultAlternate = AppShortcutBindings.defaults.alternateConfiguration(for: key)
                        
                        AppShortcutRow(
                            title: title(for: key),
                            detail: detail(for: key),
                            primaryValue: ShortcutFormatter.string(for: primary),
                            alternateValue: alternate.map { ShortcutFormatter.string(for: $0) } ?? "Disabled",
                            onRecordPrimary: { recordAppShortcut(key, slot: .primary) },
                            onRecordAlternate: { recordAppShortcut(key, slot: .alternate) },
                            onClearPrimary: primary.isDisabled ? nil : { clearPrimaryAppShortcut(key) },
                            onClearAlternate: alternate == nil ? nil : { clearAlternateAppShortcut(key) },
                            onResetPrimary: primary == defaultPrimary ? nil : { resetPrimaryAppShortcut(key) },
                            onResetAlternate: alternate == defaultAlternate ? nil : { resetAlternateAppShortcut(key) },
                            primaryIdentifier: "recorder_\(key.rawValue)_primary",
                            alternateIdentifier: "recorder_\(key.rawValue)_alternate"
                        )
                    }

                    DigitModifierRow(
                        title: "Go to session 1–10",
                        detail: "Modifier + number picks a session slot (1–0).",
                        primaryValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.sessionDigitsModifiers, digitLabel: "1–0"),
                        alternateValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.sessionDigitsAlternateModifiers, digitLabel: "1–0"),
                        onRecordPrimary: { recordModifierCapture(.sessionDigits, slot: .primary) },
                        onRecordAlternate: { recordModifierCapture(.sessionDigits, slot: .alternate) },
                        onClearPrimary: settings.appShortcutBindings.sessionDigitsModifiers == 0 ? nil : { clearModifier(.sessionDigits) },
                        onClearAlternate: settings.appShortcutBindings.sessionDigitsAlternateModifiers == nil ? nil : { clearAlternateModifier(.sessionDigits) },
                        onResetPrimary: settings.appShortcutBindings.sessionDigitsModifiers == AppShortcutBindings.defaults.sessionDigitsModifiers ? nil : { resetModifier(.sessionDigits) },
                        onResetAlternate: settings.appShortcutBindings.sessionDigitsAlternateModifiers == AppShortcutBindings.defaults.sessionDigitsAlternateModifiers ? nil : { resetAlternateModifier(.sessionDigits) },
                        primaryIdentifier: "recorder_sessionDigits_primary",
                        alternateIdentifier: "recorder_sessionDigits_alternate"
                    )

                    DigitModifierRow(
                        title: "Go to engine 1–10",
                        detail: "Modifier + number selects an engine slot (1–10).",
                        primaryValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.serviceDigitsPrimaryModifiers, digitLabel: "1–0"),
                        alternateValue: modifierDisplay(rawModifiers: settings.appShortcutBindings.serviceDigitsSecondaryModifiers, digitLabel: "1–0"),
                        onRecordPrimary: { recordModifierCapture(.serviceDigitsPrimary, slot: .primary) },
                        onRecordAlternate: { recordModifierCapture(.serviceDigitsSecondary, slot: .alternate) },
                        onClearPrimary: settings.appShortcutBindings.serviceDigitsPrimaryModifiers == 0 ? nil : { clearModifier(.serviceDigitsPrimary) },
                        onClearAlternate: settings.appShortcutBindings.serviceDigitsSecondaryModifiers == nil ? nil : { clearAlternateModifier(.serviceDigitsSecondary) },
                        onResetPrimary: settings.appShortcutBindings.serviceDigitsPrimaryModifiers == AppShortcutBindings.defaults.serviceDigitsPrimaryModifiers ? nil : { resetModifier(.serviceDigitsPrimary) },
                        onResetAlternate: settings.appShortcutBindings.serviceDigitsSecondaryModifiers == AppShortcutBindings.defaults.serviceDigitsSecondaryModifiers ? nil : { resetAlternateModifier(.serviceDigitsSecondary) },
                        primaryIdentifier: "recorder_serviceDigitsPrimary_primary",
                        alternateIdentifier: "recorder_serviceDigitsSecondary_alternate"
                    )
                }

                serviceHotkeysSection
            }
            .accessibilityIdentifier("ShortcutsList")
        }
        .padding()
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Blank Action") {
                        addBlankAction()
                    }
                    if !settings.defaultActionTemplates.isEmpty {
                        Divider()
                        ForEach(settings.defaultActionTemplates) { template in
                            Button(template.name) {
                                addAction(from: template)
                            }
                        }
                        Divider()
                        Button {
                            addAllActionTemplates()
                        } label: {
                            Label("Add All Templates", systemImage: "plus.rectangle.on.rectangle")
                        }
                    }
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .accessibilityIdentifier("Add Action")
                .help("Create a blank action or add one from templates")
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

    private var currentGlobalHotkeyLabel: String {
        ShortcutFormatter.string(for: settings.hotkeyConfiguration)
    }

    private func startGlobalHotkeyCapture() {
        let session = StandardShortcutSession(onUpdate: { update in
            shortcutState.updateMessage(update)
        }, onFinish: {
            shortcutState.cancel()
        }, completion: { configuration in
            if let configuration {
                settings.hotkeyConfiguration = configuration
                settings.saveSettings()
                appController?.updateOverlayHotkey(configuration)
                globalHotkeyStatus = "Saved as \(ShortcutFormatter.string(for: configuration))"
            } else {
                globalHotkeyStatus = ""
            }
        })
        shortcutState.start(session: session, title: "Show/Hide Quiper")
    }

    private func resetGlobalHotkey() {
        let configuration = HotkeyManager.defaultConfiguration
        settings.hotkeyConfiguration = configuration
        settings.saveSettings()
        appController?.updateOverlayHotkey(configuration)
        globalHotkeyStatus = "Reset to ⌥Space"
    }
    
    private func clearGlobalHotkey() {
        settings.hotkeyConfiguration = HotkeyManager.Configuration(keyCode: 0, modifierFlags: 0)
        settings.saveSettings()
        appController?.updateOverlayHotkey(settings.hotkeyConfiguration)
        globalHotkeyStatus = "Cleared"
    }
    
    private var globalHotkeyClearAction: (() -> Void)? {
        if settings.hotkeyConfiguration.isDisabled {
            return nil
        } else {
            return clearGlobalHotkey
        }
    }
    
    private var globalHotkeyResetAction: (() -> Void)? {
        if settings.hotkeyConfiguration == HotkeyManager.defaultConfiguration {
            return nil
        } else {
            return resetGlobalHotkey
        }
    }

    private func addBlankAction() {
        settings.customActions.append(CustomAction(name: "New Action"))
    }

    private func addAction(from template: CustomAction) {
        guard !settings.customActions.contains(where: { $0.id == template.id }) else { return }
        settings.customActions.append(template)
        applyDefaultScripts(for: template)
        settings.saveSettings()
    }

    private func addAllActionTemplates() {
        var existingIDs = Set(settings.customActions.map { $0.id })

        for template in settings.defaultActionTemplates {
            guard !existingIDs.contains(template.id) else { continue }
            settings.customActions.append(template)
            existingIDs.insert(template.id)
            applyDefaultScripts(for: template)
        }
        settings.saveSettings()
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
        }, reservedActionCheck: { config in
            let modifiers = NSEvent.ModifierFlags(rawValue: config.modifierFlags)
            let keyCode = UInt16(config.keyCode)
            return ShortcutValidator.reservedActionName(modifiers: modifiers, keyCode: keyCode, excludingActionId: id)
        }, completion: { configuration in
            if let configuration, let index = settings.customActions.firstIndex(where: { $0.id == id }) {
                settings.customActions[index].shortcut = configuration
                settings.saveSettings()
            }
        })
        let actionName = settings.customActions.first(where: { $0.id == id })?.name ?? "Action"
        shortcutState.start(session: session, title: actionName)
    }

    private func clearShortcut(for id: UUID) {
        if let index = settings.customActions.firstIndex(where: { $0.id == id }) {
            settings.customActions[index].shortcut = nil
            settings.saveSettings()
        }
    }

    private func applyDefaultScripts(for action: CustomAction) {
        for index in settings.services.indices {
            applyDefaultScript(for: action, toServiceAt: index)
        }
    }

    private func applyDefaultScript(for action: CustomAction, toServiceAt index: Int) {
        let serviceName = settings.services[index].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let template = settings.defaultServiceTemplates.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == serviceName
        }),
              let defaultScript = template.actionScripts[action.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !defaultScript.isEmpty else { return }

        let existing = settings.services[index].actionScripts[action.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }

        settings.services[index].actionScripts[action.id] = defaultScript
        ActionScriptStorage.saveScript(defaultScript, serviceID: settings.services[index].id, actionID: action.id)
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
        shortcutState.start(session: session, title: title(for: key))
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
        let groupTitle: String
        switch group {
        case .sessionDigits: groupTitle = "Go to session 1–10"
        case .serviceDigitsPrimary, .serviceDigitsSecondary: groupTitle = "Go to engine 1–10"
        }
        shortcutState.start(session: session, title: groupTitle)
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

    private func startActivationCapture(for serviceID: UUID) {
        let session = StandardShortcutSession(onUpdate: { update in
            shortcutState.updateMessage(update)
        }, onFinish: {
            shortcutState.cancel()
        }, completion: { configuration in
            if let configuration, let index = settings.services.firstIndex(where: { $0.id == serviceID }) {
                settings.services[index].activationShortcut = configuration
                settings.saveSettings()
                Task { @MainActor in
                    NSLog("[Quiper] ActionsSettingsView calling reloadServices for \(serviceID)")
                    appController?.reloadServices()
                }
                activationStatus[serviceID] = "Saved"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    activationStatus[serviceID] = nil
                }
            }
        })
        let serviceName = settings.services.first(where: { $0.id == serviceID })?.name ?? "Service"
        shortcutState.start(session: session, title: "Launch \(serviceName)")
    }

    private func clearActivation(for serviceID: UUID) {
        guard let index = settings.services.firstIndex(where: { $0.id == serviceID }) else { return }
        settings.services[index].activationShortcut = nil
        settings.saveSettings()
        Task { @MainActor in
            NSLog("[Quiper] ActionsSettingsView clearing hotkey, calling reloadServices for \(serviceID)")
            appController?.reloadServices()
        }
        activationStatus[serviceID] = "Cleared"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            activationStatus[serviceID] = nil
        }
    }
    
    @ViewBuilder
    private var serviceHotkeysSection: some View {
        if settings.services.isEmpty {
            EmptyView()
        } else {
            Section("Service Hotkeys") {
                ForEach($settings.services) { $service in
                    ServiceLaunchShortcutRow(
                        title: service.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Service" : service.name,
                        shortcut: service.activationShortcut,
                        statusMessage: activationStatus[service.id] ?? "",
                        onTap: { startActivationCapture(for: service.id) },
                        onClear: { clearActivation(for: service.id) },
                        axIdentifier: "recorder_launch_\(service.name)"
                    )
                }
            }
        }
    }



    private func title(for key: AppShortcutBindings.Key) -> String {
        switch key {
        case .previousSession: return "Previous session"
        case .nextSession: return "Next session"
        case .previousService: return "Previous engine"
        case .nextService: return "Next engine"
        }
    }

    private func detail(for key: AppShortcutBindings.Key) -> String {
        switch key {
        case .previousSession: return "Cycle to the session on the left."
        case .nextSession: return "Cycle to the session on the right."
        case .previousService: return "Move to the previous engine."
        case .nextService: return "Move to the next engine."
        }
    }

    private func modifierDisplay(rawModifiers: UInt?, digitLabel: String) -> String {
        guard let rawModifiers, rawModifiers > 0 else { return "Disabled" }
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
    var onClearPrimary: (() -> Void)?
    var onClearAlternate: (() -> Void)?
    var onResetPrimary: (() -> Void)?
    var onResetAlternate: (() -> Void)?
    var primaryIdentifier: String?
    var alternateIdentifier: String?

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
                    onReset: onResetPrimary,
                    axIdentifier: primaryIdentifier
                )
                
                LabeledShortcutButton(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
                    onClear: onClearAlternate,
                    onReset: onResetAlternate,
                    axIdentifier: alternateIdentifier
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
    var onClearPrimary: (() -> Void)?
    var onClearAlternate: (() -> Void)?
    var onResetPrimary: (() -> Void)?
    var onResetAlternate: (() -> Void)?
    var primaryIdentifier: String?
    var alternateIdentifier: String?

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
                    onReset: onResetPrimary,
                    axIdentifier: primaryIdentifier
                )
                LabeledShortcutButton(
                    label: "Alternate",
                    text: alternateValue,
                    isPlaceholder: alternateValue == "Disabled",
                    onTap: onRecordAlternate,
                    onClear: onClearAlternate,
                    onReset: onResetAlternate,
                    axIdentifier: alternateIdentifier
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
                .accessibilityIdentifier(action.name)
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

private struct GlobalShortcutRow: View {
    let title: String
    let detail: String
    let value: String
    let statusMessage: String
    var onRecord: () -> Void
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    var axIdentifier: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 320, alignment: .leading)
            Spacer()
            ShortcutButton(
                text: value,
                isPlaceholder: value == "Disabled",
                onTap: onRecord,
                onClear: onClear,
                onReset: onReset,
                width: 200,
                axIdentifier: axIdentifier ?? "ShortcutRecorder"
            )
        }
        .padding(.vertical, 10)
    }
}
