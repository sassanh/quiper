import Combine
import Foundation

/// iOS counterpart to the macOS `EditorDocumentSession`, mapping its
/// document/debounced-save/read-only contract to in-memory storage.
///
/// The macOS session mediates between a SwiftUI binding and an on-disk file
/// (directory monitoring, external-change conflicts). iOS edits live only in
/// memory, so this session keeps the same `userDidEdit`/`receiveHostText`/
/// `updateReadOnlyState`/`resume`/`stop` surface while dropping the file
/// machinery: edits are debounced and committed to the host through
/// `onAcceptedChange`, and `stop()` flushes any pending edit.
@MainActor
final class CodeEditorSession: ObservableObject {
    enum Status: Equatable {
        case saved
        case saving
    }

    @Published private(set) var text: String
    @Published private(set) var status: Status = .saved

    private var isReadOnly: Bool
    private let onAcceptedChange: (String) -> Void
    private let saveDelay: Duration
    private var saveTask: Task<Void, Never>?

    init(
        initialText: String,
        isReadOnly: Bool,
        saveDelay: Duration = .milliseconds(300),
        onAcceptedChange: @escaping (String) -> Void
    ) {
        text = initialText
        self.isReadOnly = isReadOnly
        self.saveDelay = saveDelay
        self.onAcceptedChange = onAcceptedChange
    }

    func userDidEdit(_ newText: String) {
        guard !isReadOnly, newText != text else { return }
        text = newText

        saveTask?.cancel()
        status = .saving
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: saveDelay)
            } catch {
                return
            }
            commitPendingText()
        }
    }

    func receiveHostText(_ newText: String) {
        guard newText != text, saveTask == nil else { return }
        text = newText
    }

    func updateReadOnlyState(_ newValue: Bool, hostText: String) {
        guard newValue != isReadOnly else {
            receiveHostText(hostText)
            return
        }

        saveTask?.cancel()
        saveTask = nil

        isReadOnly = newValue
        text = hostText
        status = .saved
    }

    func resume() {}

    func stop() {
        let shouldFlushPendingEdit = saveTask != nil
        saveTask?.cancel()
        saveTask = nil
        if shouldFlushPendingEdit {
            onAcceptedChange(text)
        }
        status = .saved
    }

    private func commitPendingText() {
        saveTask = nil
        guard !isReadOnly else { return }
        onAcceptedChange(text)
        status = .saved
    }
}
