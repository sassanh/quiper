import AppKit

enum ActionScriptStorage {
    static func scriptURL(serviceID: UUID, actionID: UUID) -> URL {
        EngineFileStorage.actionScriptURL(serviceID: serviceID, actionID: actionID)
    }

    static func revealInFinder(serviceID: UUID, actionID: UUID, contents: String) {
        EngineFileStorage.saveActionScript(contents, serviceID: serviceID, actionID: actionID)
        NSWorkspace.shared.activateFileViewerSelecting(
            [EngineFileStorage.actionScriptURL(serviceID: serviceID, actionID: actionID)]
        )
    }

    static func copyPath(serviceID: UUID, actionID: UUID, contents: String) {
        EngineFileStorage.saveActionScript(contents, serviceID: serviceID, actionID: actionID)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            EngineFileStorage.actionScriptURL(serviceID: serviceID, actionID: actionID).path,
            forType: .string
        )
    }

    static func loadScript(serviceID: UUID, actionID: UUID, fallback: String) -> String {
        EngineFileStorage.loadActionScript(serviceID: serviceID, actionID: actionID, fallback: fallback)
    }

    static func saveScript(_ script: String, serviceID: UUID, actionID: UUID) {
        EngineFileStorage.saveActionScript(script, serviceID: serviceID, actionID: actionID)
    }

    static func openInDefaultEditor(serviceID: UUID, actionID: UUID, contents: String) {
        EngineFileStorage.saveActionScript(contents, serviceID: serviceID, actionID: actionID)
        NSWorkspace.shared.open(
            EngineFileStorage.actionScriptURL(serviceID: serviceID, actionID: actionID)
        )
    }

    static func deleteScript(serviceID: UUID, actionID: UUID) {
        EngineFileStorage.deleteActionScript(serviceID: serviceID, actionID: actionID)
    }

    static func deleteScripts(for serviceID: UUID) {
        EngineFileStorage.deleteActionScripts(for: serviceID)
    }

    static func deleteAllScripts() {
        EngineFileStorage.deleteAllActionScripts()
    }
}
