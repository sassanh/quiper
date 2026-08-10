import CryptoKit
import Foundation

struct IOSSecuredEngineMetadata: Codable, Equatable {
    var url: String
    var focusSelector: String
    var actionScripts: [UUID: String]
    var customCSS: String?
    var routingRules: [RoutingRule]
    var iconBase64: String?
    var iconManuallyUnset: Bool?
    var preservePrompt: Bool
    var templateActionScriptSync: [UUID: Bool]
    var templatePromptInputSelectorSync: Bool
    var templateCustomCSSSync: Bool

    init(service: Service) {
        url = service.url
        focusSelector = service.focus_selector
        actionScripts = service.actionScripts
        customCSS = service.customCSS
        routingRules = service.routingRules
        iconBase64 = service.iconBase64
        iconManuallyUnset = service.iconManuallyUnset
        preservePrompt = service.preservePrompt
        templateActionScriptSync = service.templateActionScriptSync
        templatePromptInputSelectorSync = service.templatePromptInputSelectorSync
        templateCustomCSSSync = service.templateCustomCSSSync
    }

    func applying(to service: Service) -> Service {
        var service = service
        service.url = url
        service.focus_selector = focusSelector
        service.actionScripts = actionScripts
        service.customCSS = customCSS
        service.routingRules = routingRules
        service.iconBase64 = iconBase64
        service.iconManuallyUnset = iconManuallyUnset
        service.preservePrompt = preservePrompt
        service.templateActionScriptSync = templateActionScriptSync
        service.templatePromptInputSelectorSync = templatePromptInputSelectorSync
        service.templateCustomCSSSync = templateCustomCSSSync
        return service
    }
}

struct IOSSecuredTabState: Codable, Equatable {
    var activeIndex: Int?
    var openTabs: [Int: String]
    var tabTitles: [Int: String]
    var tabInputs: [Int: TabInputState]
    var tabPromptHistories: [Int: [PromptHistoryEntry]]
    var tabPromptHistoryEnabledOverrides: [Int: Bool]

    init(serviceID: UUID, state: PersistedTabState) {
        activeIndex = state.activeIndicesByID[serviceID]
        openTabs = state.openTabs[serviceID] ?? [:]
        tabTitles = state.tabTitles[serviceID] ?? [:]
        tabInputs = state.tabInputs[serviceID] ?? [:]
        tabPromptHistories = state.tabPromptHistories[serviceID] ?? [:]
        tabPromptHistoryEnabledOverrides = state.tabPromptHistoryEnabledOverrides[serviceID] ?? [:]
    }

    func applying(to state: inout PersistedTabState, serviceID: UUID) {
        state.activeIndicesByID[serviceID] = activeIndex
        state.openTabs[serviceID] = openTabs
        state.tabTitles[serviceID] = tabTitles
        state.tabInputs[serviceID] = tabInputs
        state.tabPromptHistories[serviceID] = tabPromptHistories
        state.tabPromptHistoryEnabledOverrides[serviceID] = tabPromptHistoryEnabledOverrides
    }
}

struct IOSSecuredEngineProfile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var serviceID: UUID
    var metadata: IOSSecuredEngineMetadata
    var tabState: IOSSecuredTabState?

    init(service: Service, state: PersistedTabState, includeTabState: Bool) {
        schemaVersion = Self.currentSchemaVersion
        serviceID = service.id
        metadata = IOSSecuredEngineMetadata(service: service)
        tabState = includeTabState ? IOSSecuredTabState(serviceID: service.id, state: state) : nil
    }
}

enum SecureProfileStoreError: LocalizedError, Equatable {
    case invalidKey
    case missingProfile
    case unsupportedEnvelopeVersion(Int)
    case unsupportedProfileVersion(Int)
    case serviceMismatch
    case corruptProfile
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "The protected engine key is invalid."
        case .missingProfile:
            "The protected engine data is missing."
        case .unsupportedEnvelopeVersion:
            "This protected engine was written by an unsupported version of Quiper."
        case .unsupportedProfileVersion:
            "This protected engine profile uses an unsupported format."
        case .serviceMismatch:
            "The protected engine data belongs to a different engine."
        case .corruptProfile:
            "The protected engine data is damaged or has been modified."
        case .verificationFailed:
            "Quiper could not verify the protected engine after saving it."
        }
    }
}

protocol SecureProfileStoring {
    func containsProfile(for serviceID: UUID) -> Bool
    func loadProfile(for serviceID: UUID, key: Data) throws -> IOSSecuredEngineProfile
    func saveProfile(_ profile: IOSSecuredEngineProfile, key: Data) throws
    func removeProfile(for serviceID: UUID) throws
}

final class FileSecureProfileStore: SecureProfileStoring {
    private struct Envelope: Codable {
        static let currentVersion = 1

        var version: Int
        var serviceID: UUID
        var sealedProfile: Data
    }

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func containsProfile(for serviceID: UUID) -> Bool {
        fileManager.fileExists(atPath: profileURL(for: serviceID).path)
    }

    func loadProfile(for serviceID: UUID, key: Data) throws -> IOSSecuredEngineProfile {
        guard key.count == 32 else { throw SecureProfileStoreError.invalidKey }
        let url = profileURL(for: serviceID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SecureProfileStoreError.missingProfile
        }

        do {
            let data = try Data(contentsOf: url)
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.version == Envelope.currentVersion else {
                throw SecureProfileStoreError.unsupportedEnvelopeVersion(envelope.version)
            }
            guard envelope.serviceID == serviceID else {
                throw SecureProfileStoreError.serviceMismatch
            }
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedProfile)
            let plaintext = try AES.GCM.open(
                sealedBox,
                using: SymmetricKey(data: key),
                authenticating: authenticatedData(for: serviceID)
            )
            let profile = try decoder.decode(IOSSecuredEngineProfile.self, from: plaintext)
            guard profile.schemaVersion == IOSSecuredEngineProfile.currentSchemaVersion else {
                throw SecureProfileStoreError.unsupportedProfileVersion(profile.schemaVersion)
            }
            guard profile.serviceID == serviceID else {
                throw SecureProfileStoreError.serviceMismatch
            }
            return profile
        } catch let error as SecureProfileStoreError {
            throw error
        } catch {
            throw SecureProfileStoreError.corruptProfile
        }
    }

    func saveProfile(_ profile: IOSSecuredEngineProfile, key: Data) throws {
        guard key.count == 32 else { throw SecureProfileStoreError.invalidKey }
        guard profile.schemaVersion == IOSSecuredEngineProfile.currentSchemaVersion else {
            throw SecureProfileStoreError.unsupportedProfileVersion(profile.schemaVersion)
        }
        try prepareDirectory()

        let plaintext = try encoder.encode(profile)
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            authenticating: authenticatedData(for: profile.serviceID)
        )
        guard let combined = sealedBox.combined else {
            throw SecureProfileStoreError.verificationFailed
        }
        let envelope = Envelope(
            version: Envelope.currentVersion,
            serviceID: profile.serviceID,
            sealedProfile: combined
        )
        let data = try encoder.encode(envelope)
        let url = profileURL(for: profile.serviceID)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(url)

        guard try loadProfile(for: profile.serviceID, key: key) == profile else {
            throw SecureProfileStoreError.verificationFailed
        }
    }

    func removeProfile(for serviceID: UUID) throws {
        let url = profileURL(for: serviceID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directoryURL.path
        )
        try excludeFromBackup(directoryURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func profileURL(for serviceID: UUID) -> URL {
        directoryURL.appendingPathComponent(serviceID.uuidString).appendingPathExtension("qprofile")
    }

    private func authenticatedData(for serviceID: UUID) -> Data {
        Data("quiper.ios.secure-engine.v1:\(serviceID.uuidString)".utf8)
    }
}
