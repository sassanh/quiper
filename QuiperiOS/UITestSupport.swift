import Foundation

enum UITestSupport {
    static let launchArgument = "--ui-testing"

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(launchArgument)
        #else
        false
        #endif
    }

    @MainActor
    static func makeEnvironment() -> AppEnvironment {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-ui-tests-\(ProcessInfo.processInfo.processIdentifier).json")
        try? FileManager.default.removeItem(at: settingsURL)

        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false
        )
        let service = Service(
            id: UUID(uuidString: "F0A38C27-2DB2-4922-9D52-0C94575CBA31")!,
            name: "UI Test Engine",
            url: localPageURL,
            focus_selector: "#prompt"
        )
        environment.services = [service]
        environment.customActions = []
        environment.tabNavigationRingSize = 3
        environment.persistedTabState = PersistedTabState(
            activeServiceID: service.id,
            activeIndicesByID: [service.id: 0],
            openTabs: [service.id: [0: localPageURL, 1: localPageURL, 2: localPageURL]],
            tabTitles: [service.id: [0: "First", 1: "Second", 2: "Third"]],
            tabHistory: [
                TabIdentifier(serviceID: service.id, sessionIndex: 1),
                TabIdentifier(serviceID: service.id, sessionIndex: 2)
            ]
        )
        environment.save()
        return environment
    }

    private static let localPageURL: String = {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Quiper UI Test Page</title>
            <style>
              body { font: 20px -apple-system; padding: 24px; }
              input { font: inherit; width: 90%; padding: 12px; }
              .spacer { height: 900px; }
            </style>
          </head>
          <body>
            <label for="prompt">Test prompt</label>
            <input id="prompt" aria-label="Test prompt" type="text">
            <p>needle first</p>
            <div class="spacer"></div>
            <p>needle second</p>
          </body>
        </html>
        """
        return "data:text/html;base64,\(Data(html.utf8).base64EncodedString())"
    }()
}
