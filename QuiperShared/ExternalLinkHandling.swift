import Foundation

/// Where an externally delivered link opens inside its claimed engine.
enum ExternalLinkPlacement: String, Codable, CaseIterable, Identifiable {
    /// The first visible session slot without a live page.
    case newSession
    /// The session the engine showed most recently.
    case lastVisitedSession
    /// One fixed session slot, displayed 1-9/0.
    case fixedSession

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newSession: return "New Session"
        case .lastVisitedSession: return "Last Visited Session"
        case .fixedSession: return "Fixed Session"
        }
    }
}

/// Per-engine configuration for opening links that other applications hand
/// to Quiper (right-click a link → Open Link With → Quiper).
///
/// For a secure engine the configuration lives inside the engine's
/// encrypted bundle, like the rest of its metadata: while the volume is
/// locked, nothing outside it carries the claimed domains, and the engine
/// claims no links. Plain engines keep it in settings.json.
struct ExternalLinkHandler: Codable, Equatable {
    /// Whether links matching `domains` open in this engine at all.
    var isEnabled: Bool = false
    /// Domain entries as typed by the user; matching normalizes them, so
    /// bare hosts, hosts with ports, and pasted URLs all work.
    var domains: [String] = []
    /// Where a claimed link lands.
    var placement: ExternalLinkPlacement = .newSession
    /// The slot `placement` uses when it is `.fixedSession` (0-9, shown 1-9/0).
    var fixedSessionIndex: Int = ExternalLinkHandler.defaultFixedSessionIndex

    /// The slot used when the user has not picked one: the last slot,
    /// displayed 0.
    static let defaultFixedSessionIndex = SessionSlots.count - 1

    /// Whether the user set anything here. The pristine default encodes
    /// nothing, so settings.json stays free of untouched keys.
    var isConfigured: Bool {
        isEnabled || !domains.isEmpty || placement != .newSession
            || fixedSessionIndex != ExternalLinkHandler.defaultFixedSessionIndex
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, domains, placement, fixedSessionIndex
    }

    init(
        isEnabled: Bool = false,
        domains: [String] = [],
        placement: ExternalLinkPlacement = .newSession,
        fixedSessionIndex: Int = ExternalLinkHandler.defaultFixedSessionIndex
    ) {
        self.isEnabled = isEnabled
        self.domains = domains
        self.placement = placement
        self.fixedSessionIndex = fixedSessionIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeBoolIfPresent(forKey: .isEnabled) ?? false
        domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
        placement = try container.decodeIfPresent(ExternalLinkPlacement.self, forKey: .placement) ?? .newSession
        let decodedIndex = try container.decodeIfPresent(Int.self, forKey: .fixedSessionIndex)
            ?? ExternalLinkHandler.defaultFixedSessionIndex
        fixedSessionIndex = min(max(decodedIndex, 0), SessionSlots.count - 1)
    }
}

/// Matching of externally delivered URLs against per-engine domain claims.
enum ExternalLinkRouting {
    /// Reduces a user-typed entry — bare host, host:port, or a pasted URL
    /// with path and query — to a bare lowercase host.
    static func normalizedDomain(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              var domain = url.host?.lowercased(),
              !domain.contains(" ") else {
            return nil
        }
        while domain.hasPrefix("*.") {
            domain = String(domain.dropFirst(2))
        }
        if domain.hasSuffix(".") {
            domain = String(domain.dropLast())
        }
        return domain.isEmpty ? nil : domain
    }

    /// Whether `url` falls under a claimed domain: the host itself or any
    /// subdomain of it. Case-insensitive; ports, paths, and queries never
    /// take part.
    static func matches(url: URL, domain entry: String) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty,
              let domain = normalizedDomain(from: entry) else {
            return false
        }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// The first enabled engine claiming `url`, in settings order. A secure
    /// engine claims only while unlocked: its routing records live inside
    /// the encrypted bundle, so while the volume is locked the link behaves
    /// as if nothing claimed it. Every caller states its own observation of
    /// unlock state — there is no permissive default.
    static func claimedService(
        for url: URL,
        in services: [Service],
        isEngineUnlocked: (UUID) -> Bool
    ) -> Service? {
        services.first { service in
            guard !service.isEncrypted || isEngineUnlocked(service.id) else { return false }
            guard service.externalLinkHandler.isEnabled else { return false }
            return service.externalLinkHandler.domains.contains { matches(url: url, domain: $0) }
        }
    }
}

extension Service {
    /// Drops this engine's external link routing records the way a locked
    /// engine must present itself: nothing but the name. A migrated secure
    /// engine keeps its claimed domains only inside the encrypted bundle,
    /// so locking forgets them and the next unlock restores them. Legacy
    /// engines and plain engines keep theirs in settings.json, where unlock
    /// has nothing to restore them from.
    mutating func forgetRoutingRecords() {
        guard isEncrypted, hasMigratedMetadata else { return }
        externalLinkHandler = ExternalLinkHandler()
    }
}

/// Decides which session slot an externally delivered link opens in.
enum ExternalLinkSessionPlacement {
    enum Plan: Equatable {
        /// The link opens in this slot.
        case openInSession(index: Int)
        /// Every slot shows a page; the user picks which one the link takes over.
        case replaceBusySession(defaultIndex: Int)
        /// The engine has no slot that could open a link (a Pinned Tabs
        /// engine without any tab URLs).
        case noSessionAvailable
    }

    /// - Parameters:
    ///   - visibleSlots: the slots this engine exposes; Pinned Tabs engines
    ///     hide slots without a tab URL.
    ///   - occupiedSlots: the slots with a live page.
    ///   - visitOrder: visible slots from most to least recently visited,
    ///     covering every visible slot.
    static func plan(
        placement: ExternalLinkPlacement,
        fixedSessionIndex: Int,
        visibleSlots: [Int],
        occupiedSlots: Set<Int>,
        visitOrder: [Int]
    ) -> Plan {
        guard !visibleSlots.isEmpty else { return .noSessionAvailable }

        switch placement {
        case .fixedSession:
            // A fixed slot whose pinned URL was removed is no longer
            // reachable; opening a fresh session beats dropping the link.
            if visibleSlots.contains(fixedSessionIndex) {
                return .openInSession(index: fixedSessionIndex)
            }
            return firstFreeSession(
                visibleSlots: visibleSlots,
                occupiedSlots: occupiedSlots,
                visitOrder: visitOrder
            )
        case .lastVisitedSession:
            if let recent = visitOrder.first(where: { visibleSlots.contains($0) }) {
                return .openInSession(index: recent)
            }
            return .openInSession(index: visibleSlots[0])
        case .newSession:
            return firstFreeSession(
                visibleSlots: visibleSlots,
                occupiedSlots: occupiedSlots,
                visitOrder: visitOrder
            )
        }
    }

    private static func firstFreeSession(
        visibleSlots: [Int],
        occupiedSlots: Set<Int>,
        visitOrder: [Int]
    ) -> Plan {
        if let free = visibleSlots.first(where: { !occupiedSlots.contains($0) }) {
            return .openInSession(index: free)
        }
        // Quiper keeps at most 10 sessions per engine; with all of them open
        // the least recently visited one is the default to take over.
        let oldest = visitOrder.last(where: { occupiedSlots.contains($0) })
            ?? visibleSlots.last
            ?? 0
        return .replaceBusySession(defaultIndex: oldest)
    }
}
