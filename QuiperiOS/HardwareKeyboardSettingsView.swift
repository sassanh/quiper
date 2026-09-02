import SwiftUI
import UIKit

struct HardwareKeyboardSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(IOSSceneCommandContext.self) private var commandContext
    @State private var activeRecorderID: String?
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(
                        environment.isHardwareKeyboardConnected ? "Connected" : "Not Connected",
                        systemImage: environment.isHardwareKeyboardConnected
                            ? "keyboard.badge.ellipsis" : "keyboard"
                    )
                    .foregroundStyle(environment.isHardwareKeyboardConnected ? Color.green : Color.secondary)
                }
            } footer: {
                Text("Shortcuts remain available on iPhone and iPad whenever a physical keyboard is connected.")
            }

            Section("Navigation") {
                ForEach(IOSConfigurableKeyboardCommand.allCases) { command in
                    shortcutPairRow(for: command)
                }
            }

            Section {
                digitModifierRow(title: "Sessions", isSessionGroup: true)
                digitModifierRow(title: "Engines", isSessionGroup: false)
            } header: {
                Text("Direct Selection")
            } footer: {
                Text("Record any modified digit. The same modifiers are applied to 1–9 and 0.")
            }

            Section("Actions") {
                ForEach(environment.customActions) { action in
                    shortcutRow(
                        title: action.name,
                        recorderID: "action-\(action.id)",
                        shortcut: environment.iosHardwareKeyboardSettings.actionShortcut(for: action.id)
                    ) { shortcut in
                        setActionShortcut(shortcut, actionID: action.id)
                    }
                }
            }

            Section("Engines") {
                ForEach(environment.services) { engine in
                    shortcutRow(
                        title: engine.name,
                        recorderID: "engine-\(engine.id)",
                        shortcut: environment.iosHardwareKeyboardSettings.engineShortcut(for: engine.id)
                    ) { shortcut in
                        setEngineShortcut(shortcut, engineID: engine.id)
                    }
                }
            }

            Section {
                ForEach(IOSFixedKeyboardShortcut.all) { item in
                    LabeledContent(item.title) {
                        Text(IOSKeyboardShortcutFormatter.string(for: item.shortcut))
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }
            } header: {
                Text("Fixed Commands")
            } footer: {
                Text("These mobile-relevant commands are always available and cannot be reassigned.")
            }

            Section {
                Button("Restore Defaults") {
                    activeRecorderID = nil
                    environment.restoreDefaultHardwareKeyboardSettings()
                }
            }
        }
        .navigationTitle("Hardware Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: activeRecorderID) { _, recorderID in
            commandContext.isRecordingShortcut = recorderID != nil
        }
        .onDisappear {
            activeRecorderID = nil
            commandContext.isRecordingShortcut = false
        }
        .alert("Shortcut Unavailable", isPresented: validationMessagePresented) {
            Button("OK", role: .cancel) {
                validationMessage = nil
            }
        } message: {
            Text(validationMessage ?? "Choose a different shortcut.")
        }
    }

    private var validationMessagePresented: Binding<Bool> {
        Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )
    }

    private func shortcutPairRow(for command: IOSConfigurableKeyboardCommand) -> some View {
        let binding = environment.iosHardwareKeyboardSettings.binding(for: command)
        return VStack(alignment: .leading, spacing: 8) {
            Text(command.displayTitle)
            HStack {
                Text("Primary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ShortcutRecorderButton(
                    recorderID: "command-\(command.rawValue)-primary",
                    shortcut: binding.primary,
                    activeRecorderID: $activeRecorderID
                ) { shortcut in
                    setCommandShortcut(shortcut, command: command, variant: .primary)
                }
            }
            HStack {
                Text("Alternate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ShortcutRecorderButton(
                    recorderID: "command-\(command.rawValue)-alternate",
                    shortcut: binding.alternate,
                    activeRecorderID: $activeRecorderID
                ) { shortcut in
                    setCommandShortcut(shortcut, command: command, variant: .alternate)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func digitModifierRow(title: String, isSessionGroup: Bool) -> some View {
        let binding = isSessionGroup
            ? environment.iosHardwareKeyboardSettings.sessionDigitModifiers
            : environment.iosHardwareKeyboardSettings.engineDigitModifiers
        let prefix = isSessionGroup ? "session-digits" : "engine-digits"
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
            digitRecorder(
                label: "Primary",
                recorderID: "\(prefix)-primary",
                modifiers: binding.primary,
                isSessionGroup: isSessionGroup,
                variant: .primary
            )
            digitRecorder(
                label: "Alternate",
                recorderID: "\(prefix)-alternate",
                modifiers: binding.alternate,
                isSessionGroup: isSessionGroup,
                variant: .alternate
            )
        }
        .padding(.vertical, 2)
    }

    private func digitRecorder(
        label: String,
        recorderID: String,
        modifiers: IOSKeyboardModifiers?,
        isSessionGroup: Bool,
        variant: IOSKeyboardBindingIdentifier.Variant
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            ShortcutRecorderButton(
                recorderID: recorderID,
                shortcut: modifiers.map { IOSKeyboardShortcut("1", modifiers: $0) },
                displayText: modifiers.map { "\(IOSKeyboardShortcutFormatter.modifierString($0))1–0" },
                activeRecorderID: $activeRecorderID
            ) { shortcut in
                setDigitModifiers(shortcut?.modifiers, isSessionGroup: isSessionGroup, variant: variant)
            }
        }
    }

    private func shortcutRow(
        title: String,
        recorderID: String,
        shortcut: IOSKeyboardShortcut?,
        onChange: @escaping (IOSKeyboardShortcut?) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorderButton(
                recorderID: recorderID,
                shortcut: shortcut,
                activeRecorderID: $activeRecorderID,
                onChange: onChange
            )
        }
    }

    private func setCommandShortcut(
        _ shortcut: IOSKeyboardShortcut?,
        command: IOSConfigurableKeyboardCommand,
        variant: IOSKeyboardBindingIdentifier.Variant
    ) {
        let identifier = IOSKeyboardBindingIdentifier.command(command, variant)
        guard validate(shortcut, replacing: identifier) else { return }
        environment.updateHardwareKeyboardSettings { settings in
            var binding = settings.binding(for: command)
            switch variant {
            case .primary: binding.primary = shortcut
            case .alternate: binding.alternate = shortcut
            }
            settings.commandBindings[command] = binding
        }
    }

    private func setDigitModifiers(
        _ modifiers: IOSKeyboardModifiers?,
        isSessionGroup: Bool,
        variant: IOSKeyboardBindingIdentifier.Variant
    ) {
        let identifier: IOSKeyboardBindingIdentifier = isSessionGroup
            ? .sessionDigits(variant) : .engineDigits(variant)
        if let modifiers,
           let issue = IOSKeyboardShortcutValidator.validateDigitModifiers(
               modifiers,
               replacing: identifier,
               settings: environment.iosHardwareKeyboardSettings,
               actions: environment.customActions,
               engines: environment.services
           ) {
            validationMessage = issue.localizedDescription
            return
        }
        environment.updateHardwareKeyboardSettings { settings in
            if isSessionGroup {
                switch variant {
                case .primary: settings.sessionDigitModifiers.primary = modifiers
                case .alternate: settings.sessionDigitModifiers.alternate = modifiers
                }
            } else {
                switch variant {
                case .primary: settings.engineDigitModifiers.primary = modifiers
                case .alternate: settings.engineDigitModifiers.alternate = modifiers
                }
            }
        }
    }

    private func setActionShortcut(_ shortcut: IOSKeyboardShortcut?, actionID: UUID) {
        guard validate(shortcut, replacing: .action(actionID)) else { return }
        environment.updateHardwareKeyboardSettings { settings in
            settings.actionBindings[actionID] = IOSKeyboardShortcutOverride(shortcut)
        }
    }

    private func setEngineShortcut(_ shortcut: IOSKeyboardShortcut?, engineID: UUID) {
        guard validate(shortcut, replacing: .engine(engineID)) else { return }
        environment.updateHardwareKeyboardSettings { settings in
            settings.engineBindings[engineID] = IOSKeyboardShortcutOverride(shortcut)
        }
    }

    private func validate(
        _ shortcut: IOSKeyboardShortcut?,
        replacing identifier: IOSKeyboardBindingIdentifier
    ) -> Bool {
        guard let shortcut else { return true }
        if let issue = IOSKeyboardShortcutValidator.validate(
            shortcut,
            replacing: identifier,
            settings: environment.iosHardwareKeyboardSettings,
            actions: environment.customActions,
            engines: environment.services
        ) {
            validationMessage = issue.localizedDescription
            return false
        }
        return true
    }
}

private struct ShortcutRecorderButton: View {
    let recorderID: String
    let shortcut: IOSKeyboardShortcut?
    var displayText: String?
    @Binding var activeRecorderID: String?
    let onChange: (IOSKeyboardShortcut?) -> Void

    init(
        recorderID: String,
        shortcut: IOSKeyboardShortcut?,
        displayText: String? = nil,
        activeRecorderID: Binding<String?>,
        onChange: @escaping (IOSKeyboardShortcut?) -> Void
    ) {
        self.recorderID = recorderID
        self.shortcut = shortcut
        self.displayText = displayText
        _activeRecorderID = activeRecorderID
        self.onChange = onChange
    }

    private var isRecording: Bool { activeRecorderID == recorderID }

    private var formattedShortcut: String {
        if let displayText {
            return displayText
        }
        if let shortcut {
            return IOSKeyboardShortcutFormatter.string(for: shortcut)
        }
        return "Not Set"
    }

    var body: some View {
        Button {
            activeRecorderID = isRecording ? nil : recorderID
        } label: {
            Text(
                isRecording
                    ? "Press Shortcut…"
                    : formattedShortcut
            )
            .font(.callout.monospaced())
            .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if isRecording {
                UIKitKeyPressCapture { result in
                    switch result {
                    case .cancel:
                        break
                    case .clear:
                        onChange(nil)
                    case .shortcut(let shortcut):
                        onChange(shortcut)
                    }
                    activeRecorderID = nil
                }
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(recorderID) shortcut")
        .accessibilityValue(formattedShortcut)
    }
}

private enum UIKitKeyCaptureResult {
    case cancel
    case clear
    case shortcut(IOSKeyboardShortcut)
}

private struct UIKitKeyPressCapture: UIViewRepresentable {
    let onResult: (UIKitKeyCaptureResult) -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onResult = onResult
        view.requestsFirstResponder = true
        return view
    }

    func updateUIView(_ uiView: KeyCaptureView, context: Context) {
        uiView.onResult = onResult
        uiView.requestsFirstResponder = true
        uiView.activateIfPossible()
    }

    static func dismantleUIView(_ uiView: KeyCaptureView, coordinator: Void) {
        uiView.requestsFirstResponder = false
        uiView.resignFirstResponder()
    }

    @MainActor
    final class KeyCaptureView: UIView {
        var onResult: ((UIKitKeyCaptureResult) -> Void)?
        var requestsFirstResponder = false

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            activateIfPossible()
        }

        func activateIfPossible() {
            guard requestsFirstResponder, window != nil, !isFirstResponder else { return }
            becomeFirstResponder()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let key = presses.compactMap(\.key).first else {
                super.pressesBegan(presses, with: event)
                return
            }
            switch key.keyCode.rawValue {
            case 0x29: // UIKeyboardHIDUsageKeyboardEscape
                onResult?(.cancel)
            case 0x2A, 0x4C: // Backspace or forward delete
                onResult?(.clear)
            default:
                let input = Self.usCharacter(forHID: Int(key.keyCode.rawValue)) ?? key.charactersIgnoringModifiers
                guard !input.isEmpty else { return }
                let shortcut = IOSKeyboardShortcutValidator.normalize(
                    IOSKeyboardShortcut(
                        input,
                        modifiers: IOSKeyboardModifiers(key.modifierFlags)
                    )
                )
                onResult?(.shortcut(shortcut))
            }
        }

        private static func usCharacter(forHID hid: Int) -> String? {
            switch hid {
            case 0x04: return "a"
            case 0x05: return "b"
            case 0x06: return "c"
            case 0x07: return "d"
            case 0x08: return "e"
            case 0x09: return "f"
            case 0x0A: return "g"
            case 0x0B: return "h"
            case 0x0C: return "i"
            case 0x0D: return "j"
            case 0x0E: return "k"
            case 0x0F: return "l"
            case 0x10: return "m"
            case 0x11: return "n"
            case 0x12: return "o"
            case 0x13: return "p"
            case 0x14: return "q"
            case 0x15: return "r"
            case 0x16: return "s"
            case 0x17: return "t"
            case 0x18: return "u"
            case 0x19: return "v"
            case 0x1A: return "w"
            case 0x1B: return "x"
            case 0x1C: return "y"
            case 0x1D: return "z"
            case 0x1E: return "1"
            case 0x1F: return "2"
            case 0x20: return "3"
            case 0x21: return "4"
            case 0x22: return "5"
            case 0x23: return "6"
            case 0x24: return "7"
            case 0x25: return "8"
            case 0x26: return "9"
            case 0x27: return "0"
            case 0x2C: return " "
            case 0x2D: return "-"
            case 0x2E: return "="
            case 0x2F: return "["
            case 0x30: return "]"
            case 0x31: return "\\"
            case 0x33: return ";"
            case 0x34: return "'"
            case 0x35: return "`"
            case 0x36: return ","
            case 0x37: return "."
            case 0x38: return "/"
            default: return nil
            }
        }
    }
}

enum IOSKeyboardShortcutFormatter {
    static func string(for shortcut: IOSKeyboardShortcut) -> String {
        modifierString(shortcut.modifiers) + keyString(shortcut.input)
    }

    static func modifierString(_ modifiers: IOSKeyboardModifiers) -> String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value
    }

    private static func keyString(_ input: String) -> String {
        switch input {
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        case " ": "Space"
        case "\t": "Tab"
        default: input.uppercased()
        }
    }
}

private extension IOSKeyboardModifiers {
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.alternate) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}
