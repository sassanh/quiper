import XCTest
@testable import Quiper

@MainActor
final class ExternalLinkHandlerPersistenceTests: XCTestCase {
    private func configuredHandler() -> ExternalLinkHandler {
        ExternalLinkHandler(
            isEnabled: true,
            domains: ["chatgpt.com", "share.chatgpt.com"],
            placement: .fixedSession,
            fixedSessionIndex: 6
        )
    }

    func testDefaultHandlerDecodesWhenKeyMissing() throws {
        let json = """
        {"name": "Test", "url": "https://example.com", "focus_selector": ""}
        """
        let service = try JSONDecoder().decode(Service.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(service.externalLinkHandler, ExternalLinkHandler())
        XCTAssertFalse(service.externalLinkHandler.isEnabled)
    }

    func testConfiguredHandlerRoundTrips() throws {
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.externalLinkHandler = configuredHandler()

        let data = try JSONEncoder().encode(service)
        let decoded = try JSONDecoder().decode(Service.self, from: data)

        XCTAssertEqual(decoded.externalLinkHandler, service.externalLinkHandler)
    }

    func testPristineHandlerEncodesNothing() throws {
        let service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        let data = try JSONEncoder().encode(service)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["externalLinkHandler"])
    }

    func testMigratedEncryptedEngineKeepsHandlerOutOfSettingsJSON() throws {
        // The claimed domains live inside the encrypted bundle: while the
        // volume is locked neither settings.json nor the router may see
        // them — only the engine's name stays outside.
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.isEncrypted = true
        service.hasMigratedMetadata = true
        service.externalLinkHandler = configuredHandler()

        let data = try JSONEncoder().encode(service)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["externalLinkHandler"])
        XCTAssertNil(object["url"])
    }

    func testLegacyEncryptedEngineKeepsHandlerInSettingsJSON() throws {
        // A not-yet-migrated engine keeps its whole metadata in settings.json;
        // its records join it there and move into the bundle when the unlock
        // migrates the engine.
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.isEncrypted = true
        service.hasMigratedMetadata = false
        service.externalLinkHandler = configuredHandler()

        let data = try JSONEncoder().encode(service)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["externalLinkHandler"])
    }

    func testDisabledHandlerKeepsTypedDomains() throws {
        // Turning the toggle off must not lose the domains the user typed.
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.externalLinkHandler = ExternalLinkHandler(isEnabled: false, domains: ["chatgpt.com"])

        let data = try JSONEncoder().encode(service)
        let decoded = try JSONDecoder().decode(Service.self, from: data)

        XCTAssertFalse(decoded.externalLinkHandler.isEnabled)
        XCTAssertEqual(decoded.externalLinkHandler.domains, ["chatgpt.com"])
    }

    func testPartialHandlerDecodesFieldByField() throws {
        let json = """
        {"name": "Test", "url": "https://example.com", "focus_selector": "",
         "externalLinkHandler": {"domains": ["chatgpt.com"]}}
        """
        let service = try JSONDecoder().decode(Service.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(service.externalLinkHandler.domains, ["chatgpt.com"])
        XCTAssertFalse(service.externalLinkHandler.isEnabled)
        XCTAssertEqual(service.externalLinkHandler.placement, .newSession)
        XCTAssertEqual(service.externalLinkHandler.fixedSessionIndex, ExternalLinkHandler.defaultFixedSessionIndex)
    }

    func testDefaultFixedSessionIsTheLastSlot() {
        XCTAssertEqual(ExternalLinkHandler().fixedSessionIndex, SessionSlots.count - 1)
        XCTAssertEqual(SessionSlots.label(for: ExternalLinkHandler().fixedSessionIndex), "0")
    }

    func testFixedSessionIndexClampsIntoSlotRange() throws {
        let json = """
        {"name": "Test", "url": "https://example.com", "focus_selector": "",
         "externalLinkHandler": {"isEnabled": true, "domains": ["a.example.com"],
                                  "placement": "fixedSession", "fixedSessionIndex": 42}}
        """
        let service = try JSONDecoder().decode(Service.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(service.externalLinkHandler.fixedSessionIndex, SessionSlots.count - 1)
    }

    func testHandlerIsConfiguredOnlyWhenUserSetSomething() {
        XCTAssertFalse(ExternalLinkHandler().isConfigured)
        XCTAssertTrue(ExternalLinkHandler(domains: ["example.com"]).isConfigured)
        XCTAssertTrue(ExternalLinkHandler(placement: .lastVisitedSession).isConfigured)
        XCTAssertTrue(ExternalLinkHandler(fixedSessionIndex: 3).isConfigured)
        XCTAssertTrue(ExternalLinkHandler(isEnabled: true).isConfigured)
    }

    // MARK: - Routing records in secure storage

    func testSecuredMetadataCarriesTheHandler() throws {
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.externalLinkHandler = configuredHandler()

        let metadata = SecuredEngineMetadata(from: service)
        let decoded = try JSONDecoder().decode(
            SecuredEngineMetadata.self,
            from: JSONEncoder().encode(metadata)
        )

        var restored = Service(name: "Test", url: "", focus_selector: "")
        decoded.apply(to: &restored)

        XCTAssertEqual(restored.externalLinkHandler, configuredHandler())
    }

    func testSecuredMetadataWrittenBeforeRoutingRecordsAppliesTheDefault() throws {
        // A bundle from before routing records existed carries no key;
        // unlocking it must leave the engine claiming nothing rather than
        // resurrect a record.
        let json = """
        {"url": "https://example.com", "focus_selector": ""}
        """
        let metadata = try JSONDecoder().decode(
            SecuredEngineMetadata.self,
            from: json.data(using: .utf8)!
        )
        var service = Service(name: "Test", url: "https://example.com", focus_selector: "")
        service.externalLinkHandler = configuredHandler()

        metadata.apply(to: &service)

        XCTAssertFalse(service.externalLinkHandler.isConfigured)
    }

    func testRoutingRecordsCountAsContentForTheEmptyMetadataGuard() {
        // A bundle whose only metadata is its routing record is not empty —
        // the write gate must not refuse to store it.
        var service = Service(name: "Test", url: "", focus_selector: "")
        XCTAssertTrue(service.hasEmptyMetadata)

        service.externalLinkHandler = configuredHandler()

        XCTAssertFalse(service.hasEmptyMetadata)
        XCTAssertFalse(SecuredEngineMetadata(from: service).isEmpty)
    }
}
