import Foundation
import LocalAuthentication
import Security

enum EngineKeyStoreError: LocalizedError, Equatable {
    case deviceAuthenticationUnavailable
    case authenticationCancelled
    case keyMissing
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceAuthenticationUnavailable:
            "A device passcode is required before an engine can be protected."
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .keyMissing:
            "The device-only key for this engine is missing and cannot be recovered."
        case .unexpectedStatus:
            "The protected engine key could not be accessed."
        }
    }
}

protocol EngineKeyStoring {
    func containsKey(for serviceID: UUID) -> Bool
    func createKey(for serviceID: UUID, reason: String) async throws -> Data
    func retrieveKey(for serviceID: UUID, reason: String) async throws -> Data
    func removeKey(for serviceID: UUID) throws
}

final class IOSKeychainEngineKeyStore: EngineKeyStoring {
    static let shared = IOSKeychainEngineKeyStore()

    private let serviceName: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.QuiperiOS") {
        serviceName = bundleIdentifier + ".secure-engine-key"
    }

    func containsKey(for serviceID: UUID) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(for: serviceID)
        query[kSecReturnData as String] = false
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func createKey(for serviceID: UUID, reason: String) async throws -> Data {
        let context = try await authenticatedContext(reason: reason)
        if containsKey(for: serviceID) {
            return try retrieveKey(using: context, for: serviceID)
        }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw EngineKeyStoreError.unexpectedStatus(randomStatus)
        }
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .userPresence,
            &accessControlError
        ) else {
            throw EngineKeyStoreError.deviceAuthenticationUnavailable
        }

        var query = baseQuery(for: serviceID)
        query[kSecValueData as String] = key
        query[kSecAttrAccessControl as String] = accessControl
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return try retrieveKey(using: context, for: serviceID)
        }
        guard status == errSecSuccess else {
            throw mapStatus(status)
        }
        return key
    }

    func retrieveKey(for serviceID: UUID, reason: String) async throws -> Data {
        let context = try await authenticatedContext(reason: reason)
        return try retrieveKey(using: context, for: serviceID)
    }

    func removeKey(for serviceID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: serviceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mapStatus(status)
        }
    }

    private func authenticatedContext(reason: String) async throws -> LAContext {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw EngineKeyStoreError.deviceAuthenticationUnavailable
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return context
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            throw EngineKeyStoreError.authenticationCancelled
        } catch {
            throw EngineKeyStoreError.deviceAuthenticationUnavailable
        }
    }

    private func retrieveKey(using context: LAContext, for serviceID: UUID) throws -> Data {
        var query = baseQuery(for: serviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw mapStatus(status)
        }
        guard let key = result as? Data, key.count == 32 else {
            throw EngineKeyStoreError.keyMissing
        }
        return key
    }

    private func baseQuery(for serviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serviceID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func mapStatus(_ status: OSStatus) -> EngineKeyStoreError {
        switch status {
        case errSecItemNotFound:
            .keyMissing
        case errSecUserCanceled, errSecAuthFailed:
            .authenticationCancelled
        default:
            .unexpectedStatus(status)
        }
    }
}
