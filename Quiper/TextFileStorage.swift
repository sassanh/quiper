import Foundation

enum TextFileStorage {
    static func save(_ text: String, to url: URL) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        let data = Data(text.utf8)
        if let existingData = try? Data(contentsOf: url), existingData == data {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
