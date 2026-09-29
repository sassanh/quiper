import Foundation
import Testing
@testable import Quiper

/// Covers the pure parts of the download destination gate: how a file is
/// named, where a regular engine's folder is, that a locked secure engine
/// blocks the download instead of falling back to the user's folder, and that
/// a replacement settles without losing the file it replaced.
@MainActor
struct DownloadDestinationTests {

    @Test func resolvedFilename_PrefersTheSuggestedName() {
        let filename = DownloadDestination.resolvedFilename(
            suggested: "report.pdf",
            responseURL: URL(string: "https://example.com/ignored.pdf")
        )
        #expect(filename == "report.pdf")
    }

    @Test func resolvedFilename_FallsBackToResponseURLThenDownload() {
        let fromResponse = DownloadDestination.resolvedFilename(
            suggested: "",
            responseURL: URL(string: "https://example.com/archive/data.bin")
        )
        #expect(fromResponse == "data.bin")

        let fromNothing = DownloadDestination.resolvedFilename(suggested: "", responseURL: nil)
        #expect(fromNothing == "download")
    }

    @Test func uniqueDestination_KeepsFreeNamesAndSuffixesCollisions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-download-destination-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let free = DownloadDestination.uniqueDestination(in: directory, filename: "report.pdf")
        #expect(free == directory.appendingPathComponent("report.pdf"))

        try Data("already here".utf8).write(to: free)
        let colliding = DownloadDestination.uniqueDestination(in: directory, filename: "report.pdf")
        #expect(colliding != free)
        #expect(colliding.lastPathComponent.hasPrefix("report-"))
        #expect(colliding.pathExtension == "pdf")
        #expect(!FileManager.default.fileExists(atPath: colliding.path))
    }

    @Test func finishReplacement_LandsTheStagedFileAndDropsTheReplacedOne() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-download-replacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("report.pdf")
        let stagingFile = directory.appendingPathComponent(".report.pdf.quiper-staged-test")
        try Data("old".utf8).write(to: destination)
        try Data("new".utf8).write(to: stagingFile)
        let replacing = DownloadDestination.ResolvedDestination(destination: destination, stagingFile: stagingFile)

        DownloadDestination.finishReplacement(replacing, window: nil)

        #expect(try Data(contentsOf: destination) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: stagingFile.path))

        // A download that never displaced a file has nothing to settle.
        let untouched = directory.appendingPathComponent("plain.bin")
        try Data("plain".utf8).write(to: untouched)
        DownloadDestination.finishReplacement(
            DownloadDestination.ResolvedDestination(destination: untouched, stagingFile: untouched),
            window: nil
        )
        #expect(try Data(contentsOf: untouched) == Data("plain".utf8))
    }

    @Test func abandonReplacement_KeepsTheReplacedFileAndDropsTheStagedOne() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-download-abandoned-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("report.pdf")
        let stagingFile = directory.appendingPathComponent(".report.pdf.quiper-staged-test")
        try Data("old".utf8).write(to: destination)
        try Data("partial".utf8).write(to: stagingFile)

        DownloadDestination.abandonReplacement(
            DownloadDestination.ResolvedDestination(destination: destination, stagingFile: stagingFile)
        )

        #expect(try Data(contentsOf: destination) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: stagingFile.path))

        // A download that never displaced a file keeps whatever it wrote.
        let plain = directory.appendingPathComponent("plain.bin")
        try Data("partial".utf8).write(to: plain)
        DownloadDestination.abandonReplacement(
            DownloadDestination.ResolvedDestination(destination: plain, stagingFile: plain)
        )
        #expect(try Data(contentsOf: plain) == Data("partial".utf8))
    }

    @Test func prepareDirectory_LockedSecureEngineBlocksTheDownload() {
        let lockedEngine = Service(
            name: "Locked Engine",
            url: "https://locked.example",
            focus_selector: "",
            isEncrypted: true
        )

        let result = DownloadDestination.prepareDirectory(for: lockedEngine)

        guard case .failure(let blocked) = result else {
            Issue.record("A locked engine must block the download")
            return
        }
        #expect(blocked.title == "Engine Storage is Locked")
        #expect(blocked.message.contains("Locked Engine"))
    }

    @Test func prepareDirectory_RegularEngineUsesTheUserDownloadsFolder() throws {
        let engine = Service(name: "Plain Engine", url: "https://plain.example", focus_selector: "")

        let directory = try DownloadDestination.prepareDirectory(for: engine).get()

        #expect(directory.path.hasSuffix("/Downloads"))
        #expect(directory.path.contains(NSHomeDirectory()))
    }

    @Test func secureStorageDownloadsDirectory_LivesInsideTheMountPoint() {
        let engineID = UUID()

        let directory = DownloadDestination.secureStorageDownloadsDirectory(for: engineID)

        #expect(directory.lastPathComponent == "Downloads")
        #expect(directory.path.contains("WebsiteDataStore/\(engineID.uuidString)"))
    }

    @Test func canOpenDownloadsFolder_LocksWithTheEngineStorage() {
        #expect(!DownloadDestination.canOpenDownloadsFolder(for: nil))

        let plain = Service(name: "Plain Engine", url: "https://plain.example", focus_selector: "")
        #expect(DownloadDestination.canOpenDownloadsFolder(for: plain))

        let secured = Service(
            name: "Secured Engine",
            url: "https://secured.example",
            focus_selector: "",
            isEncrypted: true
        )
        defer { EncryptedVolumeManager.shared.markLocked(secured.id) }

        #expect(!DownloadDestination.canOpenDownloadsFolder(for: secured))

        EncryptedVolumeManager.shared.markUnlocked(secured.id)
        #expect(DownloadDestination.canOpenDownloadsFolder(for: secured))
    }

    @Test func askWhereToSaveDownloads_RoundTripsThroughTheSettingsFile() throws {
        let settings = Settings.shared
        let original = settings.askWhereToSaveDownloads
        defer { settings.askWhereToSaveDownloads = original }

        settings.askWhereToSaveDownloads = false
        #expect(settings.makePersistedSettings().askWhereToSaveDownloads == false)

        settings.askWhereToSaveDownloads = true
        let persisted = settings.makePersistedSettings()
        #expect(persisted.askWhereToSaveDownloads == true)

        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.askWhereToSaveDownloads == true)
    }

    /// Pins the decode half of the upgrade path: a settings file written
    /// before the setting existed carries no value for it. `Settings` applies
    /// the missing value as off when it loads (see `applyPersistedSettings`).
    @Test func askWhereToSaveDownloads_OldSettingsFilesDecodeWithoutTheKey() throws {
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: Data("{}".utf8))
        #expect(decoded.askWhereToSaveDownloads == nil)
    }
}
