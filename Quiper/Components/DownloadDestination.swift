import AppKit
import WebKit

/// The one place that decides where a download started inside an engine is
/// written. Every download goes through `resolve(...)`: it picks the engine's
/// folder — a Downloads folder inside the mounted secure storage for secured
/// engines, the user's Downloads folder otherwise — creates that folder, and
/// either hands the destination straight to WebKit or, when the user asked to
/// choose, opens the macOS save panel there with a shortcut back to the
/// secure storage. A locked storage blocks the download instead of falling
/// back to a folder outside it. A save that replaces an existing file writes
/// through a hidden stand-in, so the replaced file keeps working until the
/// new content has landed.
@MainActor
enum DownloadDestination {

    /// Why a download was stopped before any file was written. Carries the
    /// exact words shown to the user, so the reason and the alert stay in sync.
    struct BlockedDownload: Error {
        let title: String
        let message: String
    }

    /// Where a download writes: the path the user or the engine's folder
    /// chose, plus the file WebKit is actually handed — the same path unless
    /// the destination is occupied, in which case a hidden stand-in takes the
    /// writes and the replaced file stays untouched until the download
    /// settles.
    struct ResolvedDestination {
        let destination: URL
        let stagingFile: URL
        /// Whether `destination` holds a file this download is to take the
        /// place of.
        var replacesExisting: Bool { stagingFile != destination }
    }

    /// Entry point for every download: resolves the engine's folder, then
    /// either reports where to write — and what may be replaced — or explains
    /// why the download stopped.
    static func resolve(
        service: Service?,
        suggestedFilename: String,
        responseURL: URL?,
        window: NSWindow?,
        completion: @escaping (ResolvedDestination?) -> Void
    ) {
        let filename = resolvedFilename(suggested: suggestedFilename, responseURL: responseURL)
        switch prepareDirectory(for: service) {
        case .failure(let blocked):
            presentBlockedDownload(blocked, window: window)
            completion(nil)
        case .success(let directory):
            guard Settings.shared.askWhereToSaveDownloads else {
                let destination = uniqueDestination(in: directory, filename: filename)
                completion(ResolvedDestination(destination: destination, stagingFile: destination))
                return
            }
            presentSavePanel(
                suggestedFilename: filename,
                defaultDirectory: directory,
                secureStorageDirectory: secureStorageDirectory(for: service),
                window: window,
                completion: completion
            )
        }
    }

    /// The folder this engine's downloads go to, created when missing.
    /// Secured engines resolve to a Downloads folder inside their mounted
    /// storage and never fall back to the user's folder — a locked storage
    /// blocks the download instead.
    static func prepareDirectory(for service: Service?) -> Result<URL, BlockedDownload> {
        let directory: URL
        if let service, service.isEncrypted {
            guard EncryptedVolumeManager.shared.isUnlocked(for: service.id) else {
                return .failure(BlockedDownload(
                    title: "Engine Storage is Locked",
                    message: "Unlock “\(service.name)” and start the download again to save inside its storage."
                ))
            }
            directory = secureStorageDownloadsDirectory(for: service.id)
        } else {
            directory = userDownloadsDirectory()
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(BlockedDownload(
                title: "Couldn't Create the Download Folder",
                message: "“\(directory.path)” is unavailable: \(error.localizedDescription) Check the folder, then try again."
            ))
        }
        return .success(directory)
    }

    /// Downloads folder inside the engine's mounted secure storage.
    static func secureStorageDownloadsDirectory(for serviceID: UUID) -> URL {
        EncryptedVolumeManager.shared
            .getMountPointURL(for: serviceID)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    /// The name the file gets unless the user renames it in the save panel.
    static func resolvedFilename(suggested: String, responseURL: URL?) -> String {
        if !suggested.isEmpty {
            return suggested
        }
        if let lastPathComponent = responseURL?.lastPathComponent, !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return "download"
    }

    /// WebKit refuses to write onto an existing file, so a silent save takes a
    /// free name instead of failing the second time a page sends the same file.
    /// The suffix lands before the extension so the renamed copy keeps its
    /// file type.
    static func uniqueDestination(in directory: URL, filename: String) -> URL {
        let destination = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return destination
        }
        let originalName = URL(fileURLWithPath: filename)
        let stem = originalName.deletingPathExtension().lastPathComponent
        let fileExtension = originalName.pathExtension
        func availableName(suffix: String) -> URL {
            let uniqueName = fileExtension.isEmpty
                ? "\(stem)-\(suffix)"
                : "\(stem)-\(suffix).\(fileExtension)"
            return directory.appendingPathComponent(uniqueName)
        }
        let shortNamed = availableName(suffix: String(UUID().uuidString.prefix(4)))
        guard FileManager.default.fileExists(atPath: shortNamed.path) else {
            return shortNamed
        }
        return availableName(suffix: UUID().uuidString)
    }

    // MARK: - Save panel

    private static func secureStorageDirectory(for service: Service?) -> URL? {
        guard let service, service.isEncrypted else { return nil }
        return secureStorageDownloadsDirectory(for: service.id)
    }

    /// Presents the standard macOS save panel, opened at the engine's default
    /// folder and, for secured engines, carrying a shortcut back to it.
    /// AppKit accepts a panel location only while the panel is being
    /// configured — a location assigned after it opens is ignored — so the
    /// shortcut relocates by reopening: it cancels this panel and a fresh one
    /// opens at the secure folder with the typed name, while the download
    /// keeps waiting for the outcome.
    private static func presentSavePanel(
        suggestedFilename: String,
        defaultDirectory: URL,
        secureStorageDirectory: URL?,
        window: NSWindow?,
        completion: @escaping (ResolvedDestination?) -> Void
    ) {
        func present(filename: String, at directory: URL) {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.directoryURL = directory
            panel.nameFieldStringValue = filename
            var relocationDirectory: URL?
            if let secureStorageDirectory {
                panel.accessoryView = secureStorageShortcut { [weak panel] in
                    guard let panel else { return }
                    relocationDirectory = secureStorageDirectory
                    panel.cancel(nil)
                }
            }
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if let relocationDirectory {
                    present(filename: panel.nameFieldStringValue, at: relocationDirectory)
                    return
                }
                guard response == .OK, let url = panel.url else {
                    completion(nil)
                    return
                }
                // WebKit refuses destinations that already exist, and the
                // file being replaced has to outlive a download that never
                // lands: an occupied destination gets a hidden stand-in to
                // write through, swapped in only once the download succeeds.
                let staging = FileManager.default.fileExists(atPath: url.path)
                    ? stagingFile(for: url)
                    : url
                completion(ResolvedDestination(destination: url, stagingFile: staging))
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: handle)
            } else {
                panel.begin(completionHandler: handle)
            }
        }
        present(filename: suggestedFilename, at: defaultDirectory)
    }

    /// The hidden file a confirmed replacement writes through, beside the file
    /// it replaces so both live on the same volume.
    private static func stagingFile(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).quiper-staged-\(UUID().uuidString.prefix(4))")
    }

    /// The download landed: the staged content takes the place of the file it
    /// replaced, and the replaced file is gone for good. Downloads that never
    /// displaced anything have nothing to settle.
    static func finishReplacement(_ resolved: ResolvedDestination, window: NSWindow?) {
        guard resolved.replacesExisting else { return }
        if FileManager.default.fileExists(atPath: resolved.destination.path) {
            // One step swaps the replaced file with the staged content, even
            // while another app still has the old file open.
            _ = try? FileManager.default.replaceItemAt(resolved.destination, withItemAt: resolved.stagingFile)
        }
        if !FileManager.default.fileExists(atPath: resolved.stagingFile.path) {
            return
        }
        // The replaced file is gone or unswappable; move the staged content
        // in directly.
        try? FileManager.default.removeItem(at: resolved.destination)
        try? FileManager.default.moveItem(at: resolved.stagingFile, to: resolved.destination)
        guard FileManager.default.fileExists(atPath: resolved.stagingFile.path) else { return }
        presentBlockedDownload(
            BlockedDownload(
                title: "Couldn't Replace the File",
                message: "“\(resolved.destination.path)” couldn't take the new file. The finished download is at “\(resolved.stagingFile.path)”."
            ),
            window: window
        )
    }

    /// The download failed: the staged file goes away and the file it was to
    /// replace never moved, so nothing was lost. Quiper never resumes a
    /// download, so a failure is final.
    static func abandonReplacement(_ resolved: ResolvedDestination) {
        guard resolved.replacesExisting else { return }
        try? FileManager.default.removeItem(at: resolved.stagingFile)
    }

    /// Left-aligned shortcut inside Quiper's save panel that jumps back to the
    /// engine's secure storage. It exists only in this panel — the global
    /// Finder sidebar is never touched.
    private static func secureStorageShortcut(onJump: @escaping () -> Void) -> NSView {
        let button = SecureStorageShortcutButton(onJump: onJump)
        button.sizeToFit()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 34))
        container.autoresizingMask = [.width]
        button.frame.origin = NSPoint(x: 4, y: (container.frame.height - button.frame.height) / 2)
        container.addSubview(button)
        return container
    }

    /// Stops a download with the words the user needs to act on.
    private static func presentBlockedDownload(_ blocked: BlockedDownload, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = blocked.title
        alert.informativeText = blocked.message
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func userDownloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}

/// The save panel's secure storage shortcut. AppKit ignores location changes
/// on an open panel, so the button hands the jump back to the panel's
/// presentation code, which reopens the panel at the secure folder.
private final class SecureStorageShortcutButton: NSButton {
    private let onJump: () -> Void

    init(onJump: @escaping () -> Void) {
        self.onJump = onJump
        super.init(frame: .zero)
        title = "Secure Storage"
        image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Storage")
        imagePosition = .imageLeading
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .medium)
        toolTip = "Save inside this engine's secure storage"
        target = self
        action = #selector(jumpToSecureStorage)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func jumpToSecureStorage() {
        onJump()
    }
}
