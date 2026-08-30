import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications
import WebKit

@MainActor
final class AppEnvironment: ObservableObject {
    enum StartupState: Equatable {
        case loading
        case waitingForProtectedData
        case needsWebsiteDataReset
        case ready
        case failed(String)
    }

    private enum SettingsDocumentState {
        case unavailable
        case loaded(snapshot: PersistedSettings?, json: [String: Any])
    }

    static let websiteDataStoreVersion = 1

    @Published var services: [Service] = []
    @Published var persistedTabState = PersistedTabState()
    @Published var colorScheme: AppColorScheme = .system
    @Published var dragAreaPosition: DragAreaPosition = .bottom
    @Published var customActions: [CustomAction] = []
    @Published var enablePromptHistory: Bool = true
    @Published var promptHistoryRecordOnSubmit: Bool = true
    @Published var promptHistoryRecordOnCmdBackspace: Bool = true
    @Published var promptHistoryRecordOnSelectionClear: Bool = false
    @Published var promptHistoryLimit: Int = 100
    @Published var tabNavigationRingSize: Int = 2
    @Published var tabSurvivalPolicy: TabSurvivalPolicy = .always
    @Published var automaticallySwitchEngineOnLastSessionClose: Bool = true
    @Published var autoCreateSessionOnEmptyEngineActivation: Bool = true
    @Published var shouldPurgeDanglingWebData: Bool = true
    @Published var iosHardwareKeyboardSettings: IOSHardwareKeyboardSettings = .defaults
    @Published private(set) var isHardwareKeyboardConnected = false
    @Published private(set) var startupState: StartupState = .loading
    @Published private(set) var unlockedServiceIDs: Set<UUID> = []
    @Published private(set) var securityOperationServiceIDs: Set<UUID> = []
    @Published private(set) var securityErrorByServiceID: [UUID: String] = [:]
    @Published private(set) var shouldDismissSensitiveUI = false
    @Published private(set) var needsTemplateActionSyncMigrationPrompt = false
    @Published private(set) var needsIOSOnboarding = false
    @Published var syncPreparationDetail: String? = nil
    private(set) var isRingOverlayActive = false

    private let settingsURL: URL
    private let websiteDataStoreManager: any WebsiteDataStoreManaging
    private let engineKeyStore: any EngineKeyStoring
    private let secureProfileStore: any SecureProfileStoring
    private let requiresWebsiteDataMigration: Bool
    private let isProtectedDataAvailable: () -> Bool
    private let enrichMissingIcons: Bool
    private let allowsNetworkWork: Bool
    private let hardwareKeyboardMonitor: any HardwareKeyboardMonitoring
    private var settingsDocumentState: SettingsDocumentState = .unavailable
    private var storedWebsiteDataStoreVersion: Int?
    private var persistedSettingsMigrationContext: PersistedSettingsMigrationContext?
    private var isTemplateActionSyncMigrationUnresolved = false
    private var unlockedKeys: [UUID: Data] = [:]
    private var lastActivityTime = Date()
    private var currentScenePhase: ScenePhase = .active
    private var inactivityTimer: Timer?
    private var didStartIconEnrichment = false
    private var webSessions: [UUID: [Int: WebViewSession]] = [:]
    private(set) var sessionThumbnails: [TabIdentifier: UIImage] = [:]
    @Published private(set) var thumbnailsRevision = 0
    lazy var commandExecutor = IOSCommandExecutor(environment: self)

    init(
        settingsURL: URL? = nil,
        enrichMissingIcons: Bool = true,
        websiteDataStoreManager: (any WebsiteDataStoreManaging)? = nil,
        engineKeyStore: (any EngineKeyStoring)? = nil,
        secureProfileStore: (any SecureProfileStoring)? = nil,
        requiresWebsiteDataMigration: Bool? = nil,
        isProtectedDataAvailable: (() -> Bool)? = nil,
        allowsNetworkWork: Bool = true,
        hardwareKeyboardMonitor: (any HardwareKeyboardMonitoring)? = nil
    ) {
        FaviconFetcher.configure(imageProcessor: UIKitFaviconImageProcessor.self)
        let resolvedSettingsURL = settingsURL ?? Self.makeSettingsURL()
        self.settingsURL = resolvedSettingsURL
        self.websiteDataStoreManager = websiteDataStoreManager ?? DefaultWebsiteDataStoreManager()
        self.engineKeyStore = engineKeyStore ?? IOSKeychainEngineKeyStore.shared
        self.secureProfileStore = secureProfileStore ?? FileSecureProfileStore(
            directoryURL: resolvedSettingsURL.deletingLastPathComponent().appendingPathComponent(
                "SecureProfiles",
                isDirectory: true
            )
        )
        self.requiresWebsiteDataMigration = requiresWebsiteDataMigration ?? (settingsURL == nil)
        self.isProtectedDataAvailable = isProtectedDataAvailable ?? { UIApplication.shared.isProtectedDataAvailable }
        self.enrichMissingIcons = enrichMissingIcons
        self.allowsNetworkWork = allowsNetworkWork
        self.hardwareKeyboardMonitor = hardwareKeyboardMonitor ?? HardwareKeyboardMonitor()
        load()
        self.hardwareKeyboardMonitor.onConnectionChanged = { [weak self] connected in
            self?.handleHardwareKeyboardConnection(connected)
        }
        self.hardwareKeyboardMonitor.start()
        handleHardwareKeyboardConnection(self.hardwareKeyboardMonitor.isConnected)
    }

    private func handleHardwareKeyboardConnection(_ connected: Bool) {
        isHardwareKeyboardConnected = connected
        persistHardwareKeyboardSeenIfNeeded()
    }

    private func persistHardwareKeyboardSeenIfNeeded() {
        guard isHardwareKeyboardConnected,
              startupState == .ready,
              case .loaded = settingsDocumentState,
              !iosHardwareKeyboardSettings.hasSeenHardwareKeyboard else { return }
        iosHardwareKeyboardSettings.hasSeenHardwareKeyboard = true
        _ = save()
    }

    func updateHardwareKeyboardSettings(
        _ update: (inout IOSHardwareKeyboardSettings) -> Void
    ) {
        update(&iosHardwareKeyboardSettings)
        pruneHardwareKeyboardBindings()
        _ = save()
    }

    func restoreDefaultHardwareKeyboardSettings() {
        iosHardwareKeyboardSettings.restoreDefaults()
        pruneHardwareKeyboardBindings()
        _ = save()
    }

    private func pruneHardwareKeyboardBindings() {
        iosHardwareKeyboardSettings.prune(
            validEngineIDs: Set(services.map(\.id)),
            validActionIDs: Set(customActions.map(\.id))
        )
    }

    // MARK: - Web view sessions

    func webViewSession(for serviceID: UUID, sessionIndex: Int, initialURL: URL?, loadImmediately: Bool = true) -> WebViewSession {
        if let cached = webSessions[serviceID]?[sessionIndex] {
            return cached
        }
        guard let service = services.first(where: { $0.id == serviceID }) else {
            preconditionFailure("No service for \(serviceID)")
        }
        precondition(!isServiceLocked(serviceID), "A locked engine cannot create a web session")
        let session = WebViewSession(
            service: service,
            sessionIndex: sessionIndex,
            initialURL: initialURL,
            websiteDataStore: websiteDataStoreManager.dataStore(for: serviceID),
            initialBackgroundColor: browserBackgroundColor,
            loadImmediately: loadImmediately && allowsNetworkWork
        )
        session.onPromptRecorded = { [weak self] text, clearType in
            self?.recordPrompt(text, clearType: clearType, for: serviceID, sessionIndex: sessionIndex)
        }
        session.onURLChange = { [weak self] url in
            self?.updateSessionURL(for: serviceID, sessionIndex: sessionIndex, url: url)
        }
        session.onTitleChange = { [weak self] title in
            self?.updateSessionTitle(for: serviceID, sessionIndex: sessionIndex, title: title)
        }
        session.onRememberRoutingDecision = { [weak self] host, action in
            self?.rememberRoutingDecision(host: host, action: action, serviceID: serviceID)
        }
        session.onInputStateChanged = { [weak self] state in
            self?.updateTabInputState(state, for: serviceID, sessionIndex: sessionIndex)
        }
        session.onInputStateCommitted = { [weak self] in
            self?.registerUserActivity()
            self?.save()
        }
        session.onRequestRestoreInputState = { [weak self] in
            self?.tabInputState(for: serviceID, sessionIndex: sessionIndex)
        }
        session.onSnapshot = { [weak self] image in
            self?.storeThumbnail(image, for: serviceID, sessionIndex: sessionIndex)
        }
        session.onUserActivity = { [weak self] in
            self?.registerUserActivity()
        }
        var serviceMap = webSessions[serviceID] ?? [:]
        serviceMap[sessionIndex] = session
        webSessions[serviceID] = serviceMap
        session.setKeyboardSuppressed(isRingOverlayActive)
        return session
    }

    private var browserBackgroundColor: UIColor {
        switch colorScheme {
        case .system:
            return .systemBackground
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    func setRingOverlayActive(_ active: Bool) {
        guard isRingOverlayActive != active else { return }
        isRingOverlayActive = active
        for sessions in webSessions.values {
            for session in sessions.values {
                session.setKeyboardSuppressed(active)
            }
        }
    }

    // MARK: - Accessors

    var activeService: Service? {
        Self.activeService(in: services, tabState: persistedTabState)
    }

    var isActiveServiceLocked: Bool {
        Self.isActiveServiceLocked(
            services: services,
            tabState: persistedTabState,
            unlockedServiceIDs: unlockedServiceIDs
        )
    }

    var activeServiceLockStatePublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3($services, $persistedTabState, $unlockedServiceIDs)
            .map { services, tabState, unlockedServiceIDs in
                Self.isActiveServiceLocked(
                    services: services,
                    tabState: tabState,
                    unlockedServiceIDs: unlockedServiceIDs
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static func activeService(
        in services: [Service],
        tabState: PersistedTabState
    ) -> Service? {
        guard let activeServiceID = tabState.activeServiceID else { return services.first }
        return services.first { $0.id == activeServiceID }
    }

    private static func isActiveServiceLocked(
        services: [Service],
        tabState: PersistedTabState,
        unlockedServiceIDs: Set<UUID>
    ) -> Bool {
        guard let activeService = activeService(in: services, tabState: tabState) else { return false }
        return activeService.isEncrypted && !unlockedServiceIDs.contains(activeService.id)
    }

    func isServiceLocked(_ serviceID: UUID) -> Bool {
        guard let service = services.first(where: { $0.id == serviceID }) else { return false }
        return service.isEncrypted && !unlockedServiceIDs.contains(serviceID)
    }

    func securityError(for serviceID: UUID) -> String? {
        securityErrorByServiceID[serviceID]
    }

    func clearSecurityError(for serviceID: UUID) {
        securityErrorByServiceID[serviceID] = nil
    }

    func activeSessionIndex(for serviceID: UUID) -> Int {
        let index = persistedTabState.activeIndicesByID[serviceID] ?? 0
        return SessionSlots.range.contains(index) ? index : 0
    }

    func sessionURL(for serviceID: UUID, slot: Int) -> URL? {
        if let urlString = persistedTabState.openTabs[serviceID]?[slot], !urlString.isEmpty,
           let url = URL(string: urlString) {
            return url
        }
        guard let service = services.first(where: { $0.id == serviceID }), !service.url.isEmpty else { return nil }
        return URL(string: service.url)
    }

    func activeSessionURL(for serviceID: UUID) -> URL? {
        sessionURL(for: serviceID, slot: activeSessionIndex(for: serviceID))
    }

    func isSessionLoaded(for serviceID: UUID, slot: Int) -> Bool {
        if webSessions[serviceID]?[slot] != nil { return true }
        guard let urlString = persistedTabState.openTabs[serviceID]?[slot] else { return false }
        return !urlString.isEmpty
    }

    /// Returns the live session for a tab if it has already been created,
    /// without instantiating a new one (used for ring previews).
    func existingSession(for serviceID: UUID, sessionIndex: Int) -> WebViewSession? {
        webSessions[serviceID]?[sessionIndex]
    }

    func activeWebSession(createIfNeeded: Bool = true) -> WebViewSession? {
        guard let service = activeService, !isServiceLocked(service.id) else { return nil }
        let index = activeSessionIndex(for: service.id)
        if let session = webSessions[service.id]?[index] {
            return session
        }
        guard createIfNeeded,
              persistedTabState.openTabs[service.id]?[index] != nil else { return nil }
        return webViewSession(
            for: service.id,
            sessionIndex: index,
            initialURL: activeSessionURL(for: service.id)
        )
    }

    func recreateActiveWebSession() -> WebViewSession? {
        guard let service = activeService, !isServiceLocked(service.id) else { return nil }
        let index = activeSessionIndex(for: service.id)
        let url = webSessions[service.id]?[index]?.webView.url ?? activeSessionURL(for: service.id)
        webSessions[service.id]?.removeValue(forKey: index)?.invalidate()
        return webViewSession(
            for: service.id,
            sessionIndex: index,
            initialURL: url
        )
    }

    // MARK: - Secure engine lifecycle

    func completeWebsiteDataReset() async {
        guard startupState == .needsWebsiteDataReset else { return }
        startupState = .loading
        await websiteDataStoreManager.resetLegacyDefaultStore()
        storedWebsiteDataStoreVersion = Self.websiteDataStoreVersion
        guard save(flushSecureProfiles: false) else {
            startupState = .failed("Quiper reset the old website sessions but could not record the migration. Try again before browsing.")
            return
        }
        finishLoadingReadyState()
    }

    func retryStartup() {
        guard startupState != .ready else { return }
        load()
    }

    func enableProtection(for serviceID: UUID) async {
        guard !securityOperationServiceIDs.contains(serviceID),
              var index = services.firstIndex(where: { $0.id == serviceID }),
              !services[index].isEncrypted else { return }
        securityOperationServiceIDs.insert(serviceID)
        securityErrorByServiceID[serviceID] = nil
        defer { securityOperationServiceIDs.remove(serviceID) }

        var originalService = services[index]
        var originalTabState = persistedTabState
        var keyWasPrepared = false
        do {
            let key = try await engineKeyStore.createKey(
                for: serviceID,
                reason: "Protect \(originalService.name) with your device authentication"
            )
            keyWasPrepared = true
            guard let refreshedIndex = services.firstIndex(where: { $0.id == serviceID }),
                  !services[refreshedIndex].isEncrypted else {
                throw SecurityOperationError.operationInterrupted
            }
            index = refreshedIndex
            originalService = services[index]
            originalTabState = persistedTabState
            let profile = IOSSecuredEngineProfile(
                service: originalService,
                state: persistedTabState,
                includeTabState: tabSurvivalPolicy != .never
            )
            try secureProfileStore.saveProfile(profile, key: key)

            unlockedKeys[serviceID] = key
            unlockedServiceIDs.insert(serviceID)
            services[index].isEncrypted = true
            services[index].hasMigratedMetadata = true
            // The stylesheet and scripts are sealed in the profile now; drop
            // any plaintext files so protection covers them completely.
            EngineFileStorage.deleteCustomCSS(for: serviceID)
            EngineFileStorage.deleteActionScripts(for: serviceID)
            updateCachedSessions(for: services[index])
            guard save() else {
                services[index] = originalService
                persistedTabState = originalTabState
                unlockedKeys[serviceID] = nil
                unlockedServiceIDs.remove(serviceID)
                updateCachedSessions(for: originalService)
                throw SecurityOperationError.settingsWriteFailed
            }
            if currentScenePhase == .background, services[index].lockOnSwitchAway {
                lockService(serviceID)
            }
            await removeSensitiveNotifications(for: serviceID)
        } catch {
            let isNowProtected = services.first(where: { $0.id == serviceID })?.isEncrypted == true
            if keyWasPrepared, !isNowProtected {
                try? secureProfileStore.removeProfile(for: serviceID)
                try? engineKeyStore.removeKey(for: serviceID)
            }
            if services.contains(where: { $0.id == serviceID }) {
                securityErrorByServiceID[serviceID] = error.localizedDescription
            }
        }
    }

    func disableProtection(for serviceID: UUID) async {
        guard !securityOperationServiceIDs.contains(serviceID),
              var index = services.firstIndex(where: { $0.id == serviceID }),
              services[index].isEncrypted else { return }
        securityOperationServiceIDs.insert(serviceID)
        securityErrorByServiceID[serviceID] = nil
        defer { securityOperationServiceIDs.remove(serviceID) }

        var originalService = services[index]
        var originalTabState = persistedTabState
        do {
            let key = try await engineKeyStore.retrieveKey(
                for: serviceID,
                reason: "Remove protection from \(originalService.name)"
            )
            guard let refreshedIndex = services.firstIndex(where: { $0.id == serviceID }),
                  services[refreshedIndex].isEncrypted else {
                throw SecurityOperationError.operationInterrupted
            }
            index = refreshedIndex
            originalService = services[index]
            originalTabState = persistedTabState
            let profile = try secureProfileStore.loadProfile(for: serviceID, key: key)
            var restoredService = profile.metadata.applying(to: originalService)
            restoredService.isEncrypted = false
            restoredService.hasMigratedMetadata = false
            services[index] = restoredService
            if tabSurvivalPolicy != .never {
                profile.tabState?.applying(to: &persistedTabState, serviceID: serviceID)
            }

            guard save(flushSecureProfiles: false) else {
                services[index] = originalService
                persistedTabState = originalTabState
                throw SecurityOperationError.settingsWriteFailed
            }
            unlockedKeys[serviceID] = nil
            unlockedServiceIDs.remove(serviceID)
            var cleanupErrors: [String] = []
            do {
                try secureProfileStore.removeProfile(for: serviceID)
            } catch {
                cleanupErrors.append("encrypted profile")
            }
            do {
                try engineKeyStore.removeKey(for: serviceID)
            } catch {
                cleanupErrors.append("device key")
            }
            updateCachedSessions(for: restoredService)
            if !cleanupErrors.isEmpty {
                securityErrorByServiceID[serviceID] = "Protection was removed, but Quiper could not clean up the old \(cleanupErrors.joined(separator: " and "))."
            }
        } catch {
            if services.contains(where: { $0.id == serviceID }) {
                securityErrorByServiceID[serviceID] = error.localizedDescription
            }
        }
    }

    @discardableResult
    func unlockService(
        _ serviceID: UUID,
        createSessionIfNeeded: Bool = true
    ) async -> Bool {
        guard var index = services.firstIndex(where: { $0.id == serviceID }) else { return false }
        guard isServiceLocked(serviceID) else { return true }
        guard !securityOperationServiceIDs.contains(serviceID) else { return false }
        securityOperationServiceIDs.insert(serviceID)
        securityErrorByServiceID[serviceID] = nil
        defer { securityOperationServiceIDs.remove(serviceID) }

        do {
            let key = try await engineKeyStore.retrieveKey(
                for: serviceID,
                reason: "Unlock \(services[index].name)"
            )
            guard let refreshedIndex = services.firstIndex(where: { $0.id == serviceID }),
                  isServiceLocked(serviceID) else { return false }
            index = refreshedIndex
            guard currentScenePhase != .background || !services[index].lockOnSwitchAway else {
                return false
            }
            var profile = try secureProfileStore.loadProfile(for: serviceID, key: key)
            // Migrate lock settings from unencrypted storage to encrypted profile only at decrypt time.
            var metadata = profile.metadata
            var didMigrateLock = false
            if metadata.lockOnSwitchAway == nil {
                metadata.lockOnSwitchAway = services[index].lockOnSwitchAway
                didMigrateLock = true
            }
            if metadata.lockAfterInactivity == nil {
                metadata.lockAfterInactivity = services[index].lockAfterInactivity
                didMigrateLock = true
            }
            if metadata.autoLockInactivityTimeout == nil {
                metadata.autoLockInactivityTimeout = services[index].autoLockInactivityTimeout
                didMigrateLock = true
            }
            if didMigrateLock {
                var updatedProfile = profile
                updatedProfile.metadata = metadata
                try secureProfileStore.saveProfile(updatedProfile, key: key)
                profile = updatedProfile
            }
            var restoredService = profile.metadata.applying(to: services[index])
            let validActionIDs = Set(customActions.map(\.id))
            restoredService.actionScripts = restoredService.actionScripts.filter { validActionIDs.contains($0.key) }
            restoredService.templateActionScriptSync = restoredService.templateActionScriptSync.filter {
                validActionIDs.contains($0.key)
            }
            services[index] = restoredService
            if tabSurvivalPolicy != .never {
                profile.tabState?.applying(to: &persistedTabState, serviceID: serviceID)
            }
            unlockedKeys[serviceID] = key
            unlockedServiceIDs.insert(serviceID)
            registerUserActivity()
            if createSessionIfNeeded,
               autoCreateSessionOnEmptyEngineActivation,
               hasNoSessions(for: serviceID) {
                ensureSessions(for: serviceID)
            }
            if persistedTabState.activeServiceID == serviceID {
                restoreTabsState()
            }
            return true
        } catch {
            securityErrorByServiceID[serviceID] = error.localizedDescription
            return false
        }
    }

    func lockService(_ serviceID: UUID) {
        guard unlockedServiceIDs.contains(serviceID),
              let index = services.firstIndex(where: { $0.id == serviceID }),
              let key = unlockedKeys[serviceID] else { return }
        let service = services[index]
        let profile = IOSSecuredEngineProfile(
            service: service,
            state: persistedTabState,
            includeTabState: tabSurvivalPolicy != .never
        )
        do {
            try secureProfileStore.saveProfile(profile, key: key)
        } catch {
            securityErrorByServiceID[serviceID] = "The latest in-memory changes could not be saved before locking. The previously saved protected profile remains intact."
        }

        invalidateSessions(for: serviceID)
        stripSensitiveState(for: serviceID)
        services[index] = securedStub(from: service)
        unlockedKeys[serviceID] = nil
        unlockedServiceIDs.remove(serviceID)
        _ = save(flushSecureProfiles: false)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        currentScenePhase = phase
        switch phase {
        case .active:
            shouldDismissSensitiveUI = false
            // App initialization can race the protected-data availability
            // transition on a normal foreground launch. Retry here as soon as
            // the scene is active so a transient device-data lock cannot leave
            // the app stuck on the startup lock screen.
            if startupState == .waitingForProtectedData {
                retryStartup()
            }
            if startupState == .ready {
                checkInactivityLocks()
            }
        case .inactive:
            if startupState == .ready {
                save()
            }
        case .background:
            shouldDismissSensitiveUI = true
            if startupState == .ready {
                save()
                for service in services where service.isEncrypted && service.lockOnSwitchAway {
                    lockService(service.id)
                }
            }
        @unknown default:
            break
        }
    }

    func registerUserActivity() {
        lastActivityTime = Date()
    }

    func checkInactivityLocks(now: Date = Date()) {
        let elapsed = now.timeIntervalSince(lastActivityTime)
        for service in services where service.isEncrypted && service.lockAfterInactivity {
            guard unlockedServiceIDs.contains(service.id) else { continue }
            if elapsed >= TimeInterval(max(1, service.autoLockInactivityTimeout) * 60) {
                lockService(service.id)
            }
        }
    }

    private enum SecurityOperationError: LocalizedError {
        case settingsWriteFailed
        case operationInterrupted

        var errorDescription: String? {
            switch self {
            case .settingsWriteFailed:
                "Quiper could not safely update settings, so the security change was rolled back."
            case .operationInterrupted:
                "The engine changed while Quiper was authenticating, so the security operation was cancelled."
            }
        }
    }

    private func securedStub(from service: Service) -> Service {
        var stub = service
        stub.url = ""
        stub.focus_selector = ""
        stub.actionScripts = [:]
        stub.customCSS = nil
        stub.routingRules = []
        stub.iconBase64 = nil
        stub.iconManuallyUnset = nil
        stub.preservePrompt = true
        stub.templateActionScriptSync = [:]
        stub.templatePromptInputSelectorSync = false
        stub.templateCustomCSSSync = false
        stub.isEncrypted = true
        stub.hasMigratedMetadata = true
        return stub
    }

    private func stripSensitiveState(for serviceID: UUID) {
        persistedTabState.activeIndicesByID[serviceID] = nil
        persistedTabState.openTabs[serviceID] = nil
        persistedTabState.tabTitles[serviceID] = nil
        persistedTabState.tabInputs[serviceID] = nil
        persistedTabState.tabPromptHistories[serviceID] = nil
        persistedTabState.tabPromptHistoryEnabledOverrides[serviceID] = nil
        persistedTabState.tabHistory?.removeAll { $0.serviceID == serviceID }
        if lastActiveTab?.serviceID == serviceID {
            lastActiveTab = nil
        }
        sessionThumbnails = sessionThumbnails.filter { $0.key.serviceID != serviceID }
        thumbnailsRevision += 1
    }

    private func invalidateSessions(for serviceID: UUID) {
        if let sessions = webSessions[serviceID] {
            for session in sessions.values {
                session.invalidate()
            }
        }
        webSessions[serviceID] = nil
    }

    private func removeSensitiveNotifications(for serviceID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let serviceIDString = serviceID.uuidString
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.compactMap { notification in
            notification.request.content.userInfo[NotificationMetadata.serviceIDKey] as? String == serviceIDString
                ? notification.request.identifier
                : nil
        }
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.compactMap { request in
            request.content.userInfo[NotificationMetadata.serviceIDKey] as? String == serviceIDString
                ? request.identifier
                : nil
        }
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
    }

    // MARK: - Service management

    func setActiveService(_ id: UUID, createSessionIfNeeded: Bool = true) {
        guard services.contains(where: { $0.id == id }) else { return }
        registerUserActivity()
        let previousService = activeService
        if let previousService, previousService.id != id {
            captureThumbnailWhenLeaving(
                TabIdentifier(
                    serviceID: previousService.id,
                    sessionIndex: activeSessionIndex(for: previousService.id)
                )
            )
        }
        let newTab = TabIdentifier(serviceID: id, sessionIndex: activeSessionIndex(for: id))
        recordTabHistory(switchingTo: newTab)
        persistedTabState.activeServiceID = id
        if let previousService,
           previousService.id != id,
           previousService.isEncrypted,
           previousService.lockOnSwitchAway {
            lockService(previousService.id)
        }
        if createSessionIfNeeded,
           autoCreateSessionOnEmptyEngineActivation,
           !isServiceLocked(id),
           hasNoSessions(for: id) {
            ensureSessions(for: id)
        }
        save()
    }

    /// Mirrors macOS `updateActiveWebview`: when the activated engine has no
    /// sessions and auto-create is disabled, the engine is shown empty unless a
    /// session is explicitly requested (e.g. tapping a session slot).
    func hasNoSessions(for serviceID: UUID) -> Bool {
        (persistedTabState.openTabs[serviceID] ?? [:]).isEmpty
    }

    func updateService(_ service: Service) {
        guard let index = services.firstIndex(where: { $0.id == service.id }) else { return }
        if isServiceLocked(service.id) {
            services[index].name = service.name
            services[index].lockOnSwitchAway = service.lockOnSwitchAway
            services[index].lockAfterInactivity = service.lockAfterInactivity
            services[index].autoLockInactivityTimeout = max(1, service.autoLockInactivityTimeout)
            save(flushSecureProfiles: false)
            return
        }
        services[index] = service
        syncCustomCSSFile(for: service)
        updateCachedSessions(for: service)
        save()
    }

    /// Keeps the file-backed stylesheet in step with the engine's stored state:
    /// synced engines (and cleared stylesheets) have no file, custom ones keep
    /// the edited content. Protected engines never touch files—their stylesheet
    /// lives only in the sealed profile.
    private func syncCustomCSSFile(for service: Service) {
        guard !service.isEncrypted else { return }
        EngineFileStorage.saveCustomCSS(
            service.templateCustomCSSSync ? "" : (service.customCSS ?? ""),
            serviceID: service.id
        )
    }

    /// Persists a remembered routing choice for a host at the top of the engine's
    /// routing rules, mirroring macOS `rememberDecision`.
    func rememberRoutingDecision(host: String, action: RoutingAction, serviceID: UUID) {
        guard !host.isEmpty,
              !isServiceLocked(serviceID),
              let index = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[index] = RoutingResolver.applyingRememberedRule(host: host, action: action, to: services[index])
        updateCachedSessions(for: services[index])
        save()
    }

    private func updateCachedSessions(for service: Service) {
        guard let sessions = webSessions[service.id] else { return }
        for session in sessions.values {
            session.updateService(service)
        }
    }

    func addService(_ service: Service) {
        services.append(service)
        ensureSessions(for: service.id)
        save()
        enrichMissingIconsIfNeeded()
    }

    var defaultServiceTemplates: [Service] {
        DefaultEngineDefinitions.definitions
    }

    /// Mirrors macOS `addService(from:enrichIcons:)`: copies a bundled template,
    /// seeds the template-sync flags, and pre-wires default action scripts for
    /// every custom action the template provides.
    func addService(from template: Service, enrichIcons: Bool = true) {
        var service = template
        service.id = UUID()
        service.actionScripts = [:]
        if ActionScripts.defaultPromptInputSelector(for: service) != nil {
            service.templatePromptInputSelectorSync = true
            service.focus_selector = ""
        }
        if ActionScripts.defaultCustomCSS(for: service) != nil {
            service.templateCustomCSSSync = true
            service.customCSS = nil
        }
        applyDefaultScripts(from: template, to: &service)
        services.append(service)
        ensureSessions(for: service.id)
        save()
        if enrichIcons {
            enrichMissingIconsIfNeeded()
        }
    }

    func addAllServiceTemplates() {
        var knownNames = Set(services.map { $0.name.lowercased() })
        for template in defaultServiceTemplates {
            let key = template.name.lowercased()
            guard !knownNames.contains(key) else { continue }
            addService(from: template, enrichIcons: false)
            knownNames.insert(key)
        }
        enrichMissingIconsIfNeeded()
    }

    private func applyDefaultScripts(from template: Service, to service: inout Service) {
        for action in customActions {
            guard let defaultID = ActionScripts.defaultActionID(matching: action.name),
                  let templateScript = template.actionScripts[defaultID],
                  !templateScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            service.templateActionScriptSync[action.id] = true
            service.actionScripts.removeValue(forKey: action.id)
        }
    }

    private func enrichMissingIconsIfNeeded() {
        var localUpdated = false
        for idx in 0..<services.count {
            guard !isServiceLocked(services[idx].id) else { continue }
            if let defaultB64 = EngineIconService.defaultIcon(for: services[idx], defaults: DefaultEngineDefinitions.definitions) {
                services[idx].iconBase64 = defaultB64
                localUpdated = true
            }
        }
        if localUpdated {
            save()
        }

        let enginesWithMissingIcons = EngineIconService.servicesMissingIcons(in: services)
        guard !enginesWithMissingIcons.isEmpty else { return }

        Task(priority: .background) {
            let fetchedIcons = await EngineIconService.fetchFavicons(for: enginesWithMissingIcons)
            guard !fetchedIcons.isEmpty else { return }
            await MainActor.run {
                var updated = false
                for (id, base64) in fetchedIcons {
                    if let idx = services.firstIndex(where: { $0.id == id }),
                       !isServiceLocked(id),
                       services[idx].iconBase64 == nil,
                       services[idx].iconManuallyUnset != true {
                        services[idx].iconBase64 = base64
                        updated = true
                    }
                }
                if updated {
                    save()
                }
            }
        }
    }

    func removeService(_ serviceID: UUID) {
        guard !securityOperationServiceIDs.contains(serviceID) else {
            securityErrorByServiceID[serviceID] = "Wait for the current security operation to finish before deleting this engine."
            return
        }
        guard let removed = services.first(where: { $0.id == serviceID }) else { return }
        invalidateSessions(for: serviceID)
        services.removeAll { $0.id == serviceID }
        persistedTabState.openTabs[serviceID] = nil
        persistedTabState.tabTitles[serviceID] = nil
        persistedTabState.tabPromptHistories[serviceID] = nil
        persistedTabState.tabInputs[serviceID] = nil
        persistedTabState.tabPromptHistoryEnabledOverrides[serviceID] = nil
        persistedTabState.activeIndicesByID[serviceID] = nil
        persistedTabState.tabHistory?.removeAll { $0.serviceID == serviceID }
        sessionThumbnails = sessionThumbnails.filter { $0.key.serviceID != serviceID }
        unlockedKeys[serviceID] = nil
        unlockedServiceIDs.remove(serviceID)
        securityErrorByServiceID[serviceID] = nil
        try? secureProfileStore.removeProfile(for: serviceID)
        try? engineKeyStore.removeKey(for: serviceID)
        if lastActiveTab?.serviceID == serviceID {
            lastActiveTab = nil
        }
        if persistedTabState.activeServiceID == serviceID {
            persistedTabState.activeServiceID = services.first?.id
        }
        iosHardwareKeyboardSettings.engineBindings[serviceID] = nil
        EngineFileStorage.deleteCustomCSS(for: serviceID)
        EngineFileStorage.deleteActionScripts(for: serviceID)
        save()
        purgeWebDataIfNeeded(for: removed)
    }

    /// Each engine owns an identified WebKit store, so removal never affects a
    /// different engine even when both point at the same host.
    private func purgeWebDataIfNeeded(for service: Service) {
        guard shouldPurgeDanglingWebData else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await websiteDataStoreManager.removeDataStore(for: service.id)
            } catch {
                securityErrorByServiceID[service.id] = "The engine was removed, but its isolated website data could not be deleted."
            }
        }
    }

    // MARK: - Session management

    func ensureSessions(for serviceID: UUID) {
        guard !isServiceLocked(serviceID) else { return }
        guard (persistedTabState.openTabs[serviceID] ?? [:]).isEmpty else { return }
        if persistedTabState.openTabs[serviceID] == nil {
            persistedTabState.openTabs[serviceID] = [:]
        }
        persistedTabState.openTabs[serviceID]?[0] = serviceURL(for: serviceID)
        persistedTabState.activeIndicesByID[serviceID] = 0
    }

    func closeSession(for serviceID: UUID, at index: Int) {
        guard persistedTabState.openTabs[serviceID]?[index] != nil ||
              persistedTabState.tabTitles[serviceID]?[index] != nil else { return }
        persistedTabState.openTabs[serviceID]?.removeValue(forKey: index)
        persistedTabState.tabTitles[serviceID]?.removeValue(forKey: index)
        persistedTabState.tabPromptHistories[serviceID]?.removeValue(forKey: index)
        persistedTabState.tabInputs[serviceID]?.removeValue(forKey: index)
        let closedTab = TabIdentifier(serviceID: serviceID, sessionIndex: index)
        persistedTabState.tabHistory?.removeAll { $0 == closedTab }
        sessionThumbnails.removeValue(forKey: closedTab)
        if lastActiveTab == closedTab {
            lastActiveTab = nil
        }
        webSessions[serviceID]?.removeValue(forKey: index)?.invalidate()
        if persistedTabState.activeIndicesByID[serviceID] == index {
            let remaining = (persistedTabState.openTabs[serviceID] ?? [:]).keys.sorted()
            persistedTabState.activeIndicesByID[serviceID] = remaining.min(by: { abs($0 - index) < abs($1 - index) }) ?? 0
        }
        if hasNoSessions(for: serviceID),
           persistedTabState.activeServiceID == serviceID,
           automaticallySwitchEngineOnLastSessionClose,
           let fallback = nearestEngineWithSessions(from: serviceID) {
            persistedTabState.activeServiceID = fallback
            persistedTabState.activeIndicesByID[fallback] = preferredSessionIndex(for: fallback)
        }
        save()
    }

    /// Mirrors macOS `closeCurrentTab`'s fallback: when the active engine loses
    /// its last session, search previous engines first, then next, and switch to
    /// the first engine that still has a session.
    private func nearestEngineWithSessions(from serviceID: UUID) -> UUID? {
        guard let currentIndex = services.firstIndex(where: { $0.id == serviceID }) else { return nil }
        let left = stride(from: currentIndex - 1, through: 0, by: -1).map { services[$0].id }
        let right = stride(from: currentIndex + 1, to: services.count, by: 1).map { services[$0].id }
        for candidate in left + right where !hasNoSessions(for: candidate) {
            return candidate
        }
        return nil
    }

    /// Prefers the engine's remembered active session when it is still loaded,
    /// otherwise the lowest live session, mirroring macOS.
    private func preferredSessionIndex(for serviceID: UUID) -> Int {
        let remembered = activeSessionIndex(for: serviceID)
        if webSessions[serviceID]?[remembered] != nil {
            return remembered
        }
        return (persistedTabState.openTabs[serviceID] ?? [:]).keys.min() ?? 0
    }

    func setActiveSession(for serviceID: UUID, index: Int) {
        guard services.contains(where: { $0.id == serviceID }) else { return }
        registerUserActivity()
        let slot = SessionSlots.range.contains(index) ? index : 0
        let newTab = TabIdentifier(serviceID: serviceID, sessionIndex: slot)
        if let oldService = activeService {
            let oldTab = TabIdentifier(serviceID: oldService.id, sessionIndex: activeSessionIndex(for: oldService.id))
            if oldTab != newTab {
                captureThumbnailWhenLeaving(oldTab)
            }
        }
        let previousService = activeService
        recordTabHistory(switchingTo: newTab)
        persistedTabState.activeServiceID = serviceID
        if let previousService,
           previousService.id != serviceID,
           previousService.isEncrypted,
           previousService.lockOnSwitchAway {
            lockService(previousService.id)
        }
        guard !isServiceLocked(serviceID) else {
            persistedTabState.activeIndicesByID[serviceID] = slot
            save()
            return
        }
        if persistedTabState.openTabs[serviceID] == nil {
            persistedTabState.openTabs[serviceID] = [:]
        }
        if persistedTabState.openTabs[serviceID]?[slot] == nil {
            persistedTabState.openTabs[serviceID]?[slot] = serviceURL(for: serviceID)
        }
        persistedTabState.activeIndicesByID[serviceID] = slot
        if allowsNetworkWork {
            webSessions[serviceID]?[slot]?.loadIfNeeded()
        }
        save()
    }

    /// Activates the engine and session associated with a web notification.
    /// The URL fallback keeps notifications created by older app versions usable.
    func activateNotification(serviceID: UUID?, serviceURL: String?, sessionIndex: Int?) {
        let resolvedServiceID = serviceID.flatMap { id in
            services.contains(where: { $0.id == id }) ? id : nil
        } ?? serviceURL.flatMap { url in
            services.first(where: { $0.url == url })?.id
        }
        guard let resolvedServiceID else { return }

        if let sessionIndex, SessionSlots.range.contains(sessionIndex) {
            setActiveSession(for: resolvedServiceID, index: sessionIndex)
        } else {
            setActiveService(resolvedServiceID)
        }
    }

    func updateSessionURL(for serviceID: UUID, sessionIndex: Int, url: URL) {
        guard services.contains(where: { $0.id == serviceID }), !isServiceLocked(serviceID) else { return }
        let urlString = url.absoluteString
        guard !urlString.isEmpty, urlString != "about:blank" else { return }
        if persistedTabState.openTabs[serviceID] == nil {
            persistedTabState.openTabs[serviceID] = [:]
        }
        persistedTabState.openTabs[serviceID]?[sessionIndex] = urlString
    }

    func updateSessionTitle(for serviceID: UUID, sessionIndex: Int, title: String) {
        guard services.contains(where: { $0.id == serviceID }), !isServiceLocked(serviceID) else { return }
        guard !title.isEmpty else { return }
        if persistedTabState.tabTitles[serviceID] == nil {
            persistedTabState.tabTitles[serviceID] = [:]
        }
        persistedTabState.tabTitles[serviceID]?[sessionIndex] = title
    }

    private func serviceURL(for serviceID: UUID) -> String {
        services.first { $0.id == serviceID }?.url ?? ""
    }

    // MARK: - Actions

    func actionScript(for service: Service, action: CustomAction) -> String {
        ActionScripts.resolvedActionScript(for: service, action: action)
    }

    // MARK: - Actions management

    var defaultActionTemplates: [CustomAction] {
        DefaultActions.defaults
    }

    func addBlankAction() {
        customActions.append(CustomAction(name: "New Action"))
        save()
    }

    func addAction(from template: CustomAction) {
        guard !customActions.contains(where: { $0.id == template.id }) else { return }
        customActions.append(template)
        applyDefaultScripts(for: template)
        save()
    }

    func addAllActionTemplates() {
        var existingIDs = Set(customActions.map { $0.id })
        for template in defaultActionTemplates {
            guard !existingIDs.contains(template.id) else { continue }
            customActions.append(template)
            existingIDs.insert(template.id)
            applyDefaultScripts(for: template)
        }
        save()
    }

    func renameAction(id: UUID, name: String) {
        guard let index = customActions.firstIndex(where: { $0.id == id }) else { return }
        customActions[index].name = name
        save()
    }

    func removeAction(id: UUID) {
        customActions.removeAll { $0.id == id }
        iosHardwareKeyboardSettings.actionBindings[id] = nil
        for serviceIndex in services.indices {
            services[serviceIndex].actionScripts.removeValue(forKey: id)
            services[serviceIndex].templateActionScriptSync.removeValue(forKey: id)
        }
        save()
    }

    func removeAllServices() {
        let servicesToRemove = services
        guard !servicesToRemove.isEmpty else { return }
        let busyIDs = securityOperationServiceIDs.intersection(servicesToRemove.map(\.id))
        guard busyIDs.isEmpty else {
            if let first = busyIDs.first {
                securityErrorByServiceID[first] = "Wait for the current security operation to finish before deleting engines."
            }
            return
        }
        for serviceID in servicesToRemove.map(\.id) {
            invalidateSessions(for: serviceID)
            sessionThumbnails = sessionThumbnails.filter { $0.key.serviceID != serviceID }
            unlockedKeys[serviceID] = nil
            unlockedServiceIDs.remove(serviceID)
            securityErrorByServiceID[serviceID] = nil
            try? secureProfileStore.removeProfile(for: serviceID)
            try? engineKeyStore.removeKey(for: serviceID)
            EngineFileStorage.deleteCustomCSS(for: serviceID)
            EngineFileStorage.deleteActionScripts(for: serviceID)
        }
        let removedServices = servicesToRemove
        services.removeAll()
        persistedTabState.openTabs.removeAll()
        persistedTabState.tabTitles.removeAll()
        persistedTabState.tabPromptHistories.removeAll()
        persistedTabState.tabInputs.removeAll()
        persistedTabState.tabPromptHistoryEnabledOverrides.removeAll()
        persistedTabState.activeIndicesByID.removeAll()
        persistedTabState.tabHistory?.removeAll()
        persistedTabState.activeServiceID = nil
        lastActiveTab = nil
        iosHardwareKeyboardSettings.engineBindings = [:]
        pruneHardwareKeyboardBindings()
        save()
        for service in removedServices where shouldPurgeDanglingWebData {
            Task { [weak self, serviceID = service.id] in
                try? await self?.websiteDataStoreManager.removeDataStore(for: serviceID)
            }
        }
    }

    func removeAllActions() {
        guard !customActions.isEmpty || services.contains(where: { !$0.actionScripts.isEmpty || !$0.templateActionScriptSync.isEmpty }) else { return }
        for index in services.indices {
            let serviceID = services[index].id
            services[index].actionScripts.removeAll()
            services[index].templateActionScriptSync.removeAll()
            EngineFileStorage.deleteActionScripts(for: serviceID)
        }
        customActions.removeAll()
        iosHardwareKeyboardSettings.actionBindings.removeAll()
        pruneHardwareKeyboardBindings()
        save()
    }

    // MARK: - Config import / export

    func makePersistedSettingsForExport() -> PersistedSettings {
        makePersistedSettingsForExport(secureChoice: .keepLocked, decryptedEngines: [])
    }

    func makePersistedSettingsForExport(
        secureChoice: SecureExportChoice,
        decryptedEngines: [DecryptedEngineForExport] = []
    ) -> PersistedSettings {
        let decryptedByID = Dictionary(uniqueKeysWithValues: decryptedEngines.map { ($0.service.id, $0.service) })
        let servicesForExport: [Service] = {
            switch secureChoice {
            case .keepLocked:
                return services.map { $0.isEncrypted ? securedStub(from: $0) : $0 }
            case .exclude:
                return services.filter { !$0.isEncrypted }
            case .decryptForMigration:
                return services.compactMap { service in
                    if service.isEncrypted, let decrypted = decryptedByID[service.id] {
                        return decrypted
                    }
                    if service.isEncrypted {
                        return securedStub(from: service)
                    }
                    return service
                }
            }
        }()

        let activeTabState: PersistedTabState? = {
            guard tabSurvivalPolicy != .never else { return nil }
            switch secureChoice {
            case .keepLocked, .exclude:
                return plaintextTabState()
            case .decryptForMigration:
                var full = plaintextTabState()
                // Start from plaintext and add back decrypted engines' tab states
                for engine in decryptedEngines {
                    let id = engine.service.id
                    if let tabState = engine.tabState {
                        var dict = full
                        tabState.applying(to: &dict, serviceID: id)
                        full = dict
                    } else if let existing = persistedTabState.openTabs[id] {
                        // Already unlocked engine had its tabs in plaintext? No, unlocked engines' tabs are already in persistedTabState but filtered out by plaintextTabState.
                        // For already-unlocked engines, we need to take their current tabs from live persistedTabState
                        full.openTabs[id] = persistedTabState.openTabs[id]
                        full.tabTitles[id] = persistedTabState.tabTitles[id]
                        full.tabInputs[id] = persistedTabState.tabInputs[id]
                        full.tabPromptHistories[id] = persistedTabState.tabPromptHistories[id]
                        full.tabPromptHistoryEnabledOverrides[id] = persistedTabState.tabPromptHistoryEnabledOverrides[id]
                        if let idx = persistedTabState.activeIndicesByID[id] {
                            full.activeIndicesByID[id] = idx
                        }
                    }
                }
                // Also preserve non-encrypted tabs already in plaintext, and ensure tabHistory includes decrypted engines
                var mergedHistory = full.tabHistory ?? []
                let decryptedIDs = Set(decryptedEngines.map { $0.service.id })
                // Add history entries for decrypted engines that were previously filtered
                for entry in persistedTabState.tabHistory ?? [] where decryptedIDs.contains(entry.serviceID) {
                    if !mergedHistory.contains(entry) {
                        mergedHistory.append(entry)
                    }
                }
                full.tabHistory = mergedHistory.isEmpty ? nil : mergedHistory
                return full
            }
        }()

        var payload = PersistedSettings(services: servicesForExport)
        payload.customActions = customActions
        payload.colorScheme = colorScheme
        payload.dragAreaPosition = dragAreaPosition
        payload.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        payload.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        payload.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        payload.tabSurvivalPolicy = tabSurvivalPolicy
        payload.persistedTabState = activeTabState
        payload.enablePromptHistory = enablePromptHistory
        payload.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        payload.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        payload.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        payload.promptHistoryLimit = promptHistoryLimit
        payload.tabNavigationRingSize = tabNavigationRingSize
        payload.iosHardwareKeyboardSettings = iosHardwareKeyboardSettings
        payload.version = 1
        payload.quiperVersion = persistedQuiperVersionForSave
        payload.hasCompletedIOSOnboarding = needsIOSOnboarding ? nil : true
        return payload
    }

    var hasEncryptedServices: Bool {
        services.contains { $0.isEncrypted }
    }

    func hasLocalSecureData(for serviceID: UUID) -> Bool {
        secureProfileStore.containsProfile(for: serviceID) && engineKeyStore.containsKey(for: serviceID)
    }

    func orphanedServicesForImport(in persisted: PersistedSettings) -> [Service] {
        orphanedEncryptedServices(in: persisted, hasLocalBundle: hasLocalSecureData)
    }

    struct DecryptedEngineForExport {
        let service: Service
        let tabState: IOSSecuredTabState?
    }

    /// Pure helper: returns a decrypted copy without mutating live state.
    /// If already unlocked, uses in-memory service; otherwise prompts for biometric and reads the profile.
    func decryptedServiceForExport(serviceID: UUID) async throws -> DecryptedEngineForExport {
        guard let stub = services.first(where: { $0.id == serviceID }) else {
            throw SecureExportError.serviceNotFound
        }
        guard stub.isEncrypted else {
            return DecryptedEngineForExport(service: stub, tabState: nil)
        }

        if !isServiceLocked(serviceID), let service = services.first(where: { $0.id == serviceID }) {
            let tabState: IOSSecuredTabState? = {
                guard tabSurvivalPolicy != .never else { return nil }
                var state = persistedTabState
                // Already unlocked, its tabs are already in persistedTabState, but we capture them for export
                return IOSSecuredTabState(serviceID: serviceID, state: state)
            }()
            return DecryptedEngineForExport(service: service.decryptedForExport, tabState: tabState)
        }

        let name = stub.name
        let key = try await engineKeyStore.retrieveKey(for: serviceID, reason: "Decrypt \(name) for export")
        let profile = try secureProfileStore.loadProfile(for: serviceID, key: key)
        var restored = profile.metadata.applying(to: stub)
        restored = restored.decryptedForExport
        return DecryptedEngineForExport(service: restored, tabState: profile.tabState)
    }

    enum SecureExportError: LocalizedError {
        case serviceNotFound
        case missingKey
        case authenticationCancelled
        var errorDescription: String? {
            switch self {
            case .serviceNotFound: return "Engine not found."
            case .missingKey: return "Secure storage for this engine is missing."
            case .authenticationCancelled: return "Authentication was cancelled."
            }
        }
    }

    func exportConfiguration(secureChoice: SecureExportChoice) async throws -> Data {
        switch secureChoice {
        case .keepLocked, .exclude:
            var payload = makePersistedSettingsForExport(secureChoice: secureChoice)
            ConfigPortability.inlineFileScripts(into: &payload)
            return try ConfigPortability.encode(payload)
        case .decryptForMigration:
            var decrypted: [DecryptedEngineForExport] = []
            for service in services where service.isEncrypted {
                let copy = try await decryptedServiceForExport(serviceID: service.id)
                decrypted.append(copy)
            }
            var payload = makePersistedSettingsForExport(secureChoice: .decryptForMigration, decryptedEngines: decrypted)
            ConfigPortability.inlineFileScripts(into: &payload)
            return try ConfigPortability.encode(payload)
        }
    }

    func exportConfiguration() throws -> Data {
        var payload = makePersistedSettingsForExport()
        ConfigPortability.inlineFileScripts(into: &payload)
        return try ConfigPortability.encode(payload)
    }

    func importConfiguration(from data: Data) throws {
        let persisted = try ConfigPortability.decode(from: data)
        applyImportedSettings(persisted)
        ConfigPortability.persistFileArtifacts(from: persisted)
        guard save() else {
            throw ConfigImportError.saveFailed
        }
    }

    func importConfiguration(from data: Data, droppingOrphans: Bool) throws {
        var persisted = try ConfigPortability.decode(from: data)
        if droppingOrphans {
            let orphans = Set(orphanedServicesForImport(in: persisted).map(\.id))
            persisted.services.removeAll { orphans.contains($0.id) }
            // Also purge their tab state to keep file clean
            for id in orphans {
                persisted.persistedTabState?.activeIndicesByID[id] = nil
                persisted.persistedTabState?.openTabs[id] = nil
                persisted.persistedTabState?.tabTitles[id] = nil
                persisted.persistedTabState?.tabInputs[id] = nil
                persisted.persistedTabState?.tabPromptHistories[id] = nil
                persisted.persistedTabState?.tabPromptHistoryEnabledOverrides[id] = nil
                persisted.persistedTabState?.tabHistory?.removeAll { $0.serviceID == id }
            }
        }
        applyImportedSettings(persisted)
        ConfigPortability.persistFileArtifacts(from: persisted)
        guard save() else {
            throw ConfigImportError.saveFailed
        }
    }

    private enum ConfigImportError: LocalizedError {
        case saveFailed
        var errorDescription: String? {
            "Quiper imported the file but could not save the new settings."
        }
    }

    private func applyImportedSettings(_ persisted: PersistedSettings) {
        // Invalidate sessions for services that will be replaced or removed.
        let incomingIDs = Set(persisted.services.map(\.id))
        let removedIDs = Set(services.map(\.id)).subtracting(incomingIDs)
        for serviceID in removedIDs {
            invalidateSessions(for: serviceID)
            sessionThumbnails = sessionThumbnails.filter { $0.key.serviceID != serviceID }
            unlockedKeys[serviceID] = nil
            unlockedServiceIDs.remove(serviceID)
            securityErrorByServiceID[serviceID] = nil
            try? secureProfileStore.removeProfile(for: serviceID)
            try? engineKeyStore.removeKey(for: serviceID)
            EngineFileStorage.deleteCustomCSS(for: serviceID)
            EngineFileStorage.deleteActionScripts(for: serviceID)
        }
        // Replace in-memory state.
        services = persisted.services
        // Keep cached web views in sync with the imported service descriptors.
        for service in services {
            updateCachedSessions(for: service)
        }
        // Drop any web views for engines that no longer exist.
        for serviceID in Array(webSessions.keys) where !incomingIDs.contains(serviceID) {
            invalidateSessions(for: serviceID)
        }
        customActions = persisted.customActions ?? []
        iosHardwareKeyboardSettings = persisted.iosHardwareKeyboardSettings ?? .defaults
        pruneHardwareKeyboardBindings()
        if let colorScheme = persisted.colorScheme { self.colorScheme = colorScheme }
        if let dragAreaPosition = persisted.dragAreaPosition { self.dragAreaPosition = dragAreaPosition }
        if let tabSurvivalPolicy = persisted.tabSurvivalPolicy { self.tabSurvivalPolicy = tabSurvivalPolicy }
        if let enablePromptHistory = persisted.enablePromptHistory { self.enablePromptHistory = enablePromptHistory }
        if let promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit { self.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit }
        if let promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace { self.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace }
        if let promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear { self.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear }
        if let promptHistoryLimit = persisted.promptHistoryLimit { self.promptHistoryLimit = promptHistoryLimit }
        if let tabNavigationRingSize = persisted.tabNavigationRingSize { self.tabNavigationRingSize = max(2, min(10, tabNavigationRingSize)) }
        if let automaticallySwitchEngineOnLastSessionClose = persisted.automaticallySwitchEngineOnLastSessionClose { self.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose }
        if let autoCreateSessionOnEmptyEngineActivation = persisted.autoCreateSessionOnEmptyEngineActivation { self.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation }
        if let shouldPurgeDanglingWebData = persisted.shouldPurgeDanglingWebData { self.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData }
        if tabSurvivalPolicy == .never {
            persistedTabState = PersistedTabState()
            persistedTabState.activeServiceID = services.first?.id
        } else if let tabState = persisted.persistedTabState {
            persistedTabState = tabState
            if persistedTabState.activeServiceID == nil || !services.contains(where: { $0.id == persistedTabState.activeServiceID }) {
                persistedTabState.activeServiceID = services.first?.id
            }
        } else {
            persistedTabState = PersistedTabState()
            persistedTabState.activeServiceID = services.first?.id
        }
        // Strip any plaintext for secured engines that may have been in the file as stubs already.
        for service in services where service.isEncrypted {
            stripSensitiveState(for: service.id)
        }
        if let activeID = persistedTabState.activeServiceID {
            lastActiveTab = TabIdentifier(serviceID: activeID, sessionIndex: activeSessionIndex(for: activeID))
        } else {
            lastActiveTab = nil
        }
        if autoCreateSessionOnEmptyEngineActivation {
            for service in services where !isServiceLocked(service.id) {
                ensureSessions(for: service.id)
            }
        }
        if let hasCompletedIOSOnboarding = persisted.hasCompletedIOSOnboarding {
            needsIOSOnboarding = !hasCompletedIOSOnboarding
        } else {
            needsIOSOnboarding = false
        }
        configureMigrations(loadedFromDisk: true, persistedVersion: persisted.quiperVersion)
        // Remove orphaned file artifacts for services that no longer exist.
        let validServiceIDs = Set(services.map(\.id))
        // Orphaned services already cleaned above for removedIDs; also handle case where import overwrote services completely.
        // For action scripts: valid services already have correct files via persistFileArtifacts, but old files for deleted services are gone.
        // For engines with customCSS that is now nil/synced, persistFileArtifacts already deleted the file.
        // Ensure unlocked state is consistent: encrypted engines start locked.
        for service in services where service.isEncrypted {
            unlockedKeys[service.id] = nil
            unlockedServiceIDs.remove(service.id)
        }
        _ = validServiceIDs
        // Auto-reenable Secure Storage for engines that were decrypted for migration.
        let flaggedForReenable = services.filter { $0.originatedFromSecureStorage && !$0.isEncrypted }
        if !flaggedForReenable.isEmpty {
            Task { @MainActor in
                await self.reenableSecureStorageForFlaggedServices(flaggedForReenable.map(\.id))
            }
        }
    }

    /// Re-enables Secure Storage for engines imported via decrypt-for-migration.
    /// Each engine prompts for device authentication once via `enableProtection`.
    @MainActor
    private func reenableSecureStorageForFlaggedServices(_ serviceIDs: [UUID]) async {
        for serviceID in serviceIDs {
            guard let index = services.firstIndex(where: { $0.id == serviceID }),
                  services[index].originatedFromSecureStorage,
                  !services[index].isEncrypted else { continue }
            await enableProtection(for: serviceID)
            // `enableProtection` sets `isEncrypted = true` on success; clear provenance flag.
            if let idx = services.firstIndex(where: { $0.id == serviceID }),
               services[idx].isEncrypted {
                services[idx].originatedFromSecureStorage = false
                _ = save()
            }
        }
    }

    func saveCustomActionScript(_ script: String, serviceID: UUID, actionID: UUID) {
        guard !isServiceLocked(serviceID),
              let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[serviceIndex].templateActionScriptSync[actionID] = false
        services[serviceIndex].actionScripts[actionID] = script
        if !services[serviceIndex].isEncrypted {
            EngineFileStorage.saveActionScript(script, serviceID: serviceID, actionID: actionID)
        }
        save()
    }

    /// Mirrors macOS `setTemplateActionScriptSync`: turning on follows the bundled
    /// template script (dropping the stored custom one), turning off hands control
    /// back, seeding the custom script with the default when none exists.
    func setTemplateActionScriptSync(_ isInSync: Bool, serviceID: UUID, actionID: UUID) {
        guard !isServiceLocked(serviceID),
              let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let action = customActions.first(where: { $0.id == actionID }),
              let defaultScript = ActionScripts.defaultScript(for: services[serviceIndex], action: action) else {
            return
        }

        services[serviceIndex].templateActionScriptSync[actionID] = isInSync
        if isInSync {
            services[serviceIndex].actionScripts.removeValue(forKey: actionID)
            if !services[serviceIndex].isEncrypted {
                EngineFileStorage.deleteActionScript(serviceID: serviceID, actionID: actionID)
            }
        } else {
            let existingScript = EngineFileStorage.loadActionScript(
                serviceID: serviceID,
                actionID: actionID,
                fallback: services[serviceIndex].actionScripts[actionID] ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if existingScript.isEmpty {
                services[serviceIndex].actionScripts[actionID] = defaultScript
                if !services[serviceIndex].isEncrypted {
                    EngineFileStorage.saveActionScript(
                        defaultScript,
                        serviceID: serviceID,
                        actionID: actionID
                    )
                }
            }
        }
        save()
    }

    /// Mirrors macOS `setTemplateCustomCSSSync`: turning on follows the bundled
    /// template stylesheet (dropping the stored custom one), turning off hands
    /// control back, seeding the stylesheet with the default.
    func setTemplateCustomCSSSync(_ isInSync: Bool, serviceID: UUID) {
        guard !isServiceLocked(serviceID),
              let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let defaultCSS = ActionScripts.defaultCustomCSS(for: services[serviceIndex]) else {
            return
        }

        services[serviceIndex].templateCustomCSSSync = isInSync
        if isInSync {
            services[serviceIndex].customCSS = nil
        } else {
            services[serviceIndex].customCSS = defaultCSS
        }
        if !services[serviceIndex].isEncrypted {
            EngineFileStorage.saveCustomCSS(
                isInSync ? "" : defaultCSS,
                serviceID: serviceID
            )
        }
        save()
    }

    private func applyDefaultScripts(for action: CustomAction) {
        for serviceIndex in services.indices {
            applyDefaultScript(for: action, toServiceAt: serviceIndex)
        }
    }

    private func applyDefaultScript(for action: CustomAction, toServiceAt index: Int) {
        let service = services[index]
        guard !isServiceLocked(service.id),
              let template = ActionScripts.defaultServiceTemplate(for: service),
              let defaultID = ActionScripts.defaultActionID(matching: action.name),
              let defaultScript = template.actionScripts[defaultID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !defaultScript.isEmpty else { return }
        let existing = service.actionScripts[action.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty, service.templateActionScriptSync[action.id] != false else { return }
        services[index].templateActionScriptSync[action.id] = true
        services[index].actionScripts.removeValue(forKey: action.id)
        if !services[index].isEncrypted {
            EngineFileStorage.deleteActionScript(serviceID: service.id, actionID: action.id)
        }
    }

    // MARK: - Prompt history

    /// Mirrors macOS `didReceiveInputStateMessage`: each clearing trigger records
    /// only when its own setting is enabled, and no other clear type records.
    func recordPrompt(_ text: String, clearType: String, for serviceID: UUID, sessionIndex: Int) {
        guard !isServiceLocked(serviceID) else { return }
        let shouldRecord: Bool
        switch clearType {
        case "submit":
            shouldRecord = enablePromptHistory && promptHistoryRecordOnSubmit
        case "cmdBackspace":
            shouldRecord = enablePromptHistory && promptHistoryRecordOnCmdBackspace
        case "selectionClear":
            shouldRecord = enablePromptHistory && promptHistoryRecordOnSelectionClear
        default:
            shouldRecord = false
        }
        guard shouldRecord else { return }
        guard let service = services.first(where: { $0.id == serviceID }), service.preservePrompt else { return }
        guard let entry = PromptHistoryPolicy.makeEntryIfEligible(submittedText: text) else { return }
        var current = persistedTabState.tabPromptHistories[serviceID] ?? [:]
        var list = current[sessionIndex] ?? []
        list.append(entry)
        if list.count > promptHistoryLimit {
            list.removeFirst(list.count - promptHistoryLimit)
        }
        current[sessionIndex] = list
        persistedTabState.tabPromptHistories[serviceID] = current
        save()
    }

    func promptHistory(for serviceID: UUID, sessionIndex: Int) -> [PromptHistoryEntry] {
        persistedTabState.tabPromptHistories[serviceID]?[sessionIndex] ?? []
    }

    // MARK: - Per-tab input state

    func tabInputState(for serviceID: UUID, sessionIndex: Int) -> TabInputState? {
        guard let service = services.first(where: { $0.id == serviceID }), service.preservePrompt else { return nil }
        return persistedTabState.tabInputs[serviceID]?[sessionIndex]
    }

    func updateTabInputState(_ state: TabInputState, for serviceID: UUID, sessionIndex: Int) {
        guard !isServiceLocked(serviceID) else { return }
        guard let service = services.first(where: { $0.id == serviceID }), service.preservePrompt else { return }
        if persistedTabState.tabInputs[serviceID] == nil {
            persistedTabState.tabInputs[serviceID] = [:]
        }
        persistedTabState.tabInputs[serviceID]?[sessionIndex] = state
    }

    // MARK: - Tab history ring

    private var lastActiveTab: TabIdentifier?

    /// Mirrors macOS `switchTab`'s MRU bookkeeping: the previously active tab is
    /// pushed to the front of the ring (capped at `tabNavigationRingSize - 1`) and
    /// the tab being activated is removed from history.
    private func recordTabHistory(switchingTo newTab: TabIdentifier) {
        var history = persistedTabState.tabHistory ?? []
        history = history.filter { tab in
            services.contains(where: { $0.id == tab.serviceID })
        }
        guard lastActiveTab != newTab else { return }
        history.removeAll { $0 == newTab }
        if let oldTab = lastActiveTab {
            history.removeAll { $0 == oldTab }
            history.insert(oldTab, at: 0)
            let ringSize = max(2, tabNavigationRingSize)
            if history.count > ringSize - 1 {
                history = Array(history.prefix(ringSize - 1))
            }
        }
        persistedTabState.tabHistory = history
        lastActiveTab = newTab
    }

    /// Ordered navigation ring shown by the double-tap HUD: the currently active
    /// tab first, then the MRU history (deduped), capped at `tabNavigationRingSize`.
    func navigationRingItems() -> [TabIdentifier] {
        var items: [TabIdentifier] = []
        if let service = activeService {
            items.append(TabIdentifier(serviceID: service.id, sessionIndex: activeSessionIndex(for: service.id)))
        }
        for tab in persistedTabState.tabHistory ?? [] {
            guard services.contains(where: { $0.id == tab.serviceID }) else { continue }
            if !items.contains(tab) {
                items.append(tab)
            }
        }
        let ringSize = max(2, tabNavigationRingSize)
        return Array(items.prefix(ringSize))
    }

    /// Display title for a ring item, falling back to the session slot label.
    func ringTitle(for tab: TabIdentifier) -> String {
        let title = persistedTabState.tabTitles[tab.serviceID]?[tab.sessionIndex]
        if let title, !title.isEmpty {
            return title
        }
        return "Session \(SessionSlots.label(for: tab.sessionIndex))"
    }

    // MARK: - Session thumbnails

    /// Remembers the last page state of a tab as an image. Captured when the
    /// session is left and refreshed whenever a page finishes loading, so ring
    /// previews are instant without re-screenshotting every web view.
    func storeThumbnail(_ image: UIImage?, for serviceID: UUID, sessionIndex: Int) {
        guard services.contains(where: { $0.id == serviceID }), !isServiceLocked(serviceID) else { return }
        guard let image else { return }
        sessionThumbnails[TabIdentifier(serviceID: serviceID, sessionIndex: sessionIndex)] = image
        thumbnailsRevision += 1
    }

    /// Takes a fresh snapshot of a session as it is being left, so the ring
    /// always shows the exact state we last saw before the web view unloads.
    private func captureThumbnailWhenLeaving(_ tab: TabIdentifier) {
        guard let session = webSessions[tab.serviceID]?[tab.sessionIndex] else { return }
        if let existing = session.snapshot {
            sessionThumbnails[tab] = existing
        }
        session.captureSnapshot { [weak self] image in
            self?.storeThumbnail(image, for: tab.serviceID, sessionIndex: tab.sessionIndex)
        }
    }

    /// Preferred preview for a ring item: the live snapshot for the active tab,
    /// otherwise the stored thumbnail captured when the tab was last left.
    func ringThumbnail(for tab: TabIdentifier) -> UIImage? {
        if activeService?.id == tab.serviceID,
           activeSessionIndex(for: tab.serviceID) == tab.sessionIndex,
           let live = webSessions[tab.serviceID]?[tab.sessionIndex]?.snapshot {
            return live
        }
        return sessionThumbnails[tab] ?? webSessions[tab.serviceID]?[tab.sessionIndex]?.snapshot
    }

    // MARK: - Persistence

    private static func makeSettingsURL() -> URL {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.APP_FOLDER_NAME)
        try? FileManager.default.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: baseDir.path
        )
        return baseDir.appendingPathComponent("settings.json")
    }

    // MARK: - Persisted settings migrations & first-run onboarding

    /// Mirrors macOS `App`'s migration prompts: only settings that predate
    /// version stamping (unversioned existing payloads) are eligible, and a
    /// payload from a newer or unparseable app version is deferred untouched.
    private func configureMigrations(loadedFromDisk: Bool, persistedVersion: String?) {
        let context = PersistedSettingsMigrationContext(
            loadedFromDisk: loadedFromDisk,
            persistedVersion: persistedVersion,
            currentVersion: Bundle.main.versionDisplayString
        )
        persistedSettingsMigrationContext = context

        let templateSyncDetected = context.isUnversionedExistingSettings
            && hasTemplateActionScriptMigrationCandidates()
        let disposition = context.disposition(
            whenDetected: templateSyncDetected,
            presentation: .prompted
        )
        isTemplateActionSyncMigrationUnresolved = disposition.isUnresolved
        needsTemplateActionSyncMigrationPrompt = disposition == .awaitingPrompt
    }

    /// Mirrors macOS `hasTemplateActionScriptMigrationCandidates`.
    private func hasTemplateActionScriptMigrationCandidates() -> Bool {
        services.contains { service in
            customActions.contains { ActionScripts.defaultScript(for: service, action: $0) != nil }
        }
    }

    /// Mirrors macOS `persistedQuiperVersionForSave`: the stamp stays absent
    /// until the prompted migration is resolved so the prompt survives relaunch.
    private var persistedQuiperVersionForSave: String? {
        guard let context = persistedSettingsMigrationContext,
              !isTemplateActionSyncMigrationUnresolved else {
            return nil
        }
        return context.versionForPersistence
    }

    /// Mirrors macOS `resolveTemplateActionSyncMigration`: "Update" reconnects
    /// template-matching actions to the bundled scripts and keeps them synced;
    /// "Keep Custom" leaves existing scripts editable and unchanged.
    func resolveTemplateActionSyncMigration(updateScripts: Bool) {
        for serviceIndex in services.indices {
            for action in customActions
            where ActionScripts.defaultScript(for: services[serviceIndex], action: action) != nil {
                if updateScripts {
                    services[serviceIndex].templateActionScriptSync[action.id] = true
                    services[serviceIndex].actionScripts.removeValue(forKey: action.id)
                    EngineFileStorage.deleteActionScript(
                        serviceID: services[serviceIndex].id,
                        actionID: action.id
                    )
                } else if services[serviceIndex].templateActionScriptSync[action.id] == nil {
                    services[serviceIndex].templateActionScriptSync[action.id] = false
                }
            }
        }
        isTemplateActionSyncMigrationUnresolved = false
        needsTemplateActionSyncMigrationPrompt = false
        save()
    }

    /// Mirrors macOS `OnboardingWizard.completeOnboarding` persistence: the
    /// first-run sheet appears until it is explicitly dismissed. Presentation
    /// suppression for test hosts lives in the app layer, not in this state.
    func completeIOSOnboarding() {
        guard needsIOSOnboarding else { return }
        needsIOSOnboarding = false
        save()
    }

    private func load() {
        startupState = .loading
        settingsDocumentState = .unavailable
        guard isProtectedDataAvailable() else {
            startupState = .waitingForProtectedData
            return
        }

        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            installDefaultSettings()
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            startupState = isProtectedDataAvailable()
                ? .failed("Quiper could not read settings. The existing file was left untouched.")
                : .waitingForProtectedData
            return
        }

        let persisted: PersistedSettings
        let json: [String: Any]
        do {
            persisted = try JSONDecoder().decode(PersistedSettings.self, from: data)
            guard let decodedJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SettingsLoadError.invalidTopLevelDocument
            }
            json = decodedJSON
        } catch {
            startupState = .failed("Quiper could not decode settings. The existing file was left untouched.")
            return
        }

        settingsDocumentState = .loaded(snapshot: persisted, json: json)
        storedWebsiteDataStoreVersion = json[Self.websiteDataStoreVersionKey] as? Int
        needsIOSOnboarding = !(persisted.hasCompletedIOSOnboarding ?? false)
        services = persisted.services
        customActions = persisted.customActions ?? []
        // Migration detection reads services and custom actions, so it must
        // run after they are populated from the payload.
        configureMigrations(loadedFromDisk: true, persistedVersion: persisted.quiperVersion)
        iosHardwareKeyboardSettings = persisted.iosHardwareKeyboardSettings ?? .defaults
        pruneHardwareKeyboardBindings()
        if let colorScheme = persisted.colorScheme {
            self.colorScheme = colorScheme
        }
        if let dragAreaPosition = persisted.dragAreaPosition {
            self.dragAreaPosition = dragAreaPosition
        }
        if let enablePromptHistory = persisted.enablePromptHistory {
            self.enablePromptHistory = enablePromptHistory
        }
        if let promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit {
            self.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        }
        if let promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace {
            self.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        }
        if let promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear {
            self.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        }
        if let promptHistoryLimit = persisted.promptHistoryLimit {
            self.promptHistoryLimit = promptHistoryLimit
        }
        if let tabNavigationRingSize = persisted.tabNavigationRingSize {
            self.tabNavigationRingSize = max(2, min(10, tabNavigationRingSize))
        }
        if let tabSurvivalPolicy = persisted.tabSurvivalPolicy {
            self.tabSurvivalPolicy = tabSurvivalPolicy
        }
        if let automaticallySwitchEngineOnLastSessionClose = persisted.automaticallySwitchEngineOnLastSessionClose {
            self.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        }
        if let autoCreateSessionOnEmptyEngineActivation = persisted.autoCreateSessionOnEmptyEngineActivation {
            self.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        }
        if let shouldPurgeDanglingWebData = persisted.shouldPurgeDanglingWebData {
            self.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        }

        if tabSurvivalPolicy == .never {
            // Mirror macOS `.never`: boot clean, never write or restore tab state.
            persistedTabState = PersistedTabState()
            persistedTabState.activeServiceID = services.first?.id
            if let activeID = persistedTabState.activeServiceID {
                lastActiveTab = TabIdentifier(serviceID: activeID, sessionIndex: activeSessionIndex(for: activeID))
            }
        } else {
            if let tabState = persisted.persistedTabState {
                persistedTabState = tabState
            } else {
                persistedTabState = PersistedTabState()
            }
            if persistedTabState.activeServiceID == nil ||
               !services.contains(where: { $0.id == persistedTabState.activeServiceID }) {
                persistedTabState.activeServiceID = services.first?.id
            }
            if let activeID = persistedTabState.activeServiceID {
                lastActiveTab = TabIdentifier(serviceID: activeID, sessionIndex: activeSessionIndex(for: activeID))
            }
        }

        let didSanitizeSecuredState = services.contains { service in
            guard service.isEncrypted else { return false }
            return persistedTabState.activeIndicesByID[service.id] != nil
                || persistedTabState.openTabs[service.id] != nil
                || persistedTabState.tabTitles[service.id] != nil
                || persistedTabState.tabInputs[service.id] != nil
                || persistedTabState.tabPromptHistories[service.id] != nil
                || persistedTabState.tabPromptHistoryEnabledOverrides[service.id] != nil
                || persistedTabState.tabHistory?.contains(where: { $0.serviceID == service.id }) == true
        }
        for service in services where service.isEncrypted {
            stripSensitiveState(for: service.id)
        }

        if requiresWebsiteDataMigration,
           (storedWebsiteDataStoreVersion ?? 0) < Self.websiteDataStoreVersion {
            startupState = .needsWebsiteDataReset
            return
        }
        finishLoadingReadyState()
        if persisted.didDecodeLegacyServiceIdentifiers || didSanitizeSecuredState {
            save()
        }
    }

    private enum SettingsLoadError: Error {
        case invalidTopLevelDocument
    }

    private func installDefaultSettings() {
        settingsDocumentState = .loaded(snapshot: nil, json: [:])
        storedWebsiteDataStoreVersion = Self.websiteDataStoreVersion
        configureMigrations(loadedFromDisk: false, persistedVersion: nil)
        needsIOSOnboarding = true
        // Engines are intentionally not installed here: the first-run onboarding
        // lets the user pick them. An intentionally empty engine list survives
        // relaunch, and the Add Engine flow covers late additions.
        services = []
        customActions = DefaultActions.defaults
        iosHardwareKeyboardSettings = .defaults
        persistedTabState = PersistedTabState()
        guard save(flushSecureProfiles: false) else {
            settingsDocumentState = .unavailable
            startupState = .failed("Quiper could not create its protected settings file.")
            return
        }
        finishLoadingReadyState()
    }

    private func finishLoadingReadyState() {
        startupState = .ready
        persistHardwareKeyboardSeenIfNeeded()
        if autoCreateSessionOnEmptyEngineActivation {
            for service in services where !isServiceLocked(service.id) {
                ensureSessions(for: service.id)
            }
        }
        restoreTabsState()
        startInactivityMonitoring()
        if enrichMissingIcons, !didStartIconEnrichment {
            didStartIconEnrichment = true
            enrichMissingIconsIfNeeded()
        }
    }

    private func startInactivityMonitoring() {
        guard allowsNetworkWork else { return }
        guard inactivityTimer == nil else { return }
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkInactivityLocks()
            }
        }
    }

    /// Restores only the active persisted session. Other tabs remain represented
    /// by `PersistedTabState` and are instantiated when the user selects them.
    private func restoreTabsState() {
        guard let serviceID = persistedTabState.activeServiceID,
              !isServiceLocked(serviceID),
              let sessions = persistedTabState.openTabs[serviceID],
              !sessions.isEmpty else { return }
        let preferredIndex = activeSessionIndex(for: serviceID)
        let sessionIndex = sessions[preferredIndex] != nil
            ? preferredIndex
            : sessions.keys.min() ?? preferredIndex
        guard let urlString = sessions[sessionIndex],
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        _ = webViewSession(
            for: serviceID,
            sessionIndex: sessionIndex,
            initialURL: url,
            loadImmediately: true
        )
    }

    @discardableResult
    func save(flushSecureProfiles: Bool = true) -> Bool {
        guard case let .loaded(persistedSnapshot, persistedJSON) = settingsDocumentState else {
            return false
        }
        guard isProtectedDataAvailable() else { return false }
        if flushSecureProfiles, !persistUnlockedProfiles() {
            return false
        }
        var payload = persistedSnapshot ?? PersistedSettings(services: services)
        // A protected engine may be unlocked in memory. Persist only its
        // deliberately minimal stub so future Service fields cannot cross the
        // plaintext boundary merely because their encoder was not updated.
        payload.services = services.map { service in
            service.isEncrypted ? securedStub(from: service) : service
        }
        payload.customActions = customActions
        payload.colorScheme = colorScheme
        payload.dragAreaPosition = dragAreaPosition
        payload.automaticallySwitchEngineOnLastSessionClose = automaticallySwitchEngineOnLastSessionClose
        payload.autoCreateSessionOnEmptyEngineActivation = autoCreateSessionOnEmptyEngineActivation
        payload.shouldPurgeDanglingWebData = shouldPurgeDanglingWebData
        payload.tabSurvivalPolicy = tabSurvivalPolicy
        payload.persistedTabState = tabSurvivalPolicy == .never ? nil : plaintextTabState()
        payload.enablePromptHistory = enablePromptHistory
        payload.promptHistoryRecordOnSubmit = promptHistoryRecordOnSubmit
        payload.promptHistoryRecordOnCmdBackspace = promptHistoryRecordOnCmdBackspace
        payload.promptHistoryRecordOnSelectionClear = promptHistoryRecordOnSelectionClear
        payload.promptHistoryLimit = promptHistoryLimit
        payload.tabNavigationRingSize = tabNavigationRingSize
        pruneHardwareKeyboardBindings()
        payload.iosHardwareKeyboardSettings = iosHardwareKeyboardSettings
        payload.version = 1
        payload.quiperVersion = persistedQuiperVersionForSave
        payload.hasCompletedIOSOnboarding = needsIOSOnboarding ? nil : true
        guard let encodedPayload = try? JSONEncoder().encode(payload),
              let encodedObject = try? JSONSerialization.jsonObject(with: encodedPayload) as? [String: Any]
        else { return false }

        var settingsObject = persistedJSON
        let ownedObject = Self.preservingMacShortcutFields(
            in: encodedObject,
            from: settingsObject
        )
        for key in Self.iosOwnedSettingKeys {
            settingsObject.removeValue(forKey: key)
        }
        for key in Self.knownLegacySettingKeys {
            settingsObject.removeValue(forKey: key)
        }
        for key in Self.iosOwnedSettingKeys where ownedObject[key] != nil {
            settingsObject[key] = ownedObject[key]
        }
        if let storedWebsiteDataStoreVersion {
            settingsObject[Self.websiteDataStoreVersionKey] = storedWebsiteDataStoreVersion
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: settingsObject,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: settingsURL.deletingLastPathComponent().path
            )
            try data.write(to: settingsURL, options: [.atomic, .completeFileProtection])
        } catch {
            return false
        }
        settingsDocumentState = .loaded(snapshot: payload, json: settingsObject)
        return true
    }

    private func persistUnlockedProfiles() -> Bool {
        for service in services where service.isEncrypted && unlockedServiceIDs.contains(service.id) {
            guard let key = unlockedKeys[service.id] else {
                securityErrorByServiceID[service.id] = "The engine is marked unlocked but its key is unavailable."
                return false
            }
            do {
                try secureProfileStore.saveProfile(
                    IOSSecuredEngineProfile(
                        service: service,
                        state: persistedTabState,
                        includeTabState: tabSurvivalPolicy != .never
                    ),
                    key: key
                )
            } catch {
                securityErrorByServiceID[service.id] = error.localizedDescription
                return false
            }
        }
        return true
    }

    private func plaintextTabState() -> PersistedTabState {
        var state = persistedTabState
        let secureIDs = Set(services.lazy.filter(\.isEncrypted).map(\.id))
        for serviceID in secureIDs {
            state.activeIndicesByID[serviceID] = nil
            state.openTabs[serviceID] = nil
            state.tabTitles[serviceID] = nil
            state.tabInputs[serviceID] = nil
            state.tabPromptHistories[serviceID] = nil
            state.tabPromptHistoryEnabledOverrides[serviceID] = nil
        }
        state.tabHistory = state.tabHistory?.filter { !secureIDs.contains($0.serviceID) }
        return state
    }

    private static let iosOwnedSettingKeys: Set<String> = [
        "services",
        "customActions",
        "colorScheme",
        "dragAreaPosition",
        "automaticallySwitchEngineOnLastSessionClose",
        "autoCreateSessionOnEmptyEngineActivation",
        "shouldPurgeDanglingWebData",
        "tabSurvivalPolicy",
        "persistedTabState",
        "enablePromptHistory",
        "promptHistoryRecordOnSubmit",
        "promptHistoryRecordOnCmdBackspace",
        "promptHistoryRecordOnSelectionClear",
        "promptHistoryLimit",
        "tabNavigationRingSize",
        "iosHardwareKeyboardSettings",
        websiteDataStoreVersionKey,
        "version",
        "quiperVersion",
        "hasCompletedIOSOnboarding"
    ]

    private static let websiteDataStoreVersionKey = "iosWebsiteDataStoreVersion"

    private static let knownLegacySettingKeys: Set<String> = [
        "selectorDisplayMode",
        "showPromptRecordingGlow"
    ]

    private static func preservingMacShortcutFields(
        in encodedObject: [String: Any],
        from previousObject: [String: Any]
    ) -> [String: Any] {
        var result = encodedObject
        result["services"] = mergingNestedField(
            "activationShortcut",
            current: encodedObject["services"],
            previous: previousObject["services"]
        )
        result["customActions"] = mergingNestedField(
            "shortcut",
            current: encodedObject["customActions"],
            previous: previousObject["customActions"]
        )
        return result
    }

    private static func mergingNestedField(
        _ field: String,
        current: Any?,
        previous: Any?
    ) -> Any? {
        guard var currentItems = current as? [[String: Any]],
              let previousItems = previous as? [[String: Any]] else {
            return current
        }
        let previousByID = previousItems.reduce(into: [UUID: [String: Any]]()) { result, item in
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  result[id] == nil else { return }
            result[id] = item
        }
        for index in currentItems.indices {
            guard let idString = currentItems[index]["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let value = previousByID[id]?[field] else { continue }
            currentItems[index][field] = value
        }
        return currentItems
    }
}
