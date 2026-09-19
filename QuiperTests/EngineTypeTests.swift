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
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned),
            .openHere
        )
    }

    func testPinnedReloadIgnoresTrailingSlash() {
        let service = pinnedService(urls: ["https://one.example.com"])
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com/")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned),
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
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned),
            .openExternal
        )
    }

    func testPinnedInternalStayRuleBecomesPopup() {
        var service = pinnedService(urls: ["https://one.example.com"])
        service.routingRules = [RoutingRule(pattern: "example\\.org", action: .internalStay)]
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://example.org/page")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned),
            .openNewWindow
        )
    }

    func testPinnedPromptRuleStaysPrompt() {
        var service = pinnedService(urls: ["https://one.example.com"])
        service.routingRules = [RoutingRule(pattern: "example\\.org", action: .prompt)]
        let pinned = URL(string: "https://one.example.com")!
        let target = URL(string: "https://example.org/page")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: pinned, pinnedURL: pinned),
            .showPrompt
        )
    }

    func testSingleURLRoutingUnchanged() {
        let service = Service(name: "Test", url: "https://one.example.com", focus_selector: "")
        let serviceURL = URL(string: "https://one.example.com")!
        let target = URL(string: "https://one.example.com/other")!
        XCTAssertEqual(
            RoutingResolver.route(for: target, service: service, serviceURL: serviceURL),
            .openHere
        )
    }

    func testRestoredTabsSkipPinnedEngines() {
        let pinned = pinnedService(urls: ["https://one.example.com"])
        let single = Service(name: "Single", url: "https://single.example.com", focus_selector: "")
        let state = PersistedTabState(
            activeIndicesByID: [pinned.id: 0, single.id: 0],
            openTabs: [pinned.id: [0: "https://stale.example.com"], single.id: [0: "https://single.example.com/page"]]
        )
        let restored = state.restoredTabs(services: [pinned, single], activeIndexProvider: { _ in 0 })
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.serviceID, single.id)
    }

    func testHasEmptyMetadataAccountsForPinnedURLs() {
        var service = Service(name: "Test", url: "", focus_selector: "")
        XCTAssertTrue(service.hasEmptyMetadata)
        service = pinnedService(urls: ["https://one.example.com"])
        service.url = ""
        XCTAssertFalse(service.hasEmptyMetadata)
    }
}
