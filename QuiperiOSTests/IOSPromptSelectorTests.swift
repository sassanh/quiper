import Foundation
import Testing
import WebKit
@testable import QuiperiOS

/// Covers the shared prompt-input-selector resolution boundary and the iOS
/// template-sync seeding, mirroring macOS `SettingsServiceTests` selector cases.
@MainActor
@Suite(.serialized)
struct IOSPromptSelectorTests {

    @Test func syncedEngineResolvesTemplateDefaultEvenWithEmptyStoredSelector() throws {
        let template = try #require(Self.templateWithPromptSelector())
        let defaultSelector = try #require(ActionScripts.defaultPromptInputSelector(for: template))

        // Mirrors settings carried over from macOS, where a template-backed
        // engine stores an empty selector while it follows the template.
        var service = template
        service.id = UUID()
        service.templatePromptInputSelectorSync = true
        service.focus_selector = ""

        #expect(service.focus_selector.isEmpty)
        #expect(ActionScripts.resolvedPromptInputSelector(for: service) == defaultSelector)
    }

    @Test func unsyncedTemplateEngineResolvesItsOwnStoredSelector() throws {
        let template = try #require(Self.templateWithPromptSelector())

        var service = template
        service.id = UUID()
        service.templatePromptInputSelectorSync = false
        service.focus_selector = "#custom-prompt-input"

        #expect(ActionScripts.resolvedPromptInputSelector(for: service) == "#custom-prompt-input")
    }

    @Test func engineWithoutTemplateResolvesItsOwnStoredSelector() {
        var service = Service(name: "Only Here", url: "https://example.com", focus_selector: "")
        service.id = UUID()
        service.templatePromptInputSelectorSync = true
        service.focus_selector = "textarea"

        #expect(ActionScripts.defaultPromptInputSelector(for: service) == nil)
        #expect(ActionScripts.resolvedPromptInputSelector(for: service) == "textarea")
    }

    @Test func addingTemplateEngineSeedsSelectorSyncLikeMacOS() throws {
        let template = try #require(Self.templateWithPromptSelector())
        let settingsURL = Self.temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: NoopWebsiteDataStoreManager(),
            allowsNetworkWork: false
        )
        defer { Self.removeSettings(at: settingsURL) }

        environment.addService(from: template, enrichIcons: false)

        let added = try #require(environment.services.last(where: { $0.name == template.name }))
        #expect(added.templatePromptInputSelectorSync)
        #expect(added.focus_selector.isEmpty)

        let defaultSelector = try #require(ActionScripts.defaultPromptInputSelector(for: added))
        #expect(ActionScripts.resolvedPromptInputSelector(for: added) == defaultSelector)
    }

    @Test func addingBlankEngineLeavesSelectorUnsynced() throws {
        let settingsURL = Self.temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: NoopWebsiteDataStoreManager(),
            allowsNetworkWork: false
        )
        defer { Self.removeSettings(at: settingsURL) }

        // addService assigns a fresh identifier, so locate the appended engine
        // by position instead of the constructed one.
        let serviceCountBefore = environment.services.count
        let blank = Service(
            name: "Unique Blank \(UUID().uuidString.prefix(6))",
            url: "https://example.com",
            focus_selector: "#my-own-field"
        )
        environment.addService(from: blank, enrichIcons: false)

        #expect(environment.services.count == serviceCountBefore + 1)
        let added = try #require(environment.services.last)
        #expect(!added.templatePromptInputSelectorSync)
        #expect(added.focus_selector == "#my-own-field")
        #expect(ActionScripts.resolvedPromptInputSelector(for: added) == "#my-own-field")
    }

    private static func templateWithPromptSelector() -> Service? {
        DefaultEngineDefinitions.definitions.first {
            ActionScripts.defaultPromptInputSelector(for: $0) != nil
        }
    }

    private static func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-tests-\(UUID().uuidString).json")
    }

    private static func removeSettings(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class NoopWebsiteDataStoreManager: WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore.nonPersistent()
    }

    func resetLegacyDefaultStore() async {}

    func removeDataStore(for serviceID: UUID) async throws {}
}
