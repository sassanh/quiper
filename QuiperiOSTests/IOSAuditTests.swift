import Foundation
import Testing
import WebKit
@testable import QuiperiOS

@MainActor
@Suite(.serialized)
struct IOSAuditTests {
    @Test func settingsRoundTripPreservesPlatformAndUnknownFields() throws {
        let service = makeService()
        let settings = PersistedSettings(
            services: [service],
            dragAreaPosition: .top,
            colorScheme: .dark,
            persistedTabState: PersistedTabState(activeServiceID: service.id),
            version: 1
        )
        let url = temporarySettingsURL()
        try write(settings, to: url, extra: [
            "hotkey": ["keyCode": 42, "modifierFlags": commandModifier],
            "appShortcuts": ["nextSession": ["keyCode": 123]],
            "futureSetting": ["enabled": true, "revision": 7],
            "selectorDisplayMode": "Compact"
        ])
        defer { removeSettings(at: url) }

        let environment = testEnvironment(settingsURL: url)
        #expect(environment.dragAreaPosition == .top)
        environment.colorScheme = .light
        environment.dragAreaPosition = .bottom
        environment.save()
        let firstSave = try Data(contentsOf: url)
        environment.save()
        let secondSave = try Data(contentsOf: url)

        let object = try settingsObject(at: url)
        #expect(object["hotkey"] as? [String: Any] != nil)
        #expect(object["appShortcuts"] as? [String: Any] != nil)
        #expect((object["futureSetting"] as? [String: Any])?["revision"] as? Int == 7)
        #expect(object["selectorDisplayMode"] == nil)
        #expect((try? JSONDecoder().decode(PersistedSettings.self, from: JSONSerialization.data(withJSONObject: object)))?.colorScheme == .light)
        #expect((try? JSONDecoder().decode(PersistedSettings.self, from: JSONSerialization.data(withJSONObject: object)))?.dragAreaPosition == .bottom)
        #expect(firstSave == secondSave)
    }

    @Test func emptyServicesRemainEmptyAndNeverPolicyRemovesTabState() throws {
        let service = makeService()
        let settings = PersistedSettings(
            services: [],
            tabSurvivalPolicy: .never,
            persistedTabState: PersistedTabState(activeServiceID: service.id),
            version: 1
        )
        let url = temporarySettingsURL()
        try write(settings, to: url)
        defer { removeSettings(at: url) }

        let environment = testEnvironment(settingsURL: url)
        #expect(environment.services.isEmpty)
        #expect(environment.dragAreaPosition == .bottom)
        environment.save()

        let object = try settingsObject(at: url)
        #expect(object["services"] as? [Any] != nil)
        #expect((object["services"] as? [Any])?.isEmpty == true)
        #expect(object["persistedTabState"] == nil)
    }

    @Test func activeSessionRestoresLazily() throws {
        let service = makeService()
        var tabState = PersistedTabState(activeServiceID: service.id)
        tabState.activeIndicesByID[service.id] = 0
        tabState.openTabs[service.id] = [0: "about:blank", 1: "about:blank"]
        let settings = PersistedSettings(services: [service], persistedTabState: tabState)
        let url = temporarySettingsURL()
        try write(settings, to: url)
        defer { removeSettings(at: url) }

        let environment = testEnvironment(settingsURL: url)
        #expect(environment.existingSession(for: service.id, sessionIndex: 0) != nil)
        #expect(environment.existingSession(for: service.id, sessionIndex: 1) == nil)

        let lazySession = environment.webViewSession(
            for: service.id,
            sessionIndex: 1,
            initialURL: URL(string: "about:blank"),
            loadImmediately: false
        )
        #expect(lazySession.serviceID == service.id)
        #expect(environment.existingSession(for: service.id, sessionIndex: 1) != nil)
    }

    @Test func removingServiceCleansPersistedAndLiveState() {
        let service = makeService()
        let settingsURL = temporarySettingsURL()
        let environment = testEnvironment(settingsURL: settingsURL)
        defer { removeSettings(at: settingsURL) }

        environment.services = [service]
        environment.persistedTabState.activeServiceID = service.id
        environment.persistedTabState.openTabs[service.id] = [0: "about:blank"]
        environment.persistedTabState.tabTitles[service.id] = [0: "Title"]
        environment.persistedTabState.tabInputs[service.id] = [
            0: TabInputState(text: "draft", isContentEditable: false, start: 0, end: 5)
        ]
        environment.persistedTabState.tabPromptHistories[service.id] = [
            0: [PromptHistoryEntry(text: "prompt", timestamp: Date(timeIntervalSince1970: 1))]
        ]
        environment.persistedTabState.tabPromptHistoryEnabledOverrides[service.id] = [0: false]
        environment.persistedTabState.tabHistory = [
            TabIdentifier(serviceID: service.id, sessionIndex: 0)
        ]
        _ = environment.webViewSession(
            for: service.id,
            sessionIndex: 0,
            initialURL: URL(string: "about:blank"),
            loadImmediately: false
        )

        environment.removeService(service.id)

        #expect(environment.services.isEmpty)
        #expect(environment.existingSession(for: service.id, sessionIndex: 0) == nil)
        #expect(environment.persistedTabState.openTabs[service.id] == nil)
        #expect(environment.persistedTabState.tabTitles[service.id] == nil)
        #expect(environment.persistedTabState.tabInputs[service.id] == nil)
        #expect(environment.persistedTabState.tabPromptHistories[service.id] == nil)
        #expect(environment.persistedTabState.tabPromptHistoryEnabledOverrides[service.id] == nil)
        #expect(environment.persistedTabState.tabHistory?.isEmpty != false)
    }

    @Test func eachRemovedEnginePurgesOnlyItsIsolatedStore() async {
        let first = makeService(name: "First", url: "https://Example.com/one")
        let second = makeService(name: "Second", url: "https://example.com/two")
        let manager = RecordingWebsiteDataStoreManager()
        let settingsURL = temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: manager,
            allowsNetworkWork: false
        )
        defer { removeSettings(at: settingsURL) }
        environment.services = [first, second]

        environment.removeService(first.id)
        await Task.yield()
        #expect(manager.removedServiceIDs == [first.id])

        environment.removeService(second.id)
        await Task.yield()
        #expect(manager.removedServiceIDs == [first.id, second.id])
    }

    @Test func disabledWebsiteCleanupDoesNotPurge() async {
        let service = makeService()
        let manager = RecordingWebsiteDataStoreManager()
        let settingsURL = temporarySettingsURL()
        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: manager,
            allowsNetworkWork: false
        )
        defer { removeSettings(at: settingsURL) }
        environment.services = [service]
        environment.shouldPurgeDanglingWebData = false

        environment.removeService(service.id)
        await Task.yield()

        #expect(manager.removedServiceIDs.isEmpty)
    }

    @Test func promptHistoryHonorsEachTriggerAndLimit() {
        let service = makeService(preservePrompt: true)
        let settingsURL = temporarySettingsURL()
        let environment = testEnvironment(settingsURL: settingsURL)
        defer { removeSettings(at: settingsURL) }
        environment.services = [service]
        environment.promptHistoryLimit = 1

        environment.recordPrompt("first", clearType: "selectionClear", for: service.id, sessionIndex: 0)
        #expect(environment.promptHistory(for: service.id, sessionIndex: 0).isEmpty)

        environment.promptHistoryRecordOnSelectionClear = true
        environment.recordPrompt("first", clearType: "selectionClear", for: service.id, sessionIndex: 0)
        environment.recordPrompt("second", clearType: "submit", for: service.id, sessionIndex: 0)
        environment.recordPrompt(" ", clearType: "submit", for: service.id, sessionIndex: 0)
        environment.recordPrompt("third", clearType: "unknown", for: service.id, sessionIndex: 0)

        #expect(environment.promptHistory(for: service.id, sessionIndex: 0).map(\.text) == ["second"])

        environment.services[0].preservePrompt = false
        environment.recordPrompt("fourth", clearType: "submit", for: service.id, sessionIndex: 0)
        #expect(environment.promptHistory(for: service.id, sessionIndex: 0).map(\.text) == ["second"])
    }

    @Test func notificationDestinationSupportsCurrentAndLegacyMetadata() {
        let serviceID = UUID()
        let current = NotificationDestination(userInfo: [
            NotificationMetadata.serviceIDKey: serviceID.uuidString,
            NotificationMetadata.serviceURLKey: "https://example.com",
            NotificationMetadata.sessionIndexKey: NSNumber(value: 3)
        ])
        #expect(current.serviceID == serviceID)
        #expect(current.serviceURL == "https://example.com")
        #expect(current.sessionIndex == 3)

        let legacy = NotificationDestination(userInfo: [
            NotificationMetadata.legacyServiceURLKey: "https://legacy.example",
            NotificationMetadata.legacySessionIndexKey: 2
        ])
        #expect(legacy.serviceID == nil)
        #expect(legacy.serviceURL == "https://legacy.example")
        #expect(legacy.sessionIndex == 2)
    }

    @Test func notificationActivationValidatesServiceAndSession() {
        let service = makeService()
        let settingsURL = temporarySettingsURL()
        let environment = testEnvironment(settingsURL: settingsURL)
        defer { removeSettings(at: settingsURL) }
        environment.services = [service]

        environment.activateNotification(
            serviceID: nil,
            serviceURL: service.url,
            sessionIndex: 99
        )
        #expect(environment.persistedTabState.activeServiceID == service.id)
        #expect(environment.persistedTabState.activeIndicesByID[service.id] == 0)
    }

    @Test func ringOverlaySuppressionPropagatesToExistingAndNewSessions() {
        let service = makeService(focusSelector: "#prompt")
        let settingsURL = temporarySettingsURL()
        let environment = testEnvironment(settingsURL: settingsURL)
        defer { removeSettings(at: settingsURL) }
        environment.services = [service]

        let existing = environment.webViewSession(
            for: service.id,
            sessionIndex: 0,
            initialURL: URL(string: "about:blank"),
            loadImmediately: false
        )
        environment.setRingOverlayActive(true)
        #expect(existing.isKeyboardSuppressed)

        let newSession = environment.webViewSession(
            for: service.id,
            sessionIndex: 1,
            initialURL: URL(string: "about:blank"),
            loadImmediately: false
        )
        #expect(newSession.isKeyboardSuppressed)

        environment.setRingOverlayActive(false)
        #expect(!existing.isKeyboardSuppressed)
        #expect(!newSession.isKeyboardSuppressed)
    }

    @Test func findLifecycleUpdatesCountsAndClearsState() async throws {
        let service = makeService()
        let settingsURL = temporarySettingsURL()
        let environment = testEnvironment(settingsURL: settingsURL)
        defer { removeSettings(at: settingsURL) }
        environment.services = [service]
        let session = environment.webViewSession(
            for: service.id,
            sessionIndex: 0,
            initialURL: nil,
            loadImmediately: false
        )

        session.webView.loadHTMLString(
            "<body>needle <span>needle</span></body>",
            baseURL: nil
        )
        try await waitForFindFixture(in: session)
        session.setFindQuery("needle")
        try await waitForFindStatus("1 of 2", in: session)

        session.stepFind(forward: true)
        try await waitForFindStatus("2 of 2", in: session)

        session.resetFind()
        #expect(session.findStatusText == nil)
    }

    private func waitForFindFixture(
        in session: WebViewSession,
        timeout: Duration = .seconds(30)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let isReady = try? await session.webView.evaluateJavaScript(
                "document.readyState === 'complete' && document.body?.innerText === 'needle needle'"
            ) as? Bool
            if isReady == true {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(Bool(false), "Find fixture did not finish loading")
    }

    private func waitForFindStatus(
        _ expected: String,
        in session: WebViewSession,
        timeout: Duration = .seconds(10)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if session.findStatusText == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(session.findStatusText == expected)
    }

    private func makeService(
        id: UUID = UUID(),
        name: String = "Test",
        url: String = "https://example.com",
        focusSelector: String = "",
        preservePrompt: Bool = true
    ) -> Service {
        Service(
            id: id,
            name: name,
            url: url,
            focus_selector: focusSelector,
            preservePrompt: preservePrompt
        )
    }

    private func testEnvironment(settingsURL: URL) -> AppEnvironment {
        AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: RecordingWebsiteDataStoreManager(),
            allowsNetworkWork: false
        )
    }

    private func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-tests-\(UUID().uuidString).json")
    }

    private func write(
        _ settings: PersistedSettings,
        to url: URL,
        extra: [String: Any] = [:]
    ) throws {
        let encoded = try JSONEncoder().encode(settings)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (key, value) in extra {
            object[key] = value
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func settingsObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func removeSettings(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class RecordingWebsiteDataStoreManager: WebsiteDataStoreManaging {
    private(set) var removedServiceIDs: [UUID] = []
    private(set) var legacyResetCount = 0

    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore.nonPersistent()
    }

    func resetLegacyDefaultStore() async {
        legacyResetCount += 1
    }

    func removeDataStore(for serviceID: UUID) async throws {
        removedServiceIDs.append(serviceID)
    }
}

private let commandModifier = 1_048_576
