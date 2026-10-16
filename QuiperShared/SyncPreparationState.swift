import Foundation
import Combine

@MainActor
final class SyncPreparationState: ObservableObject {
    static let shared = SyncPreparationState()
    private init() {}

    /// Which long-running job the preparation fallback is presenting, so
    /// callers never encode the job inside the detail string.
    enum Stage: Equatable {
        /// Enumerating engines before packaging.
        case readingEngines
        /// Inlining file-backed scripts and encoding the snapshot payload.
        case packagingSnapshot
        /// Decrypting protected engines ahead of packaging.
        case unlockingEngines
        /// Local network advertisement/startup after the snapshot is ready.
        case startingLocalNetwork
        /// Snapshot encoded, handing off to the share sheet.
        case startingShare

        /// Headline shown in the fallback's long-wait panel. Stages without
        /// a headline render their detail as a single plain line.
        var headline: String? {
            switch self {
            case .packagingSnapshot: "Packaging snapshot —"
            default: nil
            }
        }
    }

    struct Status: Equatable {
        let stage: Stage
        /// Detail line rendered below the headline, or as the single line
        /// when the stage has none. Presented verbatim; the headline never
        /// belongs in this string.
        let detail: String?
    }

    @Published var status: Status? = nil

    func set(_ stage: Stage, _ detail: String? = nil) {
        status = Status(stage: stage, detail: detail)
    }

    func clear() {
        status = nil
    }
}
