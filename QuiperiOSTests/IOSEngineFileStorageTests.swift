import Foundation
import Testing
import WebKit
@testable import QuiperiOS

/// Covers the file-backed engine customization storage: round trips, the
/// resolution order (synced template → file → stored value), the protected-
/// engine file guard, and cleanup on engine removal.
@MainActor
@Suite(.serialized)
struct IOSEngineFileStorageTests {

    @Test func customCSSRoundTripsAndEmptySaveDeletes() {
        let serviceID = UUID()
        defer { EngineFileStorage.deleteCustomCSS(for: serviceID) }

        EngineFileStorage.saveCustomCSS("body { color: red; }", serviceID: serviceID)
        #expect(EngineFileStorage.loadCustomCSS(serviceID: serviceID, fallback: "fallback") == "body { color: red; }")

        EngineFileStorage.saveCustomCSS("", serviceID: serviceID)
        #expect(EngineFileStorage.loadCustomCSS(serviceID: serviceID, fallback: "fallback") == "fallback")
    }

    @Test func actionScriptRoundTripsAndEmptySaveDeletes() {
        let serviceID = UUID()
        let actionID = UUID()
        defer { EngineFileStorage.deleteActionScripts(for: serviceID) }

        EngineFileStorage.saveActionScript("console.log('hi')", serviceID: serviceID, actionID: actionID)
        #expect(
            EngineFileStorage.loadActionScript(serviceID: serviceID, actionID: actionID, fallback: "fallback")
                == "console.log('hi')"
        )

        EngineFileStorage.saveActionScript("  \n  ", serviceID: serviceID, actionID: actionID)
        #expect(
            EngineFileStorage.loadActionScript(serviceID: serviceID, actionID: actionID, fallback: "fallback")
                == "fallback"
        )
    }

    @Test func unsyncedResolutionPrefersFileOverStoredValue() {
        let serviceID = UUID()
        defer { EngineFileStorage.deleteCustomCSS(for: serviceID) }

        var service = Service(name: "Only Here \(serviceID.uuidString.prefix(6))", url: "https://example.com", focus_selector: "")
        service.id = serviceID
        service.customCSS = "body { color: blue; }"

        EngineFileStorage.saveCustomCSS("body { color: red; }", serviceID: serviceID)

        #expect(ActionScripts.resolvedCustomCSS(for: service) == "body { color: red; }")
    }

    @Test func syncedResolutionPrefersTemplateOverFile() throws {
        let template = try #require(DefaultEngineDefinitions.definitions.first {
            ActionScripts.defaultCustomCSS(for: $0) != nil
        })
        let templateCSS = try #require(ActionScripts.defaultCustomCSS(for: template))

        var service = template
        service.id = UUID()
        service.templateCustomCSSSync = true
        service.customCSS = nil

        defer { EngineFileStorage.deleteCustomCSS(for: service.id) }
        EngineFileStorage.saveCustomCSS("body { color: red; }", serviceID: service.id)

        #expect(ActionScripts.resolvedCustomCSS(for: service) == templateCSS)
    }

    @Test func protectedEnginesNeverWriteFiles() {
        let settingsURL = temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: NoopWebsiteDataStoreManager(),
            allowsNetworkWork: false
        )
        defer { removeSettings(at: settingsURL) }

        let action = CustomAction(name: "New Action")
        environment.customActions = [action]
        var service = Service(name: "Sealed \(serviceIDSuffix())", url: "https://example.com", focus_selector: "")
        service.id = UUID()
        service.isEncrypted = true
        environment.services = [service]

        environment.saveCustomActionScript("console.log('secret')", serviceID: service.id, actionID: action.id)
        environment.updateService(service)

        let actionScriptURL = EngineFileStorage.actionScriptURL(serviceID: service.id, actionID: action.id)
        let cssURL = EngineFileStorage.customCSSURL(serviceID: service.id)
        #expect(!FileManager.default.fileExists(atPath: actionScriptURL.path))
        #expect(!FileManager.default.fileExists(atPath: cssURL.path))
    }

    @Test func removingEngineDeletesItsFiles() {
        let settingsURL = temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: NoopWebsiteDataStoreManager(),
            allowsNetworkWork: false
        )
        defer { removeSettings(at: settingsURL) }

        let action = CustomAction(name: "New Action")
        environment.customActions = [action]
        var service = Service(name: "Files \(serviceIDSuffix())", url: "https://example.com", focus_selector: "")
        service.id = UUID()
        service.customCSS = "body { color: green; }"
        environment.services = [service]

        environment.updateService(service)
        environment.saveCustomActionScript("console.log('kept')", serviceID: service.id, actionID: action.id)
        #expect(FileManager.default.fileExists(atPath: EngineFileStorage.customCSSURL(serviceID: service.id).path))

        environment.removeService(service.id)

        #expect(!FileManager.default.fileExists(atPath: EngineFileStorage.customCSSURL(serviceID: service.id).path))
        #expect(!FileManager.default.fileExists(atPath: EngineFileStorage.actionScriptURL(serviceID: service.id, actionID: action.id).path))
    }

    private func serviceIDSuffix() -> String {
        UUID().uuidString.prefix(6).description
    }

    private func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-tests-\(UUID().uuidString).json")
    }

    private func removeSettings(at url: URL) {
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
