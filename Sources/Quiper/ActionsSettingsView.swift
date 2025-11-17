import SwiftUI
import AppKit
import Carbon

struct ActionsSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var recordingActionID: UUID?
    @State private var captureMessage: String = "Waiting for key press…"
    @State private var captureSession: ShortcutCaptureSession?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                List {
                    ForEach($settings.customActions) { $action in
                        ActionRow(action: $action, onRecord: { recordShortcut(for: action.id) }, onClear: { clearShortcut(for: action.id) })
                    }
                    .onDelete(perform: removeActions)
                }
                HStack {
                    Button(action: addAction) {
                        Label("Add Action", systemImage: "plus")
                    }
                    Spacer()
                }
            }
            if recordingActionID != nil {
                ShortcutCaptureOverlayView(message: captureMessage, onCancel: cancelCapture)
            }
        }
        .padding()
        .onChange(of: settings.customActions) { _ in
            settings.saveSettings()
        }
    }

    private func addAction() {
        settings.customActions.append(CustomAction(name: "New Action"))
    }

    private func removeActions(at offsets: IndexSet) {
        settings.customActions.remove(atOffsets: offsets)
    }

    private func recordShortcut(for id: UUID) {
        recordingActionID = id
        captureMessage = "Waiting for key press…"
        captureSession = ShortcutCaptureSession(onUpdate: { text in
            captureMessage = text
        }, completion: { configuration in
            if let configuration, let index = settings.customActions.firstIndex(where: { $0.id == id }) {
                settings.customActions[index].shortcut = configuration
            }
            recordingActionID = nil
            captureSession = nil
        })
    }

    private func clearShortcut(for id: UUID) {
        if let index = settings.customActions.firstIndex(where: { $0.id == id }) {
            settings.customActions[index].shortcut = nil
        }
    }

    private func cancelCapture() {
        captureSession?.cancel()
    }
}

private struct ActionRow: View {
    @Binding var action: CustomAction
    var onRecord: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Action name", text: $action.name)
            Spacer()
            Button(action: onRecord) {
                Text(action.shortcut.map { ShortcutFormatter.string(for: $0) } ?? "Record Shortcut")
                    .font(.system(.body, design: .monospaced))
            }
            Button(action: onClear) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Clear shortcut")
        }
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
