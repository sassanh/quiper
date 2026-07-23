import Foundation

/// The shared ordering used for Quiper app versions, persisted settings versions,
/// and GitHub release tags.
struct QuiperVersion: Sendable {
    private let numericComponents: [Int]
    private let suffixIdentifier: String?
    private let buildNumber: Int?

    init?(_ rawValue: String, buildNumber explicitBuildNumber: Int? = nil) {
        guard let numericVersion = Self.numericVersion(in: rawValue) else {
            return nil
        }

        let surroundingVersion = Self.surroundingVersion(
            in: rawValue,
            numericRange: numericVersion.range
        )

        numericComponents = numericVersion.components
        suffixIdentifier = surroundingVersion.suffixIdentifier
        buildNumber = explicitBuildNumber ?? surroundingVersion.buildNumber
    }

    func compare(to other: QuiperVersion) -> ComparisonResult? {
        let componentCount = max(numericComponents.count, other.numericComponents.count)
        for index in 0..<componentCount {
            let component = index < numericComponents.count ? numericComponents[index] : 0
            let otherComponent =
                index < other.numericComponents.count ? other.numericComponents[index] : 0
            if component != otherComponent {
                return component < otherComponent ? .orderedAscending : .orderedDescending
            }
        }

        let hasSuffix = suffixIdentifier != nil
        let otherHasSuffix = other.suffixIdentifier != nil
        if hasSuffix != otherHasSuffix {
            return hasSuffix ? .orderedDescending : .orderedAscending
        }

        let buildComparison = Self.compare(buildNumber, to: other.buildNumber)
        if buildComparison != .orderedSame {
            return buildComparison
        }
        if buildNumber != nil {
            return .orderedSame
        }
        if suffixIdentifier == other.suffixIdentifier {
            return .orderedSame
        }
        return nil
    }

    static func compare(
        _ version: String,
        buildNumber: Int? = nil,
        to otherVersion: String,
        buildNumber otherBuildNumber: Int? = nil
    ) -> ComparisonResult? {
        if let parsedVersion = QuiperVersion(version, buildNumber: buildNumber),
           let parsedOtherVersion = QuiperVersion(
               otherVersion,
               buildNumber: otherBuildNumber
           ) {
            return parsedVersion.compare(to: parsedOtherVersion)
        }

        guard let buildNumber, let otherBuildNumber else {
            return nil
        }
        return compare(buildNumber, to: otherBuildNumber)
    }

    static func isAfter(
        _ version: String,
        buildNumber: Int? = nil,
        than otherVersion: String,
        buildNumber otherBuildNumber: Int? = nil
    ) -> Bool {
        compare(
            version,
            buildNumber: buildNumber,
            to: otherVersion,
            buildNumber: otherBuildNumber
        ) == .orderedDescending
    }

    static func isAtLeast(_ version: String, _ otherVersion: String) -> Bool? {
        guard let comparison = compare(version, to: otherVersion) else {
            return nil
        }
        return comparison != .orderedAscending
    }

    private static func compare(_ value: Int?, to otherValue: Int?) -> ComparisonResult {
        switch (value, otherValue) {
        case (let value?, let otherValue?):
            return compare(value, to: otherValue)
        case (.none, .some):
            return .orderedAscending
        case (.some, .none):
            return .orderedDescending
        default:
            return .orderedSame
        }
    }

    private static func compare(_ value: Int, to otherValue: Int) -> ComparisonResult {
        if value < otherValue {
            return .orderedAscending
        }
        if value > otherValue {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func numericVersion(
        in rawValue: String
    ) -> (components: [Int], range: Range<String.Index>)? {
        var index = rawValue.startIndex

        while index < rawValue.endIndex {
            guard rawValue[index].isNumber else {
                index = rawValue.index(after: index)
                continue
            }

            let candidateStart = index
            while index < rawValue.endIndex,
                  rawValue[index].isNumber || rawValue[index] == "." {
                index = rawValue.index(after: index)
            }

            let candidateRange = candidateStart..<index
            let components = rawValue[candidateRange].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard components.count >= 2,
                  components.allSatisfy({ !$0.isEmpty && Int($0) != nil }) else {
                continue
            }

            return (
                components: components.compactMap { Int($0) },
                range: candidateRange
            )
        }

        return nil
    }

    private static func surroundingVersion(
        in rawValue: String,
        numericRange: Range<String.Index>
    ) -> (suffixIdentifier: String?, buildNumber: Int?) {
        let prefix = String(rawValue[..<numericRange.lowerBound])
        var suffix = String(rawValue[numericRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parenthesizedBuildNumber = removeParenthesizedBuildNumber(from: &suffix)
        let taggedBuildNumber = removeTaggedBuildNumber(from: &suffix)

        return (
            suffixIdentifier: combinedSuffixIdentifier(prefix: prefix, suffix: suffix),
            buildNumber: parenthesizedBuildNumber ?? taggedBuildNumber
        )
    }

    private static func combinedSuffixIdentifier(prefix: String, suffix: String) -> String? {
        let prefixIdentifier = prefixSuffixIdentifier(prefix)
        let trailingIdentifier = trailingSuffixIdentifier(suffix)

        switch (prefixIdentifier, trailingIdentifier) {
        case (nil, nil):
            return nil
        case (let prefixIdentifier?, nil):
            return prefixIdentifier
        case (nil, let suffixIdentifier?):
            return suffixIdentifier
        case (let prefixIdentifier?, let suffixIdentifier?):
            return [prefixIdentifier, suffixIdentifier]
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
    }

    private static func prefixSuffixIdentifier(_ prefix: String) -> String? {
        var normalized = prefix.trimmingCharacters(in: versionSeparators)
        guard !normalized.isEmpty else {
            return nil
        }
        if normalized.lowercased() == "v" {
            return nil
        }

        if normalized.last?.lowercased() == "v" {
            let markerIndex = normalized.index(before: normalized.endIndex)
            if markerIndex > normalized.startIndex {
                let precedingIndex = normalized.index(before: markerIndex)
                if isVersionSeparator(normalized[precedingIndex]) {
                    normalized.removeSubrange(markerIndex...)
                    normalized = normalized.trimmingCharacters(in: versionSeparators)
                }
            }
        }

        guard !normalized.isEmpty else {
            return nil
        }
        return normalizedSuffixIdentifier(normalized)
    }

    private static func isVersionSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character == "-" || character == "_" || character == "."
    }

    private static func trailingSuffixIdentifier(_ suffix: String) -> String? {
        let normalized = suffix.trimmingCharacters(in: versionSeparators)
        guard !normalized.isEmpty else {
            return nil
        }
        return normalizedSuffixIdentifier(normalized)
    }

    private static func normalizedSuffixIdentifier(_ suffix: String) -> String {
        suffix.lowercased()
            .components(separatedBy: versionSeparators)
            .filter { !$0.isEmpty && $0 != "v" && $0 != "nonproduction" }
            .joined(separator: "-")
    }

    private static func removeParenthesizedBuildNumber(from suffix: inout String) -> Int? {
        guard suffix.last == ")",
              let openingParenthesis = suffix.lastIndex(of: "(") else {
            return nil
        }

        let numberStart = suffix.index(after: openingParenthesis)
        let numberEnd = suffix.index(before: suffix.endIndex)
        let numberText = suffix[numberStart..<numberEnd]
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              let buildNumber = Int(numberText) else {
            return nil
        }

        suffix.removeSubrange(openingParenthesis...)
        suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return buildNumber
    }

    private static func removeTaggedBuildNumber(from suffix: inout String) -> Int? {
        guard let separator = suffix.lastIndex(of: "-") else {
            return nil
        }

        let numberStart = suffix.index(after: separator)
        let numberText = suffix[numberStart...]
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              let buildNumber = Int(numberText) else {
            return nil
        }

        suffix.removeSubrange(separator...)
        suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return buildNumber
    }

    private static let versionSeparators = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "-_.")
    )
}
