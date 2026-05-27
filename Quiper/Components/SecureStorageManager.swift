import Foundation
import Security
import LocalAuthentication
import AppKit

@MainActor
final class SecureStorageManager {
    static let shared = SecureStorageManager()
    
    private init() {}
    
    /// Generates a cryptographically secure 256-bit symmetric key, encoded as a hex string.
    func generateRandomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Saves an encryption key to the macOS Keychain, protected by system-level encryption.
    /// We enforce biometrics strictly in code via LAContext.evaluatePolicy before retrieval.
    func saveKeyToKeychain(_ key: String, for serviceID: UUID) -> Bool {
        let serviceName = "com.quiper.enginekey.\(serviceID.uuidString)"
        guard let keyData = key.data(using: .utf8) else { return false }
        
        // First delete any old key
        deleteKeyFromKeychain(for: serviceID)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "quiper",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        NSLog("[SecureStorage] saveKeyToKeychain status: %d (0 = success) for service %@", status, serviceID.uuidString)
        return status == errSecSuccess
    }
    
    enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case authenticationFailed(String)
        case unknown(OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The encryption key was not found in the Keychain. Please toggle 'Encrypt Engine Local Storage' off and then back on in Settings to regenerate it."
            case .authenticationFailed(let reason):
                return "Biometric authentication failed: \(reason)"
            case .unknown(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    /// Retrieves the encryption key from the macOS Keychain.
    /// Uses LAContext.evaluatePolicy to show Touch ID prompt asynchronously.
    func retrieveKeyFromKeychain(for serviceID: UUID, context: LAContext? = nil) async throws -> String {
        defer {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.keyWindow?.makeKeyAndOrderFront(nil)
            }
        }
        let serviceName = "com.quiper.enginekey.\(serviceID.uuidString)"
        
        let authContext = context ?? LAContext()
        
        // Step 1: Authenticate via Touch ID / Passcode asynchronously if no pre-authenticated context is supplied
        if context == nil {
            do {
                try await authContext.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authorize access to secure engine local storage"
                )
                NSLog("[SecureStorage] LAContext authentication succeeded")
            } catch {
                NSLog("[SecureStorage] LAContext authentication failed: %@", error.localizedDescription)
                throw KeychainError.authenticationFailed(error.localizedDescription)
            }
        }
        
        // Step 2: Fetch the key from the Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "quiper",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        NSLog("[SecureStorage] SecItemCopyMatching status: %d (0 = success)", status)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            NSLog("[SecureStorage] Key retrieved successfully (%d bytes)", data.count)
            return String(data: data, encoding: .utf8) ?? ""
        } else if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        } else if status == -128 { // errSecUserCanceled
            throw KeychainError.authenticationFailed("Keychain access denied by user")
        } else {
            throw KeychainError.unknown(status)
        }
    }
    
    /// Deletes the key from the macOS Keychain when encryption is turned off or engine is deleted.
    func deleteKeyFromKeychain(for serviceID: UUID) {
        let serviceName = "com.quiper.enginekey.\(serviceID.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "quiper"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// Checks if a key already exists in the Keychain for this service.
    func hasKeyInKeychain(for serviceID: UUID) -> Bool {
        let serviceName = "com.quiper.enginekey.\(serviceID.uuidString)"
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "quiper",
            kSecUseAuthenticationContext as String: context
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        NSLog("[SecureStorage] hasKeyInKeychain status: %d (0 = exists, -25308 = exists+needs auth, -25300 = not found) for service %@", status, serviceID.uuidString)
        return status == errSecSuccess || status == errSecInteractionRequired || status == -25308
    }
}
