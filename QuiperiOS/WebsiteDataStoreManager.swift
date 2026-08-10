import Foundation
import WebKit

@MainActor
protocol WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore
    func resetLegacyDefaultStore() async
    func removeDataStore(for serviceID: UUID) async throws
}

@MainActor
final class DefaultWebsiteDataStoreManager: WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: serviceID)
    }

    func resetLegacyDefaultStore() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    func removeDataStore(for serviceID: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: serviceID) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
