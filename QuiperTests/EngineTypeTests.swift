import XCTest
@testable import Quiper

@MainActor
final class EngineTypeTests: XCTestCase {
    private func pinnedService(urls: [String]) -> Service {
        Service(
            name: "Pinned",
            url: "https://seed.example.com",
            engineType: .pinnedTabs,
            pinnedTabURLs: Service.normalizedPinnedTabURLs(urls),
            focus_selector: ""
        )
    }

    func testDefaultsToSingleURL() {
        let service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        XCTAssertEqual(service.engineType, .singleURL)
        XCTAssertFalse(service.isPinnedTabs)
        XCTAssertTrue(service.pinnedTabURLs.isEmpty)
    }

    func testConvertToPinnedTabsSeedsFirstSlot() {
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.convertToPinnedTabs()
        XCTAssertTrue(service.isPinnedTabs)
        XCTAssertEqual(service.pinnedTabURLs.count, Service.pinnedTabSlotCount)
        XCTAssertEqual(service.pinnedTabURLs[0], "https://example.com")
        XCTAssertTrue(service.pinnedTabURLs.dropFirst().allSatisfy(\.isEmpty))
    }

    func testConvertToSingleURLPicksFirstPinnedURL() {
        var service = pinnedService(urls: ["", "https://second.example.com", "https://third.example.com"])
        service.convertToSingleURL()
        XCTAssertEqual(service.engineType, .singleURL)
        XCTAssertEqual(service.url, "https://second.example.com")
        XCTAssertTrue(service.pinnedTabURLs.isEmpty)
    }

    func testPinnedURLLookup() {
        let service = pinnedService(urls: ["https://one.example.com", "  ", "https://three.example.com"])
        XCTAssertEqual(service.pinnedURL(for: 0), "https://one.example.com")
        XCTAssertNil(service.pinnedURL(for: 1))
        XCTAssertEqual(service.pinnedURL(for: 2), "https://three.example.com")
        XCTAssertNil(service.pinnedURL(for: 10))
        let single = Service(name: "Test", url: "https://example.com", focus_selector: "")
        XCTAssertNil(single.pinnedURL(for: 0))
    }

    func testPinnedServiceCodableRoundTrip() throws {
        let original = pinnedService(urls: ["https://one.example.com", "https://two.example.com"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Service.self, from: data)
        XCTAssertEqual(decoded.engineType, .pinnedTabs)
        XCTAssertEqual(decoded.pinnedTabURLs, original.pinnedTabURLs)
    }

    func testLegacyPayloadDecodesAsSingleURL() throws {
        let json = """
        {
            "name": "Old Service",
            "url": "https://old.com",
            "focus_selector": "input"
        }
        """
        let service = try JSONDecoder().decode(Service.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(service.engineType, .singleURL)
        XCTAssertTrue(service.pinnedTabURLs.isEmpty)
    }

    func testShortPinnedListNormalizesOnDecode() throws {
        let json = """
        {
            "name": "Pinned",
            "url": "https://seed.example.com",
            "engineType": "pinnedTabs",
            "pinnedTabURLs": ["https://one.example.com"],
            "focus_selector": ""
        }
        """
        let service = try JSONDecoder().decode(Service.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(service.pinnedTabURLs.count, Service.pinnedTabSlotCount)
        XCTAssertEqual(service.pinnedTabURLs[0], "https://one.example.com")
    }

    func testSingleURLServiceOmitsEngineTypeWhenEncoding() throws {
        let service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        let data = try JSONEncoder().encode(service)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["engineType"])
        XCTAssertNil(object["pinnedTabURLs"])
    }

    func testPinnedReloadStaysInPlace() {
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil),
            .openHere
        )
    }

    func testPinnedReloadIgnoresTrailingSlash() {
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com/")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil),
            .openHere
        )
    }

    func testPinnedUnmatchedNavigationOpensExternally() {
        // Unruled links always leave the tab: anything but the pinned URL
        // itself opens in the system browser — even same-host addresses,
        // which would stay in place for single-URL engines.
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com/other")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil),
            .openExternal
        )
    }

    func testPinnedInternalStayRuleBecomesPopup() {
        var service = pinnedService(urls: ["https://one.example.com"])
        service.routingRules = [RoutingRule(pattern: "example\\.org", action: .internalStay)]
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://example.org/page")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil),
            .openNewWindow
        )
    }

    func testPinnedPromptRuleStaysPrompt() {
        var service = pinnedService(urls: ["https://one.example.com"])
        service.routingRules = [RoutingRule(pattern: "example\\.org", action: .prompt)]
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://example.org/page")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil),
            .showPrompt
        )
    }

    func testSingleURLRoutingUnchanged() {
        let service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        let serviceURL = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com/other")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: serviceURL, currentURL: nil),
            .openHere
        )
    }

    func testSameDocumentFragmentStaysInPlaceOnDriftedHost() {
        // Page reached via redirect no longer matches the service root, but a
        // fragment-only change is a scroll, not a navigation.
        let service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        let serviceURL = URL(string: "https://one.example.com")!
        let current = URL(string: "https://drifted.example.org/page")!
        let target = URL(string: "https://drifted.example.org/page#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: serviceURL, currentURL: current),
            .openHere
        )
    }

    func testSameDocumentCheckFallsThroughOnDifferentPathOrQuery() {
        let service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        let serviceURL = URL(string: "https://one.example.com")!
        let current = URL(string: "https://example.org/page?x=1")!
        let differentPath = URL(string: "https://example.org/other#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: differentPath, service: service, serviceURL: serviceURL, currentURL: current),
            .openExternal
        )
        let differentQuery = URL(string: "https://example.org/page?x=2#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: differentQuery, service: service, serviceURL: serviceURL, currentURL: current),
            .openExternal
        )
    }

    func testSameDocumentOverridesExplicitExternalRule() {
        // Fragment-only changes stay in place even when a routing rule would
        // send the host elsewhere: there is no new document to route.
        var service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        service.routingRules = [RoutingRule(pattern: "example\\.org", action: .external)]
        let serviceURL = URL(string: "https://one.example.com")!
        let current = URL(string: "https://example.org/page")!
        let target = URL(string: "https://example.org/page#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: serviceURL, currentURL: current),
            .openHere
        )
    }

    func testSameDocumentFragmentStaysInPlaceForPinnedTabsDespitePinnedMismatch() {
        // Same-document check runs before the pinned-tab branch: a fragment
        // scroll on a drifted page stays in place even though the target no
        // longer matches the pinned URL.
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let current = URL(string: "https://drifted.example.org/page")!
        let target = URL(string: "https://drifted.example.org/page#section")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: current),
            .openHere
        )
    }

    func testHasEmptyMetadataAccountsForPinnedURLs() {
        var service = Service(name: "Test", url: "", focus_selector: "")
        XCTAssertTrue(service.hasEmptyMetadata)
        service = pinnedService(urls: ["https://one.example.com"])
        service.url = ""
        XCTAssertFalse(service.hasEmptyMetadata)
    }

    func testVisibleSessionIndicesShowAllSlotsForSingleURL() {
        let service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        XCTAssertEqual(service.visibleSessionIndices, Array(0..<10))
    }

    func testVisibleSessionIndicesHidePinnedSlotsWithoutURL() {
        let service = pinnedService(urls: ["https://one.example.com", "", "https://three.example.com"])
        XCTAssertEqual(service.visibleSessionIndices, [0, 2])
    }

    func testVisibleSessionIndicesEmptyWhenNoPinnedURLsDefined() {
        let service = pinnedService(urls: [])
        XCTAssertTrue(service.visibleSessionIndices.isEmpty)
    }

    // MARK: - Click modifiers

    private let commandModifiers = ClickModifiers(commandPressed: true)
    private let commandShiftModifiers = ClickModifiers(commandPressed: true, shiftPressed: true)
    private let commandOptionModifiers = ClickModifiers(commandPressed: true, optionPressed: true)
    private let optionModifiers = ClickModifiers(optionPressed: true)

    func testModifierDecisionForcesCommandCombosWhereverTheClickGoes() {
        // ⌘/⌘⇧/⌘⌥ name their destination whatever the bare click would
        // have done — a prompt rule and a pinned engine included — and no
        // modifiers at all never force anything.
        XCTAssertNil(RoutingResolver.modifierDecision(modifiers: .none))
        XCTAssertEqual(RoutingResolver.modifierDecision(modifiers: commandModifiers), .openNewWindow)
        XCTAssertEqual(RoutingResolver.modifierDecision(modifiers: commandShiftModifiers), .openPrivate)
        XCTAssertEqual(RoutingResolver.modifierDecision(modifiers: commandOptionModifiers), .openExternal)
        // Shift without ⌘ means nothing.
        XCTAssertNil(RoutingResolver.modifierDecision(modifiers: ClickModifiers(shiftPressed: true)))
        // ⌘⇧ names Open Private even with ⌥ riding along.
        XCTAssertEqual(
            RoutingResolver.modifierDecision(modifiers: ClickModifiers(commandPressed: true, optionPressed: true, shiftPressed: true)),
            .openPrivate
        )
    }

    func testOptionAlwaysPerformsOpenLinkHere() {
        // ⌥ performs the explicit Open Link Here action itself — the very
        // thing the menu item does — in every engine and every frame,
        // pinned tabs included: whatever the bare click would have done,
        // however it is triggered the action is the same one.
        XCTAssertEqual(RoutingResolver.modifierDecision(modifiers: optionModifiers), .openHere)
    }

    func testRouteAppliesClickModifiers() {
        let service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        let serviceURL = URL(string: "https://one.example.com")!
        let sameOrigin = URL(string: "https://one.example.com/other")!
        let elsewhere = URL(string: "https://example.org/page")!
        var promptService = service
        promptService.routingRules = [RoutingRule(pattern: "example\\.org", action: .prompt)]

        // A bare click keeps routing's answer; the same links under ⌘/⌘⇧/⌘⌥
        // take their modifier's destination instead.
        XCTAssertEqual(RoutingResolver.route(for: sameOrigin, service: service, serviceURL: serviceURL, currentURL: nil), .openHere)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: serviceURL, currentURL: nil), .openExternal)
        XCTAssertEqual(RoutingResolver.route(for: sameOrigin, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: commandModifiers), .openNewWindow)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: commandModifiers), .openNewWindow)
        XCTAssertEqual(RoutingResolver.route(for: sameOrigin, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: commandShiftModifiers), .openPrivate)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: commandOptionModifiers), .openExternal)

        // ⌥ performs Open Link Here — the explicit instruction — stepping
        // over an outward-bound rule and a prompt rule alike; a link that
        // already stays is the same answer either way.
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: optionModifiers), .openHere)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: promptService, serviceURL: serviceURL, currentURL: nil), .showPrompt)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: promptService, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: optionModifiers), .openHere)
        XCTAssertEqual(RoutingResolver.route(for: sameOrigin, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: optionModifiers), .openHere)

        // Shift without ⌘ changes nothing.
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: nil, modifiers: ClickModifiers(shiftPressed: true)), .openExternal)
    }

    func testRouteOptionInPinnedTabPerformsOpenLinkHereToo() {
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let elsewhere = URL(string: "https://example.org/page")!

        // ⌥ performs the same Open Link Here action in a pinned engine too:
        // the link loads in place, so the pinned invariant is the bare
        // click's own; ⌘/⌘⇧/⌘⌥ keep their destinations.
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil, modifiers: optionModifiers), .openHere)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil, modifiers: commandModifiers), .openNewWindow)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil, modifiers: commandShiftModifiers), .openPrivate)
        XCTAssertEqual(RoutingResolver.route(for: elsewhere, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil, modifiers: commandOptionModifiers), .openExternal)
        // The pinned address itself still reloads in place under ⌥.
        XCTAssertEqual(RoutingResolver.route(for: pinned, service: service, serviceURL: pinned, pinnedURL: pinned, currentURL: nil, modifiers: optionModifiers), .openHere)
    }
}
