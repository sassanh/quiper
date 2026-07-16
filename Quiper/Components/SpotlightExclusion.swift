import Foundation

enum SpotlightExclusion {
    private static let markerFileName = ".metadata_never_index"

    /// Returns whether the URL is already excluded from Spotlight indexing.
    static func isExcluded(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        if let values = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]),
           values.isExcludedFromBackup == true {
            return true
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let markerURL = url.appendingPathComponent(markerFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Ensures the URL is excluded from Spotlight indexing, applying markers only when needed.
    @discardableResult
    static func ensureExcluded(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        if isExcluded(at: url) {
            return true
        }

        return applyExclusion(at: url)
    }

    @discardableResult
    private static func applyExclusion(at url: URL) -> Bool {
        var mutableURL = url
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutableURL.setResourceValues(values)
        } catch {
            NSLog(
                "[SpotlightExclusion] Failed to set isExcludedFromBackup for %@: %@",
                url.path,
                error.localizedDescription
            )
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return true
        }

        let markerURL = url.appendingPathComponent(markerFileName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: markerURL.path) else {
            return true
        }

        guard FileManager.default.createFile(atPath: markerURL.path, contents: Data()) else {
            NSLog(
                "[SpotlightExclusion] Failed to create %@ in %@",
                markerFileName,
                url.path
            )
            return false
        }

        return true
    }
}