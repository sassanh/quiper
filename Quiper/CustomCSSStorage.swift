import AppKit

@MainActor
enum CustomCSSStorage {
    static func cssURL(serviceID: UUID) -> URL {
        EngineFileStorage.customCSSURL(serviceID: serviceID)
    }

    static func revealInFinder(serviceID: UUID, contents: String) {
        EngineFileStorage.saveCustomCSS(contents, serviceID: serviceID)
        NSWorkspace.shared.activateFileViewerSelecting(
            [EngineFileStorage.customCSSURL(serviceID: serviceID)]
        )
    }

    static func copyPath(serviceID: UUID, contents: String) {
        EngineFileStorage.saveCustomCSS(contents, serviceID: serviceID)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            EngineFileStorage.customCSSURL(serviceID: serviceID).path,
            forType: .string
        )
    }

    static func loadCSS(serviceID: UUID, fallback: String) -> String {
        EngineFileStorage.loadCustomCSS(serviceID: serviceID, fallback: fallback)
    }

    static func saveCSS(_ css: String, serviceID: UUID) {
        EngineFileStorage.saveCustomCSS(css, serviceID: serviceID)
    }

    static func openInDefaultEditor(serviceID: UUID, contents: String) {
        EngineFileStorage.saveCustomCSS(contents, serviceID: serviceID)
        NSWorkspace.shared.open(EngineFileStorage.customCSSURL(serviceID: serviceID))
    }

    static func deleteCSS(for serviceID: UUID) {
        EngineFileStorage.deleteCustomCSS(for: serviceID)
    }

    static func deleteAllCSS() {
        EngineFileStorage.deleteAllCustomCSS()
    }
}
