import Foundation
import Combine

@MainActor
final class SyncPreparationState: ObservableObject {
    static let shared = SyncPreparationState()
    private init() {}

    @Published var detail: String? = nil

    func set(_ text: String?) {
        detail = text
    }
}
