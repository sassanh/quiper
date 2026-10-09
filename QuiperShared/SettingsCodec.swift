import Foundation

/// The pure settings codec: the encoder, the decoder, and the single
/// compat path every reader of `settings.json` goes through. No file I/O,
/// no app coupling — the app's persistence gate and the resident link
/// helper both decode through here, so a format change lands in one place.
enum SettingsCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // 1. Try Double (deferredToDate: timeIntervalSinceReferenceDate)
            if let doubleValue = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: doubleValue)
            }
            // 2. Try Int (also reference date, for old files writing 806344477)
            if let intValue = try? container.decode(Int.self) {
                return Date(timeIntervalSinceReferenceDate: Double(intValue))
            }
            // 3. Try ISO8601 string (current encoder: .iso8601 -> "2026-08-29T16:34:36Z")
            if let stringValue = try? container.decode(String.self) {
                // With fractional seconds
                let isoWithFractional = ISO8601DateFormatter()
                isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoWithFractional.date(from: stringValue) {
                    return date
                }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: stringValue) {
                    return date
                }
                // Fallback: try default ISO8601 without explicit options (handles Z)
                let isoDefault = ISO8601DateFormatter()
                if let date = isoDefault.date(from: stringValue) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode Date: expected Double, Int, or ISO8601 string")
        }
        return decoder
    }

    static func encode(_ persisted: PersistedSettings) throws -> Data {
        try makeEncoder().encode(persisted)
    }

    static func decode(from data: Data) throws -> PersistedSettings {
        do {
            return try makeDecoder().decode(PersistedSettings.self, from: data)
        } catch let error as DecodingError {
            throw ConfigPortError.decodingFailed(error)
        }
    }

    /// Decodes a persisted settings payload, accepting the legacy `[Service]`
    /// archive shape when the current one does not fit. Nil when the data is
    /// neither shape — the reader decides what an unreadable file means.
    static func decodePersistedSettings(from data: Data) -> PersistedSettings? {
        if let payload = try? makeDecoder().decode(PersistedSettings.self, from: data) {
            return payload
        }
        // The bare `[Service]` archive predates PersistedSettings and was
        // only ever written by the macOS app, whose settings carried a
        // hotkey; iOS never produced such a file, so there the shape is
        // simply unreadable.
        #if os(macOS)
        guard let legacyServices = try? makeDecoder().decode([Service].self, from: data) else {
            return nil
        }
        return PersistedSettings(
            services: legacyServices,
            hotkey: nil,
            customActions: nil,
            updatePreferences: nil,
            serviceZoomLevels: nil
        )
        #else
        return nil
        #endif
    }
}

enum ConfigPortError: LocalizedError {
    case decodingFailed(DecodingError)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let error):
            return "Failed to read the config file: \(error.detailedDescription)"
        }
    }
}

extension DecodingError {
    var detailedDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let location = path.isEmpty ? "" : " at '\(path)'"
            return "Missing field '\(key.stringValue)'\(location)."
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Incorrect type for field '\(path)': expected \(type). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Value of type '\(type)' not found at '\(path)'."
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let location = path.isEmpty ? "" : " at '\(path)'"
            return "Data corrupted\(location): \(context.debugDescription)"
        @unknown default:
            return self.localizedDescription
        }
    }
}
