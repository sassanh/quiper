import Foundation

/// One element in the picked ancestor chain, ordered root-first. The picker
/// JavaScript (`WebScripts.makeSelectorPickerStartScript`) precomputes each
/// `segment` against the live DOM, preferring stable hooks (test attributes,
/// stable ids, meaningful classes) and using position only as a last resort.
/// Swift never builds segments: joining them into prefix candidates is the
/// only selector construction here.
struct SelectorElementDescriptor: Equatable {
    var tag: String
    var segment: String

    init(tag: String, segment: String) {
        self.tag = tag
        self.segment = segment
    }

    init?(dictionary: [String: Any]) {
        guard let tag = dictionary["tag"] as? String,
              let segment = dictionary["segment"] as? String,
              !segment.isEmpty
        else { return nil }
        self.tag = tag
        self.segment = segment
    }
}

enum SelectorSuggest {
    /// Builds candidate selectors from a root-first path. Structural ancestors
    /// (`html`, `head`, `body`) are dropped: they would only ever highlight
    /// the whole page, so the slider starts at the first meaningful element.
    /// Index 0 selects that ancestor, and each deeper index selects one level
    /// further down, so the last index selects the picked leaf with the full
    /// anchored path. The leaf itself is always kept, even when it is `body`.
    /// Empty paths yield no candidates.
    static func candidates(for path: [SelectorElementDescriptor]) -> [String] {
        guard !path.isEmpty else { return [] }
        var trimmed = path
        let structural = ["html", "head", "body"]
        while trimmed.count > 1, structural.contains(trimmed[0].tag.lowercased()) {
            trimmed.removeFirst()
        }
        let segments = trimmed.map(\.segment)
        return (0..<segments.count).map { depth in
            segments[...depth].joined(separator: " > ")
        }
    }

    /// CSS rule hiding everything the selector matches.
    static func hideRule(for selector: String) -> String {
        "\(selector) { display: none !important; }"
    }
}
