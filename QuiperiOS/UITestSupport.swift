import Foundation
import WebKit

enum UITestSupport {
    static let launchArgument = "--ui-testing"
    static let launchEnvironmentKey = "QUIPER_UI_TESTING"
    static let protectedEngineLaunchArgument = "--ui-testing-protected-engine"
    static let hardwareKeyboardSeenLaunchArgument = "--ui-testing-hardware-keyboard-seen"
    static let hardwareKeyboardConnectedLaunchArgument = "--ui-testing-hardware-keyboard-connected"

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.environment[launchEnvironmentKey] == "1"
        #else
        false
        #endif
    }

    static var isUnitTestHost: Bool {
        #if DEBUG
        guard !isEnabled else { return false }
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    @MainActor
    static func makeUnitTestHostEnvironment() -> AppEnvironment {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quiper-ios-unit-test-host-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let settingsURL = directoryURL.appendingPathComponent("settings.json")
        let settings = PersistedSettings(
            services: [],
            customActions: [],
            autoCreateSessionOnEmptyEngineActivation: false,
            shouldPurgeDanglingWebData: false,
            persistedTabState: PersistedTabState()
        )
        try? JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)

        return AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            requiresWebsiteDataMigration: false,
            isProtectedDataAvailable: { true },
            allowsNetworkWork: false
        )
    }

    @MainActor
    static func makeEnvironment() -> AppEnvironment {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quiper-ios-ui-tests-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: directoryURL)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let settingsURL = directoryURL.appendingPathComponent("settings.json")
        let profileStore = FileSecureProfileStore(
            directoryURL: directoryURL.appendingPathComponent("profiles", isDirectory: true)
        )
        let keyStore = UITestEngineKeyStore()
        let service = Service(
            id: UUID(uuidString: "F0A38C27-2DB2-4922-9D52-0C94575CBA31")!,
            name: "UI Test Engine",
            url: localPageURL,
            focus_selector: "#prompt"
        )
        let tabState = PersistedTabState(
            activeServiceID: service.id,
            activeIndicesByID: [service.id: 0],
            openTabs: [service.id: [0: localPageURL, 1: localPageURL, 2: localPageURL]],
            tabTitles: [service.id: [0: "First", 1: "Second", 2: "Third"]],
            tabHistory: [
                TabIdentifier(serviceID: service.id, sessionIndex: 1),
                TabIdentifier(serviceID: service.id, sessionIndex: 2)
            ]
        )
        let startsProtected = ProcessInfo.processInfo.arguments.contains(protectedEngineLaunchArgument)
        let keyboardSeen = ProcessInfo.processInfo.arguments.contains(hardwareKeyboardSeenLaunchArgument)
        let keyboardConnected = ProcessInfo.processInfo.arguments.contains(
            hardwareKeyboardConnectedLaunchArgument
        )
        var persistedService = service
        var persistedTabState = tabState
        if startsProtected {
            let key = Data(repeating: 0xA7, count: 32)
            keyStore.setKey(key, for: service.id)
            try? profileStore.saveProfile(
                IOSSecuredEngineProfile(service: service, state: tabState, includeTabState: true),
                key: key
            )
            persistedService.isEncrypted = true
            persistedService.hasMigratedMetadata = true
            persistedTabState = PersistedTabState(activeServiceID: service.id)
        }
        let settings = PersistedSettings(
            services: [persistedService],
            customActions: [],
            persistedTabState: persistedTabState,
            tabNavigationRingSize: 3,
            iosHardwareKeyboardSettings: IOSHardwareKeyboardSettings(
                hasSeenHardwareKeyboard: keyboardSeen || keyboardConnected
            )
        )
        try? JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)

        return AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: UITestWebsiteDataStoreManager(),
            engineKeyStore: keyStore,
            secureProfileStore: profileStore,
            isProtectedDataAvailable: { true },
            hardwareKeyboardMonitor: UITestHardwareKeyboardMonitor(isConnected: keyboardConnected)
        )
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
            <input id="prompt" aria-label="Test prompt" type="text" autofocus>
            <p id="focus-state">not focused</p>
            <p>needle first</p>
            <div class="spacer"></div>
            <p>needle second</p>
            <script>
              document.getElementById("prompt").addEventListener("focus", () => {
                document.getElementById("focus-state").textContent = "prompt focused";
              });
            </script>
          </body>
        </html>
        """
        return "data:text/html;base64,\(Data(html.utf8).base64EncodedString())"
    }()
}

@MainActor
private final class UITestHardwareKeyboardMonitor: HardwareKeyboardMonitoring {
    let isConnected: Bool
    var onConnectionChanged: ((Bool) -> Void)?

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    func start() { }
}

@MainActor
private final class UITestEngineKeyStore: EngineKeyStoring {
    private var keys: [UUID: Data] = [:]

    func setKey(_ key: Data, for serviceID: UUID) {
        keys[serviceID] = key
    }

    func containsKey(for serviceID: UUID) -> Bool {
        keys[serviceID] != nil
    }

    func createKey(for serviceID: UUID, reason: String) async throws -> Data {
        if let key = keys[serviceID] { return key }
        let key = Data(repeating: 0xB4, count: 32)
        keys[serviceID] = key
        return key
    }

    func retrieveKey(for serviceID: UUID, reason: String) async throws -> Data {
        guard let key = keys[serviceID] else { throw EngineKeyStoreError.keyMissing }
        return key
    }

    func removeKey(for serviceID: UUID) throws {
        keys[serviceID] = nil
    }
}

@MainActor
private final class UITestWebsiteDataStoreManager: WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore.nonPersistent()
    }

    func resetLegacyDefaultStore() async { }

    func removeDataStore(for serviceID: UUID) async throws { }
}
