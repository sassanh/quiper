import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var services: [Service] = []
    @Published var persistedTabState = PersistedTabState()
    @Published var colorScheme: AppColorScheme = .system
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
    private(set) var isRingOverlayActive = false

    private let settingsURL: URL
    private var webSessions: [UUID: [Int: WebViewSession]] = [:]
    private(set) var sessionThumbnails: [TabIdentifier: UIImage] = [:]
    @Published private(set) var thumbnailsRevision = 0

    init() {
        FaviconFetcher.configure(imageProcessor: UIKitFaviconImageProcessor.self)
        settingsURL = Self.makeSettingsURL()
        load()
        enrichMissingIconsIfNeeded()
    }

    // MARK: - Web view sessions

    func webViewSession(for serviceID: UUID, sessionIndex: Int, initialURL: URL?, loadImmediately: Bool = true) -> WebViewSession {
        if let cached = webSessions[serviceID]?[sessionIndex] {
            return cached
        }
        guard let service = services.first(where: { $0.id == serviceID }) else {
            preconditionFailure("No service for \(serviceID)")
        }
        let session = WebViewSession(service: service, sessionIndex: sessionIndex, initialURL: initialURL, loadImmediately: loadImmediately)
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
            self?.save()
        }
        session.onRequestRestoreInputState = { [weak self] in
            self?.tabInputState(for: serviceID, sessionIndex: sessionIndex)
        }
        session.onSnapshot = { [weak self] image in
            self?.storeThumbnail(image, for: serviceID, sessionIndex: sessionIndex)
        }
        var serviceMap = webSessions[serviceID] ?? [:]
        serviceMap[sessionIndex] = session
        webSessions[serviceID] = serviceMap
        session.setKeyboardSuppressed(isRingOverlayActive)
        return session
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
        guard let activeServiceID = persistedTabState.activeServiceID else { return services.first }
        return services.first { $0.id == activeServiceID }
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

    // MARK: - Service management

    func setActiveService(_ id: UUID) {
        let newTab = TabIdentifier(serviceID: id, sessionIndex: activeSessionIndex(for: id))
        recordTabHistory(switchingTo: newTab)
        persistedTabState.activeServiceID = id
        if autoCreateSessionOnEmptyEngineActivation, hasNoSessions(for: id) {
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
        services[index] = service
        updateCachedSessions(for: service)
        save()
    }

    /// Persists a remembered routing choice for a host at the top of the engine's
    /// routing rules, mirroring macOS `rememberDecision`.
    func rememberRoutingDecision(host: String, action: RoutingAction, serviceID: UUID) {
        guard !host.isEmpty,
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
        guard let removed = services.first(where: { $0.id == serviceID }) else { return }
        services.removeAll { $0.id == serviceID }
        persistedTabState.openTabs[serviceID] = nil
        persistedTabState.tabTitles[serviceID] = nil
        persistedTabState.tabPromptHistories[serviceID] = nil
        persistedTabState.tabInputs[serviceID] = nil
        persistedTabState.activeIndicesByID[serviceID] = nil
        persistedTabState.tabHistory?.removeAll { $0.serviceID == serviceID }
        sessionThumbnails = sessionThumbnails.filter { $0.key.serviceID != serviceID }
        if lastActiveTab?.serviceID == serviceID {
            lastActiveTab = nil
        }
        if persistedTabState.activeServiceID == serviceID {
            persistedTabState.activeServiceID = services.first?.id
        }
        save()
        purgeWebDataIfNeeded(for: removed)
    }

    /// Purges the removed engine's website data from the shared data store when
    /// the user enabled the setting, mirroring macOS's `WebKitCacheCleaner`.
    private func purgeWebDataIfNeeded(for service: Service) {
        guard shouldPurgeDanglingWebData, let host = URL(string: service.url)?.host else { return }
        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            let matching = records.filter { $0.displayName == host }
            guard !matching.isEmpty else { return }
            store.removeData(ofTypes: dataTypes, for: matching) { }
        }
    }

    // MARK: - Session management

    func ensureSessions(for serviceID: UUID) {
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
        webSessions[serviceID]?.removeValue(forKey: index)
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
        let slot = SessionSlots.range.contains(index) ? index : 0
        let newTab = TabIdentifier(serviceID: serviceID, sessionIndex: slot)
        if let oldService = activeService {
            let oldTab = TabIdentifier(serviceID: oldService.id, sessionIndex: activeSessionIndex(for: oldService.id))
            if oldTab != newTab {
                captureThumbnailWhenLeaving(oldTab)
            }
        }
        recordTabHistory(switchingTo: newTab)
        persistedTabState.activeServiceID = serviceID
        if persistedTabState.openTabs[serviceID] == nil {
            persistedTabState.openTabs[serviceID] = [:]
        }
        if persistedTabState.openTabs[serviceID]?[slot] == nil {
            persistedTabState.openTabs[serviceID]?[slot] = serviceURL(for: serviceID)
        }
        persistedTabState.activeIndicesByID[serviceID] = slot
        webSessions[serviceID]?[slot]?.loadIfNeeded()
        save()
    }

    func updateSessionURL(for serviceID: UUID, sessionIndex: Int, url: URL) {
        let urlString = url.absoluteString
        guard !urlString.isEmpty, urlString != "about:blank" else { return }
        if persistedTabState.openTabs[serviceID] == nil {
            persistedTabState.openTabs[serviceID] = [:]
        }
        persistedTabState.openTabs[serviceID]?[sessionIndex] = urlString
    }

    func updateSessionTitle(for serviceID: UUID, sessionIndex: Int, title: String) {
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

    func runAction(_ action: CustomAction, for serviceID: UUID) {
        guard let service = services.first(where: { $0.id == serviceID }),
              let session = webSessions[serviceID]?[activeSessionIndex(for: serviceID)] else { return }
        let storedScript = actionScript(for: service, action: action)
        let rawScript = storedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let script: String
        if rawScript.isEmpty {
            script = WebScripts.makeActionFallbackScript(actionName: action.name, serviceName: service.name)
        } else {
            script = rawScript
        }

        let wrappedScript = WebScripts.makeActionRunnerScript(script: script)

        session.webView.callAsyncJavaScript(wrappedScript, in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any], let message = dict["quiperError"] as? String {
                    NSLog("[Quiper] Custom action script failed (caught exception): \(message)")
                }
            case .failure(let error):
                NSLog("[Quiper] Custom action script failed (error): \(error)")
            }
        }
    }

    func actionScript(for service: Service, action: CustomAction) -> String {
        if service.templateActionScriptSync[action.id] == true,
           let defaultScript = ActionScripts.defaultScript(for: service, action: action) {
            return defaultScript
        }
        return service.actionScripts[action.id] ?? ""
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
        for serviceIndex in services.indices {
            services[serviceIndex].actionScripts.removeValue(forKey: id)
            services[serviceIndex].templateActionScriptSync.removeValue(forKey: id)
        }
        save()
    }

    func saveCustomActionScript(_ script: String, serviceID: UUID, actionID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[serviceIndex].templateActionScriptSync[actionID] = false
        services[serviceIndex].actionScripts[actionID] = script
        save()
    }

    /// Mirrors macOS `setTemplateActionScriptSync`: turning on follows the bundled
    /// template script (dropping the stored custom one), turning off hands control
    /// back, seeding the custom script with the default when none exists.
    func setTemplateActionScriptSync(_ isInSync: Bool, serviceID: UUID, actionID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let action = customActions.first(where: { $0.id == actionID }),
              let defaultScript = ActionScripts.defaultScript(for: services[serviceIndex], action: action) else {
            return
        }

        services[serviceIndex].templateActionScriptSync[actionID] = isInSync
        if isInSync {
            services[serviceIndex].actionScripts.removeValue(forKey: actionID)
        } else {
            let existingScript = services[serviceIndex].actionScripts[actionID]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingScript.isEmpty {
                services[serviceIndex].actionScripts[actionID] = defaultScript
            }
        }
        save()
    }

    /// Mirrors macOS `setTemplateCustomCSSSync`: turning on follows the bundled
    /// template stylesheet (dropping the stored custom one), turning off hands
    /// control back, seeding the stylesheet with the default.
    func setTemplateCustomCSSSync(_ isInSync: Bool, serviceID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let defaultCSS = ActionScripts.defaultCustomCSS(for: services[serviceIndex]) else {
            return
        }

        services[serviceIndex].templateCustomCSSSync = isInSync
        if isInSync {
            services[serviceIndex].customCSS = nil
        } else {
            services[serviceIndex].customCSS = defaultCSS
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
        guard let template = ActionScripts.defaultServiceTemplate(for: service),
              let defaultID = ActionScripts.defaultActionID(matching: action.name),
              let defaultScript = template.actionScripts[defaultID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !defaultScript.isEmpty else { return }
        let existing = service.actionScripts[action.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty, service.templateActionScriptSync[action.id] != false else { return }
        services[index].templateActionScriptSync[action.id] = true
        services[index].actionScripts.removeValue(forKey: action.id)
    }

    // MARK: - Prompt history

    /// Mirrors macOS `didReceiveInputStateMessage`: each clearing trigger records
    /// only when its own setting is enabled, and no other clear type records.
    func recordPrompt(_ text: String, clearType: String, for serviceID: UUID, sessionIndex: Int) {
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
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
        return baseDir.appendingPathComponent("settings.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: settingsURL),
              let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data) else {
            services = DefaultEngineDefinitions.definitions
            customActions = DefaultActions.defaults
            persistedTabState.activeServiceID = services.first?.id
            for service in services {
                ensureSessions(for: service.id)
            }
            save()
            return
        }

        services = persisted.services.isEmpty ? DefaultEngineDefinitions.definitions : persisted.services
        customActions = persisted.customActions ?? []
        if let colorScheme = persisted.colorScheme {
            self.colorScheme = colorScheme
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
            for service in services {
                if autoCreateSessionOnEmptyEngineActivation {
                    ensureSessions(for: service.id)
                }
            }
            restoreTabsState()
        }
        if persisted.didDecodeLegacyServiceIdentifiers {
            save()
        }
    }

    /// Restores only the active persisted session. Other tabs remain represented
    /// by `PersistedTabState` and are instantiated when the user selects them.
    private func restoreTabsState() {
        guard let serviceID = persistedTabState.activeServiceID,
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

    func save() {
        let payload = PersistedSettings(
            services: services,
            customActions: customActions,
            colorScheme: colorScheme,
            automaticallySwitchEngineOnLastSessionClose: automaticallySwitchEngineOnLastSessionClose,
            autoCreateSessionOnEmptyEngineActivation: autoCreateSessionOnEmptyEngineActivation,
            shouldPurgeDanglingWebData: shouldPurgeDanglingWebData,
            tabSurvivalPolicy: tabSurvivalPolicy,
            persistedTabState: tabSurvivalPolicy == .never ? nil : persistedTabState,
            enablePromptHistory: enablePromptHistory,
            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
            promptHistoryRecordOnCmdBackspace: promptHistoryRecordOnCmdBackspace,
            promptHistoryRecordOnSelectionClear: promptHistoryRecordOnSelectionClear,
            promptHistoryLimit: promptHistoryLimit,
            tabNavigationRingSize: tabNavigationRingSize,
            version: 1
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
}
