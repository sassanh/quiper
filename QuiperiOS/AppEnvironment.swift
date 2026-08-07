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
    @Published var promptHistoryLimit: Int = 100

    private let settingsURL: URL
    private var webSessions: [UUID: [Int: WebViewSession]] = [:]

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
        session.onPromptRecorded = { [weak self] text in
            self?.recordPrompt(text, for: serviceID, sessionIndex: sessionIndex)
        }
        session.onURLChange = { [weak self] url in
            self?.updateSessionURL(for: serviceID, sessionIndex: sessionIndex, url: url)
        }
        session.onTitleChange = { [weak self] title in
            self?.updateSessionTitle(for: serviceID, sessionIndex: sessionIndex, title: title)
        }
        var serviceMap = webSessions[serviceID] ?? [:]
        serviceMap[sessionIndex] = session
        webSessions[serviceID] = serviceMap
        return session
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

    // MARK: - Service management

    func setActiveService(_ id: UUID) {
        persistedTabState.activeServiceID = id
        save()
    }

    func updateService(_ service: Service) {
        guard let index = services.firstIndex(where: { $0.id == service.id }) else { return }
        services[index] = service
        save()
    }

    func addService(_ service: Service) {
        services.append(service)
        ensureSessions(for: service.id)
        save()
        enrichMissingIconsIfNeeded()
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
        services.removeAll { $0.id == serviceID }
        persistedTabState.openTabs[serviceID] = nil
        persistedTabState.tabTitles[serviceID] = nil
        persistedTabState.tabPromptHistories[serviceID] = nil
        persistedTabState.activeIndicesByID[serviceID] = nil
        if persistedTabState.activeServiceID == serviceID {
            persistedTabState.activeServiceID = services.first?.id
        }
        save()
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
        webSessions[serviceID]?.removeValue(forKey: index)
        if persistedTabState.activeIndicesByID[serviceID] == index {
            let remaining = (persistedTabState.openTabs[serviceID] ?? [:]).keys.sorted()
            persistedTabState.activeIndicesByID[serviceID] = remaining.min(by: { abs($0 - index) < abs($1 - index) }) ?? 0
        }
        save()
    }

    func setActiveSession(for serviceID: UUID, index: Int) {
        let slot = SessionSlots.range.contains(index) ? index : 0
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

    func recordPrompt(_ text: String, for serviceID: UUID, sessionIndex: Int) {
        guard enablePromptHistory, promptHistoryRecordOnSubmit else { return }
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
        if let promptHistoryLimit = persisted.promptHistoryLimit {
            self.promptHistoryLimit = promptHistoryLimit
        }

        if let tabState = persisted.persistedTabState {
            persistedTabState = tabState
        } else {
            persistedTabState = PersistedTabState()
        }
        if persistedTabState.activeServiceID == nil ||
           !services.contains(where: { $0.id == persistedTabState.activeServiceID }) {
            persistedTabState.activeServiceID = services.first?.id
        }
        for service in services {
            ensureSessions(for: service.id)
        }
        restoreTabsState()
    }

    /// Mirrors the macOS `restoreTabsState`: re-instantiates every persisted open
    /// tab with its saved URL, loading only the active session immediately.
    private func restoreTabsState() {
        for tab in persistedTabState.restoredTabs(
            services: services,
            activeIndexProvider: { activeSessionIndex(for: $0) }
        ) {
            _ = webViewSession(
                for: tab.serviceID,
                sessionIndex: tab.sessionIndex,
                initialURL: tab.url,
                loadImmediately: tab.loadImmediately
            )
        }
    }

    func save() {
        let payload = PersistedSettings(
            services: services,
            customActions: customActions,
            colorScheme: colorScheme,
            persistedTabState: persistedTabState,
            enablePromptHistory: enablePromptHistory,
            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
            promptHistoryLimit: promptHistoryLimit,
            version: 1
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
}
