import XCTest
@testable import Quiper

@MainActor
final class SecureStorageManagerTests: XCTestCase {

    // MARK: - generateRandomKey Tests

    func testGenerateRandomKey_ReturnsValidLength() {
        let key1 = SecureStorageManager.shared.generateRandomKey()
        let key2 = SecureStorageManager.shared.generateRandomKey()

        // 256 bits = 32 bytes = 64 hex characters
        XCTAssertEqual(key1.count, 64)
        XCTAssertEqual(key2.count, 64)

        // Ensure randomness (very low probability of collision)
        XCTAssertNotEqual(key1, key2)
    }

    func testGenerateRandomKey_ReturnsValidHex() {
        let key = SecureStorageManager.shared.generateRandomKey()

        // Ensure string only contains valid hex characters
        let validHexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let keyCharacterSet = CharacterSet(charactersIn: key)

        XCTAssertTrue(validHexCharacterSet.isSuperset(of: keyCharacterSet), "Generated key contains non-hex characters")
    }

    // MARK: - KeychainError Mapping Tests

    func testKeychainError_ItemNotFound_ErrorDescription() {
        let error = SecureStorageManager.KeychainError.itemNotFound
        let expectedMessage = "The encryption key was not found in the Keychain. Please toggle 'Encrypt Engine Local Storage' off and then back on in Settings to regenerate it."
        
        XCTAssertEqual(error.errorDescription, expectedMessage)
    }

    func testKeychainError_AuthenticationFailed_ErrorDescription() {
        let reason = "Biometry is locked out."
        let error = SecureStorageManager.KeychainError.authenticationFailed(reason)
        let expectedMessage = "Biometric authentication failed: Biometry is locked out."
        
        XCTAssertEqual(error.errorDescription, expectedMessage)
    }

    func testKeychainError_Unknown_ErrorDescription() {
        let status: OSStatus = -25293 // errSecAuthFailed
        let error = SecureStorageManager.KeychainError.unknown(status)
        let expectedMessage = "Keychain error: -25293"
        
        XCTAssertEqual(error.errorDescription, expectedMessage)
    }
}
