import AppIntents
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import QuiperiOS

@MainActor
@Suite(.serialized)
struct IOSKeyboardAndIntentTests {
    @Test func keyboardSettingsDefaultsAndExplicitClearingAreStable() throws {
        let defaults = IOSHardwareKeyboardSettings.defaults
        #expect(defaults.version == 1)
        #expect(defaults.binding(for: .nextSession).primary == .init(
            IOSHardwareKeyboardSettings.rightArrowInput,
            modifiers: [.command, .shift]
        ))
        #expect(defaults.binding(for: .nextEngine).primary == .init(
            IOSHardwareKeyboardSettings.rightArrowInput,
            modifiers: [.command, .control]
        ))
        #expect(defaults.binding(for: .lockCurrentEngine).primary == .init(
            "l",
            modifiers: [.command, .option]
        ))
        #expect(defaults.sessionDigitModifiers.primary == .command)
        #expect(defaults.engineDigitModifiers.primary == [.command, .control])
        #expect(defaults.actionShortcut(for: DefaultEngineDefinitions.newSessionActionID) == .init(
            "n",
            modifiers: .command
        ))
        #expect(defaults.actionShortcut(for: DefaultEngineDefinitions.newTemporarySessionActionID) == .init(
            "n",
            modifiers: [.command, .shift]
        ))
        #expect(defaults.actionShortcut(for: DefaultEngineDefinitions.shareActionID) == .init(
            "s",
            modifiers: [.command, .shift]
        ))
        #expect(defaults.actionShortcut(for: DefaultEngineDefinitions.historyActionID) == .init(
            "h",
            modifiers: [.command, .shift]
        ))
        #expect(defaults.actionShortcut(for: DefaultEngineDefinitions.openSettingsActionID) == .init(
            ",",
            modifiers: .command
        ))

        let actionID = UUID()
        var settings = defaults
        settings.commandBindings[.nextSession]?.primary = nil
        settings.actionBindings[actionID] = IOSKeyboardShortcutOverride(nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let firstData = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(IOSHardwareKeyboardSettings.self, from: firstData)
        let secondData = try encoder.encode(decoded)

        #expect(decoded.binding(for: .nextSession).primary == nil)
        #expect(decoded.actionBindings[actionID] == IOSKeyboardShortcutOverride(nil))
        #expect(firstData == secondData)

        var partialSource = defaults
        partialSource.hasSeenHardwareKeyboard = true
        partialSource.commandBindings = [.nextSession: IOSDualKeyboardBinding()]
        let partial = try JSONDecoder().decode(
            IOSHardwareKeyboardSettings.self,
            from: encoder.encode(partialSource)
        )
        #expect(partial.hasSeenHardwareKeyboard)
        #expect(partial.binding(for: .nextSession).primary == nil)
        #expect(partial.binding(for: .nextEngine) == defaults.binding(for: .nextEngine))
        #expect(partial.actionBindings == defaults.actionBindings)
    }

    @Test func shortcutValidationRejectsUnsafeAndConflictingBindings() {
        let action = CustomAction(id: UUID(), name: "Custom")
        let engine = makeService(name: "Engine")
        var settings = IOSHardwareKeyboardSettings.defaults
        settings.actionBindings[action.id] = IOSKeyboardShortcutOverride(
            IOSKeyboardShortcut("1", modifiers: .command)
        )

        #expect(IOSKeyboardShortcutValidator.validate(
            .init("x", modifiers: []),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .modifierRequired)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("h", modifiers: .command),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .systemReserved)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("f", modifiers: .command),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .fixedCommand("Find in Page"))
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("1", modifiers: .command),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .duplicate("Session Selection"))
        #expect(IOSKeyboardShortcutValidator.validateDigitModifiers(
            .command,
            replacing: .engineDigits(.primary),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) != nil)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init(IOSHardwareKeyboardSettings.rightArrowInput, modifiers: []),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .modifierRequired)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("x", modifiers: .shift),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .modifierRequired)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("\u{F704}", modifiers: []),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == nil)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("k", modifiers: [.control, .option]),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .systemReserved)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("4", modifiers: [.command, .shift]),
            replacing: .engine(engine.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .systemReserved)
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("l", modifiers: [.command, .option, .shift]),
            replacing: .action(action.id),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .duplicate("Lock All Protected Engines"))
        #expect(IOSKeyboardShortcutValidator.validate(
            .init("k", modifiers: [.command, .option, .shift]),
            replacing: .command(.lockCurrentEngine, .primary),
            settings: settings,
            actions: [action],
            engines: [engine]
        ) == .duplicate("Lock All Protected Engines"))
    }

    @Test func keyboardDetectionIsProgressiveAndPersistsAfterDisconnect() throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let monitor = TestHardwareKeyboardMonitor(isConnected: false)
        let environment = fixture.makeEnvironment(monitor: monitor)

        #expect(!environment.isHardwareKeyboardConnected)
        #expect(!environment.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard)

        monitor.setConnected(true)
        #expect(environment.isHardwareKeyboardConnected)
        #expect(environment.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard)

        monitor.setConnected(false)
        #expect(!environment.isHardwareKeyboardConnected)
        #expect(environment.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard)

        let reloaded = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        #expect(reloaded.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard)
        #expect(!reloaded.isHardwareKeyboardConnected)
    }

    @Test func initiallyConnectedKeyboardIsDetectedWithoutWaitingForNotification() throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: true)
        )

        #expect(environment.isHardwareKeyboardConnected)
        #expect(environment.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard)
    }

    @Test func iosSavePreservesNestedMacShortcutsAndPrunesOrphans() throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let service = makeService()
        let action = CustomAction(id: UUID(), name: "Action")
        var object = try jsonObject(
            from: PersistedSettings(services: [service], customActions: [action])
        )
        object["services"] = [[
            "id": service.id.uuidString.lowercased(),
            "name": service.name,
            "url": service.url,
            "focus_selector": service.focus_selector,
            "activationShortcut": ["keyCode": 7, "modifierFlags": 1]
        ]]
        object["customActions"] = [[
            "id": action.id.uuidString.lowercased(),
            "name": action.name,
            "shortcut": ["keyCode": 8, "modifierFlags": 2]
        ]]
        object["hotkey"] = ["keyCode": 42, "modifierFlags": 1]
        object["appShortcuts"] = ["nextSession": ["keyCode": 124, "modifierFlags": 9]]
        object["futureMacField"] = ["nested": [1, 2, 3]]
        try writeJSON(object, to: fixture.settingsURL)

        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        environment.iosHardwareKeyboardSettings.engineBindings[service.id] =
            IOSKeyboardShortcutOverride(.init("e", modifiers: .command))
        environment.iosHardwareKeyboardSettings.actionBindings[action.id] =
            IOSKeyboardShortcutOverride(.init("a", modifiers: .command))
        #expect(environment.save())

        let saved = try jsonObject(at: fixture.settingsURL)
        let savedService = try #require((saved["services"] as? [[String: Any]])?.first)
        let savedAction = try #require((saved["customActions"] as? [[String: Any]])?.first)
        #expect(savedService["activationShortcut"] as? [String: Int] == [
            "keyCode": 7,
            "modifierFlags": 1
        ])
        #expect(savedAction["shortcut"] as? [String: Int] == [
            "keyCode": 8,
            "modifierFlags": 2
        ])
        #expect(saved["hotkey"] as? [String: Int] == [
            "keyCode": 42,
            "modifierFlags": 1
        ])
        #expect(saved["appShortcuts"] as? [String: Any] != nil)
        #expect(saved["futureMacField"] as? [String: Any] != nil)
        let firstSave = try Data(contentsOf: fixture.settingsURL)
        #expect(environment.save())
        #expect(try Data(contentsOf: fixture.settingsURL) == firstSave)

        environment.removeAction(id: action.id)
        environment.removeService(service.id)
        #expect(environment.iosHardwareKeyboardSettings.actionBindings[action.id] == nil)
        #expect(environment.iosHardwareKeyboardSettings.engineBindings[service.id] == nil)
    }

    @Test func sessionAndEngineCommandsMapDigitsAndWrap() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let first = makeService(name: "First")
        let second = makeService(name: "Second")
        try fixture.writeSettings(
            services: [first, second],
            tabState: PersistedTabState(
                activeServiceID: first.id,
                activeIndicesByID: [first.id: 9],
                openTabs: [first.id: [9: first.url], second.id: [0: second.url]]
            )
        )
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let executor = IOSCommandExecutor(environment: environment)

        _ = try await executor.execute(.nextSession)
        #expect(environment.activeSessionIndex(for: first.id) == 0)
        _ = try await executor.execute(.previousSession)
        #expect(environment.activeSessionIndex(for: first.id) == 9)
        _ = try await executor.execute(.selectSession(3))
        #expect(environment.activeSessionIndex(for: first.id) == 3)

        _ = try await executor.execute(.nextEngine)
        #expect(environment.activeService?.id == second.id)
        _ = try await executor.execute(.nextEngine)
        #expect(environment.activeService?.id == first.id)
        _ = try await executor.execute(.selectEngine(1))
        #expect(environment.activeService?.id == second.id)
    }

    @Test func newSessionUsesLowestEmptySlotAndNeverReplacesFullSet() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let service = makeService()
        try fixture.writeSettings(
            services: [service],
            tabState: PersistedTabState(
                activeServiceID: service.id,
                openTabs: [service.id: [0: service.url, 2: service.url]]
            )
        )
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let executor = IOSCommandExecutor(environment: environment)

        _ = try await executor.execute(.openNewSession(engineID: nil))
        #expect(environment.activeSessionIndex(for: service.id) == 1)

        environment.persistedTabState.openTabs[service.id] = [:]
        environment.persistedTabState.activeIndicesByID[service.id] = 7
        _ = try await executor.execute(.openNewSession(engineID: service.id))
        #expect(environment.activeSessionIndex(for: service.id) == 0)
        #expect(environment.persistedTabState.openTabs[service.id]?.keys.sorted() == [0])

        environment.persistedTabState.openTabs[service.id] = Dictionary(
            uniqueKeysWithValues: SessionSlots.range.map { ($0, service.url) }
        )
        await #expect(throws: IOSCommandError.allSessionSlotsOccupied) {
            _ = try await executor.execute(.openNewSession(engineID: service.id))
        }
    }

    @Test func presentationAndMRUCommandsRouteThroughSceneContext() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let service = makeService()
        try fixture.writeSettings(
            services: [service],
            tabState: PersistedTabState(
                activeServiceID: service.id,
                activeIndicesByID: [service.id: 0],
                openTabs: [service.id: [0: service.url, 1: service.url]],
                tabHistory: [TabIdentifier(serviceID: service.id, sessionIndex: 1)]
            )
        )
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let context = IOSSceneCommandContext()
        var presentations: [IOSScenePresentationCommand] = []
        context.presentationHandler = { presentations.append($0) }
        let executor = IOSCommandExecutor(environment: environment)

        _ = try await executor.execute(.showSettings, sceneContext: context)
        _ = try await executor.execute(.showHistory, sceneContext: context)
        _ = try await executor.execute(.find(.show), sceneContext: context)
        #expect(presentations == [.showSettings, .showHistory, .showFind])

        _ = try await executor.execute(.cycleMRU(reverse: false))
        #expect(environment.activeSessionIndex(for: service.id) == 1)
    }

    @Test func pageCommandsCoverFindReloadZoomAndCloseWithoutCreatingEmptyTabs() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let service = makeService(url: "about:blank")
        try fixture.writeSettings(
            services: [service],
            tabState: PersistedTabState(
                activeServiceID: service.id,
                openTabs: [service.id: [0: service.url]]
            )
        )
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let executor = IOSCommandExecutor(environment: environment)
        let context = IOSSceneCommandContext()
        var presentations: [IOSScenePresentationCommand] = []
        context.presentationHandler = { presentations.append($0) }
        let initialSession = try #require(environment.activeWebSession())
        initialSession.webView.loadHTMLString(
            "<html><body><p>one match and another match</p></body></html>",
            baseURL: nil
        )
        try await initialSession.waitUntilNavigationReady(timeout: .seconds(5))

        _ = try await executor.execute(.zoom(.inStep))
        #expect(initialSession.webView.pageZoom == Zoom.default + Zoom.step)
        _ = try await executor.execute(.zoom(.outStep))
        #expect(initialSession.webView.pageZoom == Zoom.default)
        initialSession.webView.pageZoom = 1.75
        _ = try await executor.execute(.zoom(.reset))
        #expect(initialSession.webView.pageZoom == Zoom.default)

        initialSession.setFindQuery("match")
        _ = try await executor.execute(.find(.show), sceneContext: context)
        _ = try await executor.execute(.find(.next), sceneContext: context)
        _ = try await executor.execute(.find(.previous), sceneContext: context)
        #expect(presentations == [.showFind])

        _ = try await executor.execute(.reload(.normal))
        _ = try await executor.execute(.reload(.fromOrigin))
        _ = try await executor.execute(.reload(.force))
        #expect(environment.activeWebSession(createIfNeeded: false) !== initialSession)

        _ = try await executor.execute(.closeSession)
        #expect(environment.hasNoSessions(for: service.id))
        await #expect(throws: IOSCommandError.noActiveSession) {
            _ = try await executor.execute(.closeSession)
        }
        await #expect(throws: IOSCommandError.noActiveSession) {
            _ = try await executor.execute(.reload(.normal))
        }
        #expect(environment.hasNoSessions(for: service.id))
    }

    @Test func protectedCommandAuthenticatesOnceAndLockAllLocksUnlockedTargets() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        var service = makeService(name: "Protected")
        service.lockOnSwitchAway = false
        try fixture.writeSettings(
            services: [service],
            tabState: PersistedTabState(
                activeServiceID: service.id,
                openTabs: [service.id: [0: service.url]]
            )
        )
        let keyStore = TestEngineKeyStore()
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false),
            keyStore: keyStore
        )
        await environment.enableProtection(for: service.id)
        environment.lockService(service.id)
        let executor = IOSCommandExecutor(environment: environment)

        _ = try await executor.execute(.openEngine(service.id))
        #expect(!environment.isServiceLocked(service.id))
        #expect(keyStore.retrieveCount == 1)

        let dependency = IOSAppIntentDependency(environment: environment)
        let selectedLockIntent = LockEngineIntent(
            scope: .selected,
            engine: EngineEntity(id: service.id.uuidString, name: service.name),
            dependency: dependency
        )
        _ = try await selectedLockIntent.perform()
        #expect(environment.isServiceLocked(service.id))

        let openIntent = OpenEngineIntent(
            engine: EngineEntity(id: service.id.uuidString, name: service.name),
            dependency: dependency
        )
        _ = try await openIntent.perform()
        #expect(!environment.isServiceLocked(service.id))

        let lockAllIntent = LockEngineIntent(
            scope: .allProtected,
            engine: nil,
            dependency: dependency
        )
        _ = try await lockAllIntent.perform()
        #expect(environment.isServiceLocked(service.id))
    }

    @Test func cancelledAuthenticationDiscardsQueuedOperation() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        var service = makeService(name: "Protected")
        service.lockOnSwitchAway = false
        try fixture.writeSettings(services: [service])
        let keyStore = TestEngineKeyStore()
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false),
            keyStore: keyStore
        )
        await environment.enableProtection(for: service.id)
        environment.lockService(service.id)
        keyStore.cancelRetrieval = true

        await #expect(throws: IOSCommandError.self) {
            _ = try await environment.commandExecutor.execute(.openEngine(service.id))
        }
        #expect(environment.isServiceLocked(service.id))
        #expect(keyStore.retrieveCount == 1)
    }

    @Test func actionWaitsForReadinessAndSerializedCommandsRunInOrder() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let service = makeService(url: "about:blank")
        let action = CustomAction(id: UUID(), name: "Mark Page")
        var scriptedService = service
        scriptedService.actionScripts[action.id] = "window.__quiperRuns = (window.__quiperRuns || 0) + 1"
        try fixture.writeSettings(
            services: [scriptedService],
            actions: [action],
            tabState: PersistedTabState(
                activeServiceID: service.id,
                openTabs: [service.id: [0: service.url]]
            )
        )
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let session = environment.activeWebSession()!
        #expect(!session.isNavigationReady)
        let executor = IOSCommandExecutor(environment: environment)

        _ = try await executor.execute(.runAction(actionID: action.id, engineID: nil))
        let didRun = try await session.webView.evaluateJavaScript("window.__quiperRuns === 1") as? Bool
        #expect(didRun == true)

        let pending = environment.webViewSession(
            for: service.id,
            sessionIndex: 1,
            initialURL: nil,
            loadImmediately: false
        )
        environment.persistedTabState.openTabs[service.id]?[1] = service.url
        environment.persistedTabState.activeIndicesByID[service.id] = 1
        #expect(!pending.isNavigationReady)
        let shortExecutor = IOSCommandExecutor(
            environment: environment,
            actionReadinessTimeout: .milliseconds(20)
        )
        let first = Task {
            try await shortExecutor.execute(.runAction(actionID: action.id, engineID: nil))
        }
        await Task.yield()
        let second = Task {
            try await shortExecutor.execute(.selectSession(2))
        }
        _ = await first.result
        _ = try await second.value
        #expect(environment.activeSessionIndex(for: service.id) == 2)
    }

    @Test func appIntentQueriesAndInjectedIntentsUseLiveConfiguration() async throws {
        let fixture = try KeyboardFixture()
        defer { fixture.remove() }
        let first = makeService(name: "Alpha")
        var second = makeService(name: "Beta", url: "about:blank")
        let action = CustomAction(id: UUID(), name: "Share")
        second.actionScripts[action.id] = "window.__intentRuns = (window.__intentRuns || 0) + 1"
        try fixture.writeSettings(services: [first, second], actions: [action])
        let environment = fixture.makeEnvironment(
            monitor: TestHardwareKeyboardMonitor(isConnected: false)
        )
        let dependency = IOSAppIntentDependency(environment: environment)
        let engineQuery = EngineEntityQuery(dependency: dependency)
        let actionQuery = ActionEntityQuery(dependency: dependency)

        #expect(try await engineQuery.suggestedEntities().map(\.name) == ["Alpha", "Beta"])
        #expect(try await engineQuery.entities(matching: "bet").map(\.id) == [second.id.uuidString])
        #expect(try await actionQuery.suggestedEntities().map(\.name) == ["Share"])

        let intent = OpenEngineIntent(
            engine: EngineEntity(id: second.id.uuidString, name: second.name),
            dependency: dependency
        )
        _ = try await intent.perform()
        #expect(environment.activeService?.id == second.id)

        let session = try #require(environment.activeWebSession())
        #expect(!session.isNavigationReady)
        let actionIntent = RunQuiperActionIntent(
            action: ActionEntity(id: action.id.uuidString, name: action.name),
            engine: nil,
            dependency: dependency
        )
        _ = try await actionIntent.perform()
        let didRun = try await session.webView.evaluateJavaScript("window.__intentRuns === 1") as? Bool
        #expect(didRun == true)

        let newSessionIntent = OpenNewQuiperSessionIntent(engine: nil, dependency: dependency)
        _ = try await newSessionIntent.perform()
        #expect(environment.activeService?.id == second.id)
        #expect(environment.activeSessionIndex(for: second.id) == 1)

        #expect(OpenEngineIntent.supportedModes == [.foreground(.immediate)])
        #expect(OpenNewQuiperSessionIntent.supportedModes == [.foreground(.immediate)])
        #expect(RunQuiperActionIntent.supportedModes == [.foreground(.immediate)])
        #expect(LockEngineIntent.supportedModes == [.foreground(.immediate)])
        #expect(OpenNewQuiperSessionIntent().engine == nil)
        #expect(RunQuiperActionIntent().engine == nil)
        #expect(LockEngineIntent().scope == .current)
    }

    private func makeService(
        name: String = "Test",
        url: String = "https://example.com"
    ) -> Service {
        Service(name: name, url: url, focus_selector: "#prompt")
    }
}

@MainActor
private final class KeyboardFixture {
    let directoryURL: URL
    let settingsURL: URL
    let profileDirectoryURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quiper-ios-keyboard-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        settingsURL = directoryURL.appendingPathComponent("settings.json")
        profileDirectoryURL = directoryURL.appendingPathComponent("profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func writeSettings(
        services: [Service],
        actions: [CustomAction] = [],
        tabState: PersistedTabState? = nil
    ) throws {
        let settings = PersistedSettings(
            services: services,
            customActions: actions,
            persistedTabState: tabState
        )
        try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
    }

    func makeEnvironment(
        monitor: TestHardwareKeyboardMonitor,
        keyStore: TestEngineKeyStore? = nil
    ) -> AppEnvironment {
        let resolvedKeyStore = keyStore ?? TestEngineKeyStore()
        return AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: KeyboardWebsiteDataStoreManager(),
            engineKeyStore: resolvedKeyStore,
            secureProfileStore: FileSecureProfileStore(directoryURL: profileDirectoryURL),
            allowsNetworkWork: false,
            hardwareKeyboardMonitor: monitor
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

@MainActor
private final class TestHardwareKeyboardMonitor: HardwareKeyboardMonitoring {
    private(set) var isConnected: Bool
    var onConnectionChanged: ((Bool) -> Void)?

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    func start() { }

    func setConnected(_ connected: Bool) {
        isConnected = connected
        onConnectionChanged?(connected)
    }
}

@MainActor
private final class TestEngineKeyStore: EngineKeyStoring {
    private var keys: [UUID: Data] = [:]
    var cancelRetrieval = false
    private(set) var retrieveCount = 0

    func containsKey(for serviceID: UUID) -> Bool {
        keys[serviceID] != nil
    }

    func createKey(for serviceID: UUID, reason: String) async throws -> Data {
        if let key = keys[serviceID] { return key }
        let key = Data(repeating: 0x91, count: 32)
        keys[serviceID] = key
        return key
    }

    func retrieveKey(for serviceID: UUID, reason: String) async throws -> Data {
        retrieveCount += 1
        if cancelRetrieval { throw CancellationError() }
        guard let key = keys[serviceID] else { throw EngineKeyStoreError.keyMissing }
        return key
    }

    func removeKey(for serviceID: UUID) throws {
        keys[serviceID] = nil
    }
}

@MainActor
private final class KeyboardWebsiteDataStoreManager: WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore.nonPersistent()
    }

    func resetLegacyDefaultStore() async { }
    func removeDataStore(for serviceID: UUID) async throws { }
}

private func jsonObject(from settings: PersistedSettings) throws -> [String: Any] {
    try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
    )
}

private func jsonObject(at url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: url, options: .atomic)
}
