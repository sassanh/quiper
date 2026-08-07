import Foundation

/// Snapshot of the engine input field posted by the shared tracker script
/// (`WebScripts.makeInputStateTrackerScript`). Owns the WebKit message parsing
/// so macOS and iOS never drift apart on the payload shape.
struct InputStatePayload {
    var text: String
    var isContentEditable: Bool
    var start: Int
    var end: Int
    var wasSent: Bool
    var wasSentText: String
    var clearType: String

    init(_ dict: [String: Any]) {
        text = dict["text"] as? String ?? ""
        isContentEditable = dict["isContentEditable"] as? Bool ?? false
        start = dict["start"] as? Int ?? 0
        end = dict["end"] as? Int ?? 0
        wasSent = dict["wasSent"] as? Bool ?? false
        wasSentText = dict["wasSentText"] as? String ?? ""
        clearType = dict["clearType"] as? String ?? "submit"
    }
}
