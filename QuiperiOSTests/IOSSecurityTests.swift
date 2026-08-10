import Foundation
import SwiftUI
import Testing
import WebKit
@testable import QuiperiOS

@MainActor
@Suite(.serialized)
struct IOSSecurityTests {
    @Test func encryptedProfileRoundTripsAndRejectsWrongKeyAndTampering() throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let service = makeSensitiveService()
        let profile = makeSensitiveProfile(service: service)
        let key = Data(repeating: 0x31, count: 32)
        let wrongKey = Data(repeating: 0x42, count: 32)

        try fixture.profileStore.saveProfile(profile, key: key)
        #expect(try fixture.profileStore.loadProfile(for: service.id, key: key) == profile)

        do {
            _ = try fixture.profileStore.loadProfile(for: service.id, key: wrongKey)
            Issue.record("A profile decrypted with the wrong key")
        } catch {
            #expect(error as? SecureProfileStoreError == .corruptProfile)
        }

        try tamperWithCiphertext(at: fixture.profileURL(for: service.id))
        do {
            _ = try fixture.profileStore.loadProfile(for: service.id, key: key)
            Issue.record("A modified profile passed authentication")
        } catch {
            #expect(error as? SecureProfileStoreError == .corruptProfile)
        }
    }

    @Test func encryptedProfileBindsCiphertextToServiceIdentifierAndVersion() throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let first = makeSensitiveService()
        let secondID = UUID()
        let profile = makeSensitiveProfile(service: first)
        let key = Data(repeating: 0x63, count: 32)
        try fixture.profileStore.saveProfile(profile, key: key)

        var envelope = try jsonObject(at: fixture.profileURL(for: first.id))
        envelope["serviceID"] = secondID.uuidString
        try writeJSON(envelope, to: fixture.profileURL(for: secondID))
        do {
            _ = try fixture.profileStore.loadProfile(for: secondID, key: key)
            Issue.record("Ciphertext was accepted for a different engine")
        } catch {
            #expect(error as? SecureProfileStoreError == .corruptProfile)
        }

        envelope = try jsonObject(at: fixture.profileURL(for: first.id))
        envelope["version"] = 99
        try writeJSON(envelope, to: fixture.profileURL(for: first.id))
        do {
            _ = try fixture.profileStore.loadProfile(for: first.id, key: key)
            Issue.record("An unsupported profile envelope was accepted")
        } catch {
            #expect(error as? SecureProfileStoreError == .unsupportedEnvelopeVersion(99))
        }
    }

    @Test func protectingEngineRemovesSensitiveFieldsFromSharedSettingsAndLockScrubsMemory() async throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let service = makeSensitiveService()
        try fixture.writeSettings(service: service)
        let environment = fixture.makeEnvironment()

        await environment.enableProtection(for: service.id)
        #expect(environment.services.first?.isEncrypted == true)
        #expect(!environment.isServiceLocked(service.id))

        let plaintext = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
        for secret in sensitiveStrings {
            #expect(!plaintext.contains(secret))
        }
        #expect(plaintext.contains(service.name))

        environment.services[0].url = "https://private.example/unlocked-edit-9274"
        environment.services[0].customCSS = "/* unlocked-css-secret-9274 */"
        #expect(environment.save())
        let savedWhileUnlocked = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
        #expect(!savedWhileUnlocked.contains("unlocked-edit-9274"))
        #expect(!savedWhileUnlocked.contains("unlocked-css-secret-9274"))
        environment.services[0].url = sensitiveURL
        environment.services[0].customCSS = sensitiveCSS

        environment.lockService(service.id)
        #expect(environment.isServiceLocked(service.id))
        #expect(environment.services.first?.url.isEmpty == true)
        #expect(environment.persistedTabState.openTabs[service.id] == nil)
        #expect(environment.persistedTabState.tabTitles[service.id] == nil)
        #expect(environment.persistedTabState.tabInputs[service.id] == nil)
        #expect(environment.persistedTabState.tabPromptHistories[service.id] == nil)
        #expect(environment.persistedTabState.tabPromptHistoryEnabledOverrides[service.id] == nil)

        await environment.unlockService(service.id)
        #expect(!environment.isServiceLocked(service.id))
        #expect(environment.services.first?.url == sensitiveURL)
        #expect(environment.services.first?.customCSS == sensitiveCSS)
        #expect(environment.persistedTabState.tabInputs[service.id]?[2]?.text == sensitiveDraft)
        #expect(environment.persistedTabState.tabPromptHistories[service.id]?[2]?.first?.text == sensitivePrompt)
    }

    @Test func removingProtectionRestoresPlaintextOnlyAfterAuthentication() async throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let service = makeSensitiveService()
        try fixture.writeSettings(service: service)
        let environment = fixture.makeEnvironment()

        await environment.enableProtection(for: service.id)
        environment.lockService(service.id)
        await environment.disableProtection(for: service.id)

        #expect(environment.services.first?.isEncrypted == false)
        #expect(environment.services.first?.url == sensitiveURL)
        #expect(!fixture.keyStore.containsKey(for: service.id))
        #expect(!fixture.profileStore.containsProfile(for: service.id))
        let persisted = try persistedSettings(at: fixture.settingsURL)
        #expect(persisted.services.first?.url == sensitiveURL)
        #expect(persisted.persistedTabState?.tabInputs[service.id]?[2]?.text == sensitiveDraft)
    }

    @Test func failedProfileWriteRollsBackProtectionAndDeletesPreparedKey() async throws {
        let fixture = try SecurityFixture(profileStore: FailingSecureProfileStore())
        defer { fixture.remove() }
        let service = makeSensitiveService()
        try fixture.writeSettings(service: service)
        let environment = fixture.makeEnvironment()

        await environment.enableProtection(for: service.id)

        #expect(environment.services.first?.isEncrypted == false)
        #expect(!fixture.keyStore.containsKey(for: service.id))
        #expect(environment.securityError(for: service.id) != nil)
        let persisted = try persistedSettings(at: fixture.settingsURL)
        #expect(persisted.services.first?.url == sensitiveURL)
    }

    @Test func unavailableProtectedDataNeverOverwritesExistingSettings() throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let service = makeSensitiveService()
        try fixture.writeSettings(service: service)
        let originalData = try Data(contentsOf: fixture.settingsURL)
        let availability = ProtectedDataAvailability(isAvailable: false)

        let environment = fixture.makeEnvironment(
            isProtectedDataAvailable: { availability.isAvailable }
        )
        #expect(environment.startupState == .waitingForProtectedData)
        #expect(try Data(contentsOf: fixture.settingsURL) == originalData)

        availability.isAvailable = true
        environment.retryStartup()
        #expect(environment.startupState == .ready)
        #expect(environment.services.first?.id == service.id)
    }

    @Test func existingInstallRequiresOneSuccessfulWebsiteDataReset() async throws {
        let manager = SecurityWebsiteDataStoreManager()
        let fixture = try SecurityFixture(websiteDataStoreManager: manager)
        defer { fixture.remove() }
        try fixture.writeSettings(service: makeSensitiveService())
        let environment = fixture.makeEnvironment(requiresWebsiteDataMigration: true)

        #expect(environment.startupState == .needsWebsiteDataReset)
        #expect(manager.legacyResetCount == 0)
        await environment.completeWebsiteDataReset()

        #expect(manager.legacyResetCount == 1)
        #expect(environment.startupState == .ready)
        let object = try jsonObject(at: fixture.settingsURL)
        #expect(object["iosWebsiteDataStoreVersion"] as? Int == AppEnvironment.websiteDataStoreVersion)
    }

    @Test func newInstallRecordsIsolationVersionWithoutMigrationPrompt() throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let environment = fixture.makeEnvironment(requiresWebsiteDataMigration: true)

        #expect(environment.startupState == .ready)
        let object = try jsonObject(at: fixture.settingsURL)
        #expect(object["iosWebsiteDataStoreVersion"] as? Int == AppEnvironment.websiteDataStoreVersion)
    }

    @Test func newerWebsiteIsolationVersionNeverRetriggersDestructiveReset() throws {
        let manager = SecurityWebsiteDataStoreManager()
        let fixture = try SecurityFixture(websiteDataStoreManager: manager)
        defer { fixture.remove() }
        try fixture.writeSettings(service: makeSensitiveService())
        var settings = try jsonObject(at: fixture.settingsURL)
        settings["iosWebsiteDataStoreVersion"] = AppEnvironment.websiteDataStoreVersion + 1
        try writeJSON(settings, to: fixture.settingsURL)

        let environment = fixture.makeEnvironment(requiresWebsiteDataMigration: true)

        #expect(environment.startupState == .ready)
        #expect(manager.legacyResetCount == 0)
    }

    @Test func switchAwayAndInactivityPoliciesLockProtectedEngines() async throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        var service = makeSensitiveService()
        service.lockOnSwitchAway = false
        service.lockAfterInactivity = true
        service.autoLockInactivityTimeout = 1
        try fixture.writeSettings(service: service)
        let environment = fixture.makeEnvironment()

        await environment.enableProtection(for: service.id)
        environment.checkInactivityLocks(now: Date().addingTimeInterval(61))
        #expect(environment.isServiceLocked(service.id))

        await environment.unlockService(service.id)
        environment.services[0].lockOnSwitchAway = true
        environment.handleScenePhase(.background)
        #expect(environment.isPrivacyShieldVisible)
        #expect(environment.isServiceLocked(service.id))
        await environment.unlockService(service.id)
        #expect(environment.isServiceLocked(service.id))
        environment.handleScenePhase(.active)
        #expect(!environment.isPrivacyShieldVisible)
    }

    @Test func missingDeviceOnlyKeyNeverFallsBackToPlaintext() async throws {
        let fixture = try SecurityFixture()
        defer { fixture.remove() }
        let service = makeSensitiveService()
        try fixture.writeSettings(service: service)
        let environment = fixture.makeEnvironment()

        await environment.enableProtection(for: service.id)
        environment.lockService(service.id)
        try fixture.keyStore.removeKey(for: service.id)
        await environment.unlockService(service.id)

        #expect(environment.isServiceLocked(service.id))
        #expect(environment.services.first?.url.isEmpty == true)
        #expect(environment.securityError(for: service.id) != nil)
    }

    private func makeSensitiveService() -> Service {
        Service(
            name: "Protected Test Engine",
            url: sensitiveURL,
            focus_selector: sensitiveSelector,
            actionScripts: [UUID(): sensitiveScript],
            routingRules: [RoutingRule(pattern: "private.example", action: .internalStay)],
            customCSS: sensitiveCSS,
            iconBase64: Data("secret icon".utf8).base64EncodedString(),
            preservePrompt: true
        )
    }

    private func tamperWithCiphertext(at url: URL) throws {
        var envelope = try jsonObject(at: url)
        let encodedCiphertext = try #require(envelope["sealedProfile"] as? String)
        var ciphertext = try #require(Data(base64Encoded: encodedCiphertext))
        ciphertext[ciphertext.startIndex] ^= 0x01
        envelope["sealedProfile"] = ciphertext.base64EncodedString()
        try writeJSON(envelope, to: url)
    }
}

@MainActor
private final class SecurityFixture {
    let directoryURL: URL
    let settingsURL: URL
    let profileDirectoryURL: URL
    let keyStore = InMemoryEngineKeyStore()
    let websiteDataStoreManager: any WebsiteDataStoreManaging
    let profileStore: any SecureProfileStoring

    init(
        profileStore: (any SecureProfileStoring)? = nil,
        websiteDataStoreManager: (any WebsiteDataStoreManaging)? = nil
    ) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-security-tests-\(UUID().uuidString)", isDirectory: true)
        settingsURL = directoryURL.appendingPathComponent("settings.json")
        profileDirectoryURL = directoryURL.appendingPathComponent("profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.profileStore = profileStore ?? FileSecureProfileStore(directoryURL: profileDirectoryURL)
        self.websiteDataStoreManager = websiteDataStoreManager ?? SecurityWebsiteDataStoreManager()
    }

    func makeEnvironment(
        requiresWebsiteDataMigration: Bool = false,
        isProtectedDataAvailable: (() -> Bool)? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: websiteDataStoreManager,
            engineKeyStore: keyStore,
            secureProfileStore: profileStore,
            requiresWebsiteDataMigration: requiresWebsiteDataMigration,
            isProtectedDataAvailable: isProtectedDataAvailable,
            allowsNetworkWork: false
        )
    }

    func writeSettings(service: Service) throws {
        let profile = makeSensitiveProfile(service: service)
        let settings = PersistedSettings(
            services: [service],
            persistedTabState: PersistedTabState(
                activeServiceID: service.id,
                activeIndicesByID: [service.id: profile.tabState?.activeIndex ?? 0],
                openTabs: [service.id: profile.tabState?.openTabs ?? [:]],
                tabTitles: [service.id: profile.tabState?.tabTitles ?? [:]],
                tabInputs: [service.id: profile.tabState?.tabInputs ?? [:]],
                tabPromptHistories: [service.id: profile.tabState?.tabPromptHistories ?? [:]],
                tabPromptHistoryEnabledOverrides: [
                    service.id: profile.tabState?.tabPromptHistoryEnabledOverrides ?? [:]
                ]
            )
        )
        try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
    }

    func profileURL(for serviceID: UUID) -> URL {
        profileDirectoryURL.appendingPathComponent(serviceID.uuidString).appendingPathExtension("qprofile")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

@MainActor
private final class InMemoryEngineKeyStore: EngineKeyStoring {
    private var keys: [UUID: Data] = [:]

    func containsKey(for serviceID: UUID) -> Bool {
        keys[serviceID] != nil
    }

    func createKey(for serviceID: UUID, reason: String) async throws -> Data {
        if let key = keys[serviceID] { return key }
        let key = Data(repeating: UInt8(keys.count + 1), count: 32)
        keys[serviceID] = key
        return key
    }

    func retrieveKey(for serviceID: UUID, reason: String) async throws -> Data {
        guard let key = keys[serviceID] else { throw EngineKeyStoreError.keyMissing }
        return key
    }

    func removeKey(for serviceID: UUID) throws {
        keys[serviceID] = nil
    }
}

@MainActor
private final class SecurityWebsiteDataStoreManager: WebsiteDataStoreManaging {
    private(set) var legacyResetCount = 0
    private(set) var removedServiceIDs: [UUID] = []

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

@MainActor
private final class FailingSecureProfileStore: SecureProfileStoring {
    func containsProfile(for serviceID: UUID) -> Bool { false }

    func loadProfile(for serviceID: UUID, key: Data) throws -> IOSSecuredEngineProfile {
        throw SecureProfileStoreError.missingProfile
    }

    func saveProfile(_ profile: IOSSecuredEngineProfile, key: Data) throws {
        throw SecureProfileStoreError.verificationFailed
    }

    func removeProfile(for serviceID: UUID) throws { }
}

private final class ProtectedDataAvailability {
    var isAvailable: Bool

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }
}

private func jsonObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func persistedSettings(at url: URL) throws -> PersistedSettings {
    try JSONDecoder().decode(PersistedSettings.self, from: Data(contentsOf: url))
}

private func writeJSON(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
}

private func makeSensitiveProfile(service: Service) -> IOSSecuredEngineProfile {
    var state = PersistedTabState(activeServiceID: service.id)
    state.activeIndicesByID[service.id] = 2
    state.openTabs[service.id] = [2: sensitiveURL + "/conversation"]
    state.tabTitles[service.id] = [2: sensitiveTitle]
    state.tabInputs[service.id] = [
        2: TabInputState(text: sensitiveDraft, isContentEditable: false, start: 0, end: sensitiveDraft.count)
    ]
    state.tabPromptHistories[service.id] = [
        2: [PromptHistoryEntry(text: sensitivePrompt, timestamp: Date(timeIntervalSince1970: 1_000))]
    ]
    return IOSSecuredEngineProfile(service: service, state: state, includeTabState: true)
}

private let sensitiveURL = "https://private.example/account-token-9274"
private let sensitiveSelector = "#secret-composer"
private let sensitiveScript = "window.privateActionToken = 'script-secret-9274'"
private let sensitiveCSS = ".private-account { display: none } /* css-secret-9274 */"
private let sensitiveDraft = "draft-secret-9274"
private let sensitivePrompt = "prompt-secret-9274"
private let sensitiveTitle = "title-secret-9274"
private let sensitiveStrings = [
    sensitiveURL,
    sensitiveSelector,
    sensitiveScript,
    sensitiveCSS,
    sensitiveDraft,
    sensitivePrompt,
    sensitiveTitle
]
