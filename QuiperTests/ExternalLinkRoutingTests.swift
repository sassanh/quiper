import XCTest
@testable import Quiper

@MainActor
final class ExternalLinkRoutingTests: XCTestCase {
    // MARK: - Domain normalization

    func testNormalizedDomainDropsSchemePathAndQuery() {
        XCTAssertEqual(
            ExternalLinkRouting.normalizedDomain(from: "https://chatgpt.com/c/abc?model=x"),
            "chatgpt.com"
        )
    }

    func testNormalizedDomainLowercasesBareHost() {
        XCTAssertEqual(ExternalLinkRouting.normalizedDomain(from: "ChatGPT.com"), "chatgpt.com")
    }

    func testNormalizedDomainDropsPort() {
        XCTAssertEqual(ExternalLinkRouting.normalizedDomain(from: "http://localhost:3000/app"), "localhost")
    }

    func testNormalizedDomainStripsWildcardPrefix() {
        XCTAssertEqual(ExternalLinkRouting.normalizedDomain(from: "*.example.com"), "example.com")
    }

    func testNormalizedDomainRejectsEmptyAndMalformedEntries() {
        XCTAssertNil(ExternalLinkRouting.normalizedDomain(from: ""))
        XCTAssertNil(ExternalLinkRouting.normalizedDomain(from: "   "))
        XCTAssertNil(ExternalLinkRouting.normalizedDomain(from: "https://"))
        XCTAssertNil(ExternalLinkRouting.normalizedDomain(from: "not a host"))
    }

    // MARK: - Matching

    func testMatchesExactHost() {
        let url = URL(string: "https://chatgpt.com/c/123?model=x")!
        XCTAssertTrue(ExternalLinkRouting.matches(url: url, domain: "chatgpt.com"))
    }

    func testMatchesSubdomainButNotSuffixLookalike() {
        let subdomain = URL(string: "https://share.chatgpt.com/invite")!
        XCTAssertTrue(ExternalLinkRouting.matches(url: subdomain, domain: "chatgpt.com"))
        let lookalike = URL(string: "https://evilchatgpt.com/")!
        XCTAssertFalse(ExternalLinkRouting.matches(url: lookalike, domain: "chatgpt.com"))
    }

    func testMatchesIgnoresEntryCaseAndURLPort() {
        let url = URL(string: "https://chatgpt.com:8443/")!
        XCTAssertTrue(ExternalLinkRouting.matches(url: url, domain: "ChatGPT.COM"))
    }

    // MARK: - Engine claiming

    /// The claim under an observation of unlock state: secure engines
    /// default to locked (nothing observed), plain engines never consult it.
    private func claim(
        _ link: String,
        in services: [Service],
        unlocked: Set<UUID> = []
    ) -> Service? {
        ExternalLinkRouting.claimedService(
            for: URL(string: link)!,
            in: services,
            isEngineUnlocked: { unlocked.contains($0) }
        )
    }

    func testClaimedServiceReturnsFirstEnabledMatchInSettingsOrder() {
        var first = Service(name: "First", url: "https://first.example.com", focus_selector: "")
        first.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: ["chatgpt.com"])
        var second = Service(name: "Second", url: "https://second.example.com", focus_selector: "")
        second.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: ["chatgpt.com"])

        XCTAssertEqual(
            claim("https://share.chatgpt.com/invite", in: [first, second])?.id,
            first.id
        )
    }

    func testClaimedServiceSkipsDisabledEngines() {
        var disabled = Service(name: "Disabled", url: "https://a.example.com", focus_selector: "")
        disabled.externalLinkHandler = ExternalLinkHandler(isEnabled: false, domains: ["chatgpt.com"])

        XCTAssertNil(claim("https://chatgpt.com/", in: [disabled]))
    }

    func testClaimedServiceReturnsNilWhenNothingClaimsTheURL() {
        var engine = Service(name: "Engine", url: "https://a.example.com", focus_selector: "")
        engine.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: ["example.org"])

        XCTAssertNil(claim("https://chatgpt.com/", in: [engine]))
    }

    // MARK: - Locked secure engines claim nothing

    private func secureEngine(hasMigratedMetadata: Bool, claiming domain: String) -> Service {
        var service = Service(name: "Secure", url: "https://secure.example.com", focus_selector: "")
        service.isEncrypted = true
        service.hasMigratedMetadata = hasMigratedMetadata
        service.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: [domain])
        return service
    }

    func testLockedSecureEngineClaimsNothing() {
        let engine = secureEngine(hasMigratedMetadata: true, claiming: "chatgpt.com")
        XCTAssertNil(claim("https://chatgpt.com/", in: [engine], unlocked: []))
    }

    func testUnlockedSecureEngineClaims() {
        let engine = secureEngine(hasMigratedMetadata: true, claiming: "chatgpt.com")
        XCTAssertEqual(claim("https://chatgpt.com/", in: [engine], unlocked: [engine.id])?.id, engine.id)
    }

    func testLockedLegacySecureEngineClaimsNothing() {
        // A not-yet-migrated engine still keeps its records in settings.json,
        // so plaintext alone would match it — the lock gate must refuse it
        // too, or a locked engine would route links.
        let engine = secureEngine(hasMigratedMetadata: false, claiming: "chatgpt.com")
        XCTAssertNil(claim("https://chatgpt.com/", in: [engine], unlocked: []))
        XCTAssertEqual(claim("https://chatgpt.com/", in: [engine], unlocked: [engine.id])?.id, engine.id)
    }

    func testPlainEngineClaimsRegardlessOfUnlockObservation() {
        var engine = Service(name: "Plain", url: "https://plain.example.com", focus_selector: "")
        engine.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: ["chatgpt.com"])
        XCTAssertEqual(claim("https://chatgpt.com/", in: [engine])?.id, engine.id)
    }

    // MARK: - Forgetting routing records on lock

    func testForgettingRoutingRecordsSparesOnlyTheNameOfMigratedSecureEngines() {
        var engine = secureEngine(hasMigratedMetadata: true, claiming: "chatgpt.com")
        let name = engine.name

        engine.forgetRoutingRecords()

        XCTAssertFalse(engine.externalLinkHandler.isConfigured)
        XCTAssertEqual(engine.name, name)
    }

    func testForgettingRoutingRecordsKeepsLegacyAndPlainEngineRecords() {
        // Their records still live in settings.json, where unlock has
        // nothing to restore them from — dropping them would lose them.
        var legacy = secureEngine(hasMigratedMetadata: false, claiming: "chatgpt.com")
        legacy.forgetRoutingRecords()
        XCTAssertTrue(legacy.externalLinkHandler.isConfigured)

        var plain = Service(name: "Plain", url: "https://plain.example.com", focus_selector: "")
        plain.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: ["chatgpt.com"])
        plain.forgetRoutingRecords()
        XCTAssertTrue(plain.externalLinkHandler.isConfigured)
    }

    // MARK: - Session placement

    private let allSlots = Array(0..<10)

    private func plan(
        placement: ExternalLinkPlacement,
        fixedSessionIndex: Int = 0,
        visibleSlots: [Int]? = nil,
        occupiedSlots: Set<Int> = [],
        visitOrder: [Int]? = nil
    ) -> ExternalLinkSessionPlacement.Plan {
        let visible = visibleSlots ?? allSlots
        return ExternalLinkSessionPlacement.plan(
            placement: placement,
            fixedSessionIndex: fixedSessionIndex,
            visibleSlots: visible,
            occupiedSlots: occupiedSlots,
            visitOrder: visitOrder ?? visible
        )
    }

    func testNewSessionUsesFirstFreeSlot() {
        XCTAssertEqual(
            plan(placement: .newSession, occupiedSlots: [0, 1, 2]),
            .openInSession(index: 3)
        )
    }

    func testNewSessionDefaultsToOldestVisitedWhenAllBusy() {
        // Visit order runs most → least recent, so the last busy slot is the
        // default the replacement prompt opens on.
        let visitOrder = [9, 4, 0, 1, 2, 3, 5, 6, 7, 8]
        XCTAssertEqual(
            plan(placement: .newSession, occupiedSlots: Set(allSlots), visitOrder: visitOrder),
            .replaceBusySession(defaultIndex: 8)
        )
    }

    func testFixedSessionOpensConfiguredSlot() {
        XCTAssertEqual(
            plan(placement: .fixedSession, fixedSessionIndex: 6, occupiedSlots: [0, 6]),
            .openInSession(index: 6)
        )
    }

    func testFixedSessionFallsBackToNewSessionWhenSlotNoLongerVisible() {
        // A Pinned Tabs slot whose URL was removed is unreachable; the link
        // opens in the first free visible slot instead of being dropped.
        XCTAssertEqual(
            plan(placement: .fixedSession, fixedSessionIndex: 7, visibleSlots: [0, 2, 5], occupiedSlots: [0]),
            .openInSession(index: 2)
        )
    }

    func testLastVisitedSessionOpensMostRecentVisit() {
        let visitOrder = [4, 7, 0, 1, 2, 3, 5, 6, 8, 9]
        XCTAssertEqual(
            plan(placement: .lastVisitedSession, visitOrder: visitOrder),
            .openInSession(index: 4)
        )
    }

    func testLastVisitedSessionSkipsHiddenSlots() {
        XCTAssertEqual(
            plan(placement: .lastVisitedSession, visibleSlots: [0, 3], visitOrder: [7, 3, 0]),
            .openInSession(index: 3)
        )
    }

    func testNoSessionAvailableWhenEngineHasNoVisibleSlots() {
        XCTAssertEqual(plan(placement: .newSession, visibleSlots: []), .noSessionAvailable)
        XCTAssertEqual(plan(placement: .lastVisitedSession, visibleSlots: []), .noSessionAvailable)
        XCTAssertEqual(plan(placement: .fixedSession, fixedSessionIndex: 4, visibleSlots: []), .noSessionAvailable)
    }
}
