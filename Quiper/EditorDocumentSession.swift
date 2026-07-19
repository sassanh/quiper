import Combine
import Foundation

#if os(macOS)
import Darwin

@MainActor
final class EditorDocumentSession: ObservableObject {
    enum Status: Equatable {
        case saved
        case saving
        case updatedExternally
        case conflict
        case error(String)
    }

    struct Conflict: Equatable {
        fileprivate var internalText: String
        fileprivate var externalSnapshot: DiskSnapshot

        var externalText: String {
            externalSnapshot.text
        }
    }

    fileprivate enum DiskSnapshot: Equatable {
        case missing
        case text(String)

        var text: String {
            switch self {
            case .missing:
                return ""
            case .text(let value):
                return value
            }
        }
    }

    @Published private(set) var text: String
    @Published private(set) var status: Status = .saved
    @Published private(set) var conflict: Conflict?

    private let fileURL: URL?
    private var isReadOnly: Bool
    private let onAcceptedChange: (String) -> Void
    private let saveDelay: Duration
    private var baseDiskSnapshot: DiskSnapshot
    private var lastCommittedText: String
    private var monitor: EditorDirectoryMonitor?
    private var saveTask: Task<Void, Never>?
    private var fileEventTask: Task<Void, Never>?
    private var transientStatusTask: Task<Void, Never>?

    init(
        initialText: String,
        fileURL: URL?,
        isReadOnly: Bool,
        saveDelay: Duration = .milliseconds(300),
        onAcceptedChange: @escaping (String) -> Void
    ) {
        text = initialText
        self.fileURL = fileURL
        self.isReadOnly = isReadOnly
        self.saveDelay = saveDelay
        self.onAcceptedChange = onAcceptedChange
        lastCommittedText = initialText
        baseDiskSnapshot = fileURL.flatMap { try? Self.readSnapshot(at: $0) } ?? .missing
        startMonitoringIfNeeded()
    }

    func userDidEdit(_ newText: String) {
        guard !isReadOnly, newText != text else { return }
        text = newText

        if let conflict {
            self.conflict = Conflict(
                internalText: newText,
                externalSnapshot: conflict.externalSnapshot
            )
            status = .conflict
            return
        }

        transientStatusTask?.cancel()
        status = .saving
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: saveDelay)
            } catch {
                return
            }
            persistPendingText()
        }
    }

    func receiveHostText(_ newText: String) {
        guard newText != text, saveTask == nil, conflict == nil else { return }
        text = newText
        lastCommittedText = newText
    }

    func updateReadOnlyState(_ newValue: Bool, hostText: String) {
        guard newValue != isReadOnly else {
            receiveHostText(hostText)
            return
        }

        saveTask?.cancel()
        saveTask = nil
        fileEventTask?.cancel()
        fileEventTask = nil
        transientStatusTask?.cancel()
        transientStatusTask = nil
        conflict = nil
        monitor?.cancel()
        monitor = nil

        isReadOnly = newValue
        text = hostText
        lastCommittedText = hostText
        refreshBaseSnapshot()
        status = .saved
        startMonitoringIfNeeded()
    }

    func keepInternalVersion() {
        guard let conflict else { return }
        saveTask?.cancel()
        saveTask = nil
        self.conflict = nil
        text = conflict.internalText
        status = .saving
        acceptInternalText(conflict.internalText, ignoringExternalChanges: true)
    }

    func loadExternalVersion() {
        guard let conflict else { return }
        saveTask?.cancel()
        saveTask = nil
        self.conflict = nil
        acceptExternalSnapshot(conflict.externalSnapshot)
    }

    func resume() {
        startMonitoringIfNeeded()
    }

    func stop() {
        let shouldFlushPendingEdit = saveTask != nil && conflict == nil
        saveTask?.cancel()
        saveTask = nil
        if shouldFlushPendingEdit {
            acceptInternalText(text, ignoringExternalChanges: false)
        }
        fileEventTask?.cancel()
        fileEventTask = nil
        transientStatusTask?.cancel()
        transientStatusTask = nil
        monitor?.cancel()
        monitor = nil
    }

    func checkForExternalChanges() {
        guard let fileURL, !isReadOnly else { return }

        let snapshot: DiskSnapshot
        do {
            snapshot = try Self.readSnapshot(at: fileURL)
        } catch {
            status = .error("Could not read the externally edited file.")
            return
        }

        guard snapshot != baseDiskSnapshot else { return }

        if conflict != nil {
            self.conflict = Conflict(
                internalText: text,
                externalSnapshot: snapshot
            )
            status = .conflict
            return
        }

        if saveTask != nil || text != lastCommittedText {
            saveTask?.cancel()
            saveTask = nil
            conflict = Conflict(internalText: text, externalSnapshot: snapshot)
            status = .conflict
            return
        }

        acceptExternalSnapshot(snapshot)
    }

    private func persistPendingText() {
        saveTask = nil
        guard !isReadOnly, conflict == nil else { return }
        acceptInternalText(text, ignoringExternalChanges: false)
    }

    private func acceptInternalText(_ value: String, ignoringExternalChanges: Bool) {
        if let fileURL, !ignoringExternalChanges {
            do {
                let currentSnapshot = try Self.readSnapshot(at: fileURL)
                guard currentSnapshot == baseDiskSnapshot else {
                    conflict = Conflict(internalText: value, externalSnapshot: currentSnapshot)
                    status = .conflict
                    return
                }
            } catch {
                status = .error("Could not verify the externally edited file.")
                return
            }
        }

        onAcceptedChange(value)
        lastCommittedText = value
        refreshBaseSnapshot()
        status = .saved
    }

    private func acceptExternalSnapshot(_ snapshot: DiskSnapshot) {
        baseDiskSnapshot = snapshot
        text = snapshot.text
        lastCommittedText = snapshot.text
        onAcceptedChange(snapshot.text)
        refreshBaseSnapshot()
        showTransientExternalUpdateStatus()
    }

    private func refreshBaseSnapshot() {
        guard let fileURL else {
            baseDiskSnapshot = .missing
            return
        }

        if let snapshot = try? Self.readSnapshot(at: fileURL) {
            baseDiskSnapshot = snapshot
        }
    }

    private func showTransientExternalUpdateStatus() {
        transientStatusTask?.cancel()
        status = .updatedExternally
        transientStatusTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self, conflict == nil, saveTask == nil else { return }
            status = .saved
        }
    }

    private func startMonitoringIfNeeded() {
        guard monitor == nil, let fileURL, !isReadOnly else { return }
        monitor = EditorDirectoryMonitor(directoryURL: fileURL.deletingLastPathComponent()) { [weak self] in
            self?.scheduleExternalChangeCheck()
        }
    }

    private func scheduleExternalChangeCheck() {
        fileEventTask?.cancel()
        fileEventTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let self else { return }
            fileEventTask = nil
            checkForExternalChanges()
        }
    }

    private static func readSnapshot(at url: URL) throws -> DiskSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return .text(text)
    }
}

@MainActor
private final class EditorDirectoryMonitor {
    private let directoryURL: URL
    private let eventHandler: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(directoryURL: URL, eventHandler: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.eventHandler = eventHandler
        start()
    }

    deinit {
        source?.cancel()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }

    private func start() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.eventHandler()
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        self.source = source
        source.resume()
    }
}
#endif
