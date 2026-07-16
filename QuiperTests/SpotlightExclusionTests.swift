import XCTest
@testable import Quiper

final class SpotlightExclusionTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotlightExclusionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testEnsureExcluded_ForDirectory_SetsBackupExclusionAndMarker() throws {
        let directory = tempDirectory.appendingPathComponent("EncryptedStores", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertFalse(SpotlightExclusion.isExcluded(at: directory))
        XCTAssertTrue(SpotlightExclusion.ensureExcluded(at: directory))
        XCTAssertTrue(SpotlightExclusion.isExcluded(at: directory))

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        let markerURL = directory.appendingPathComponent(".metadata_never_index", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testEnsureExcluded_WhenAlreadyExcluded_IsIdempotent() throws {
        let directory = tempDirectory.appendingPathComponent("EngineStore", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertTrue(SpotlightExclusion.ensureExcluded(at: directory))
        XCTAssertTrue(SpotlightExclusion.ensureExcluded(at: directory))
        XCTAssertTrue(SpotlightExclusion.isExcluded(at: directory))
    }

    func testEnsureExcluded_ForMissingPath_ReturnsFalse() {
        let missingURL = tempDirectory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertFalse(SpotlightExclusion.ensureExcluded(at: missingURL))
    }
}