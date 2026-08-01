import AppKit
import WebKit

struct TabIdentifier: Equatable, Codable, Hashable {
    let serviceID: UUID
    let sessionIndex: Int
}

extension MainWindowController {
    
    // MARK: - Session & Service Management
    
    func selectService(withID id: UUID) -> Bool {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return false }
        selectService(at: index)
        return true
    }
    
    func selectService(at index: Int) {
        selectService(at: index, focusWebView: true)
    }

    func selectService(at index: Int, focusWebView: Bool = true) {
        if isCyclingHistory && !isExecutingHistoryNavigation {
            endHistoryCycling()
        }
        guard services.indices.contains(index) else { return }
        let selectedService = services[index]

        if let previousService = currentService() {
            if selectedService.id != previousService.id {
                handleSwitchAway(from: previousService)
            }
        }
        
        currentServiceName = selectedService.name
        currentServiceID = selectedService.id
        
        serviceSelector?.selectedSegment = index
        collapsibleServiceSelector?.selectedSegment = index
        let activeServiceLabel = "Active: \(services[index].name)"
        serviceSelector?.setAccessibilityLabel(activeServiceLabel)
        collapsibleServiceSelector?.setAccessibilityLabel(activeServiceLabel)

        if let sel = activeServiceSelector {
            NSAccessibility.post(element: sel, notification: .valueChanged)
        }
        
        updateActiveWebview(focusWebView: focusWebView)
        updateSessionSelector()
        layoutSelectors()
        
        showHeaderTemporarily()
        GhostOnboardingManager.shared.serviceDidSwitch()
        saveTabsState()
    }

    func switchSession(to index: Int) {
        switchSession(to: index, forceCreate: true)
    }

    func switchSession(to index: Int, forceCreate: Bool) {
        if isCyclingHistory && !isExecutingHistoryNavigation {
            endHistoryCycling()
        }
        guard let service = currentService() else { return }
        
        if service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
            NSLog("[MainWindowController] Session switching disabled for locked engine: %@", service.name)
            return
        }
        
        let bounded = max(0, min(index, 9))
        activeIndicesByID[service.id] = bounded
        
        let segmentIdx = segmentIndex(forSession: bounded)
        sessionSelector?.selectedSegment = segmentIdx
        collapsibleSessionSelector?.selectedSegment = segmentIdx
        
        if let svcIndex = services.firstIndex(where: { $0.id == service.id }) {
            serviceSelector?.selectedSegment = svcIndex
            collapsibleServiceSelector?.selectedSegment = svcIndex
        }
        
        if let sel = activeSessionSelector {
            NSAccessibility.post(element: sel, notification: .valueChanged)
        }
        
        updateActiveWebview(focusWebView: true, forceCreate: forceCreate)
        layoutSelectors()
        
        showHeaderTemporarily()
        GhostOnboardingManager.shared.sessionDidSwitch()
        saveTabsState()
    }

    func reloadServices() {
        reloadServices(Settings.shared.services)
    }

    func reloadServices(_ services: [Service]? = nil) {
        let newServices = services ?? Settings.shared.loadSettings()
        updateServices(newServices: newServices)
    }

    private func updateServices(newServices: [Service]) {
        let incomingIDs = Set(newServices.map { $0.id })
        let existingIDs = Set(activeIndicesByID.keys)

        let removedIDs = existingIDs.subtracting(incomingIDs)
        for id in removedIDs {
            activeIndicesByID.removeValue(forKey: id)
        }
        
        for service in newServices where activeIndicesByID[service.id] == nil {
             activeIndicesByID[service.id] = 0
        }

        webViewManager.updateServices(newServices)
        services = newServices
        syncCurrentServiceSelection()
        refreshServiceSegments()
        updateActiveWebview()
    }

    func getOrCreateWebview(for service: Service, sessionIndex: Int) -> WKWebView {
        guard let manager = webViewManager else {
            NSLog("[Quiper] WARNING: getOrCreateWebview called before webViewManager initialized. Returning dummy.")
            return WKWebView(frame: .zero)
        }
        
        let wasInstantiated = manager.getWebView(for: service, sessionIndex: sessionIndex) != nil
        let webView = manager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea)
        
        if !wasInstantiated {
            setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
            refreshInstantiationState()
        }
        
        return webView
    }
    
    func refreshInstantiationState() {
        collapsibleServiceSelector?.refreshInstantiationState()
        collapsibleSessionSelector?.refreshInstantiationState()
        
        serviceSelector?.needsDisplay = true
        sessionSelector?.needsDisplay = true
        
        updateEmptyStateShortcuts()
    }

    func currentService() -> Service? {
        if let currentID = currentServiceID,
           let match = services.first(where: { $0.id == currentID }) {
            currentServiceName = match.name
            return match
        }
        if let name = currentServiceName,
           let match = services.first(where: { $0.name == name }) {
            currentServiceID = match.id
            return match
        }
        currentServiceName = services.first?.name
        currentServiceID = services.first?.id
        return services.first
    }

    func updateActiveWebview(focusWebView: Bool = true, forceCreate: Bool = false) {
        guard let service = currentService(), webViewManager != nil else { return }
        let activeIndex = activeIndicesByID[service.id] ?? 0
        let currentTab = TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
        let existingTargetWebView = webViewManager.getWebView(for: service, sessionIndex: activeIndex)
        if findBarViewController?.webView !== existingTargetWebView {
            findBarViewController?.tabWillHide()
        }

        if let oldTab = lastActiveTab,
           let oldService = services.first(where: { $0.id == oldTab.serviceID }),
           let oldWV = webViewManager.getWebView(for: oldService, sessionIndex: oldTab.sessionIndex) {
            oldWV.takeSnapshot(with: nil) { [weak self] image, error in
                guard let img = image, error == nil else { return }
                DispatchQueue.main.async {
                    self?.tabPreviews[oldTab] = img
                }
            }
        }
        
        tabHistory = tabHistory.filter { tab in
            guard let svc = services.first(where: { $0.id == tab.serviceID }) else { return false }
            return webViewManager.getWebView(for: svc, sessionIndex: tab.sessionIndex) != nil
        }
        
        if lastActiveTab != currentTab {
            if !isCyclingHistory {
                tabHistory.removeAll { $0 == currentTab }
                if let oldTab = lastActiveTab {
                    tabHistory.removeAll { $0 == oldTab }
                    tabHistory.insert(oldTab, at: 0)
                    let ringSize = Settings.shared.tabNavigationRingSize
                    if tabHistory.count > ringSize - 1 {
                        tabHistory = Array(tabHistory.prefix(ringSize - 1))
                    }
                }
            }
            lastActiveTab = currentTab
        }
        
        let hasAnySession = (0..<10).contains { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
        if !hasAnySession && !Settings.shared.autoCreateSessionOnEmptyEngineActivation && !forceCreate {
            webViewManager.hideAll()
            showEmptyState()
            return
        }
        
        hideEmptyState()
        webViewManager.hideAll()
        
        let activeWebview = getOrCreateWebview(for: service, sessionIndex: activeIndex)
        findBarViewController = findBarController(for: activeWebview)

        webViewManager.showSession(activeWebview)
        let restoredFindBarFocus = findBarViewController.tabDidShow()
        
        if let zoom = Settings.shared.serviceZoomLevels[service.id] {
            webViewManager.applyZoom(zoom, for: service.id)
        }
        
        updateTitleLabel(from: activeWebview)
        updateTitleLabel(from: activeWebview)
        
        observeNavigationState(of: activeWebview)
        
        if focusWebView, !restoredFindBarFocus, !GhostOnboardingManager.shared.isActive {
            if webViewManager.hasVisibleLoadError(for: activeWebview) {
                webViewManager.focusLoadError(for: activeWebview)
            } else {
                window?.makeFirstResponder(activeWebview)
                focusInputInActiveWebview()
            }
        }
    }
    
    func stepSession(by delta: Int) {
        guard let service = currentService() else { return }
        let current = activeIndicesByID[service.id] ?? 0
        let next = (current + delta + 10) % 10
        switchSession(to: next)
    }

    func stepService(by delta: Int) {
        guard !services.isEmpty else { return }
        let currentIndex = services.firstIndex(where: { $0.id == currentServiceID }) ??
                           services.firstIndex(where: { $0.name == currentServiceName }) ??
                           0
        let next = (currentIndex + delta + services.count) % services.count
        selectService(at: next)
    }

    func closeCurrentTab() {
        guard let service = currentService() else { return }
        let currentSession = activeIndicesByID[service.id] ?? 0
        let currentServiceIndex = services.firstIndex(where: { $0.id == service.id }) ?? 0

        let closedTab = TabIdentifier(serviceID: service.id, sessionIndex: currentSession)
        tabHistory.removeAll { $0 == closedTab }
        if lastActiveTab == closedTab {
            lastActiveTab = nil
        }

        removeWebViewAndCleanObserver(for: service, sessionIndex: currentSession)

        let remainingSessionsCount = (0..<10).filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }.count
        if remainingSessionsCount == 0 {
            activeIndicesByID[service.id] = 0
        }

        func nearestInstantiatedSession(in svc: Service, excluding: Int? = nil) -> Int? {
            let sessions = (0..<10).filter { $0 != excluding && webViewManager.getWebView(for: svc, sessionIndex: $0) != nil }
            return sessions.first
        }

        let leftSessions  = stride(from: currentSession - 1, through: 0, by: -1)
        let rightSessions = stride(from: currentSession + 1, to: 10, by: 1)

        for idx in leftSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
            switchSession(to: idx)
            refreshInstantiationState()
            return
        }
        for idx in rightSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
            switchSession(to: idx)
            refreshInstantiationState()
            return
        }

        if Settings.shared.automaticallySwitchEngineOnLastSessionClose {
            let leftServices  = stride(from: currentServiceIndex - 1, through: 0, by: -1).map { services[$0] }
            let rightServices = stride(from: currentServiceIndex + 1, to: services.count, by: 1).map { services[$0] }

            for svc in (leftServices + rightServices) {
                let activeSession = activeIndicesByID[svc.id] ?? 0
                let targetSession: Int?
                if webViewManager.getWebView(for: svc, sessionIndex: activeSession) != nil {
                    targetSession = activeSession
                } else {
                    targetSession = nearestInstantiatedSession(in: svc)
                }
                if let session = targetSession {
                    let svcIndex = services.firstIndex(where: { $0.id == svc.id })!
                    activeIndicesByID[svc.id] = session
                    selectService(at: svcIndex)
                    refreshInstantiationState()
                    return
                }
            }
        }

        showEmptyState()
        refreshInstantiationState()
    }

    @objc func performClose(_ sender: Any?) {
        closeCurrentTab()
    }

    func handleSessionMiddleClick(at segmentIndex: Int) {
        let sessionIndex = self.sessionIndex(forSegment: segmentIndex)
        guard let service = currentService() else { return }
        
        guard webViewManager.getWebView(for: service, sessionIndex: sessionIndex) != nil else { return }
        
        let currentSession = activeIndicesByID[service.id] ?? 0
        
        removeWebViewAndCleanObserver(for: service, sessionIndex: sessionIndex)
        
        let remainingSessionsCount = (0..<10).filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }.count
        if remainingSessionsCount == 0 {
            activeIndicesByID[service.id] = 0
        }
        
        if sessionIndex == currentSession {
            let leftSessions  = stride(from: sessionIndex - 1, through: 0, by: -1)
            let rightSessions = stride(from: sessionIndex + 1, to: 10, by: 1)
            
            for idx in leftSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
                switchSession(to: idx)
                refreshInstantiationState()
                return
            }
            for idx in rightSessions where webViewManager.getWebView(for: service, sessionIndex: idx) != nil {
                switchSession(to: idx)
                refreshInstantiationState()
                return
            }
            
            if Settings.shared.automaticallySwitchEngineOnLastSessionClose {
                let currentServiceIndex = services.firstIndex(where: { $0.id == service.id }) ?? 0
                let leftServices  = stride(from: currentServiceIndex - 1, through: 0, by: -1).map { services[$0] }
                let rightServices = stride(from: currentServiceIndex + 1, to: services.count, by: 1).map { services[$0] }
                
                for svc in (leftServices + rightServices) {
                    let activeSession = activeIndicesByID[svc.id] ?? 0
                    if webViewManager.getWebView(for: svc, sessionIndex: activeSession) != nil {
                        let svcIndex = services.firstIndex(where: { $0.id == svc.id })!
                        selectService(at: svcIndex)
                        refreshInstantiationState()
                        return
                    }
                    if let anySession = (0..<10).first(where: { webViewManager.getWebView(for: svc, sessionIndex: $0) != nil }) {
                        let svcIndex = services.firstIndex(where: { $0.id == svc.id })!
                        activeIndicesByID[svc.id] = anySession
                        selectService(at: svcIndex)
                        refreshInstantiationState()
                        return
                    }
                }
            }
            
            showEmptyState()
        }
        
        refreshInstantiationState()
    }
    
    func handleServiceMiddleClick(at serviceIndex: Int) {
        guard services.indices.contains(serviceIndex) else { return }
        let service = services[serviceIndex]
        
        let instantiatedSessions = (0..<10).filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
        
        guard !instantiatedSessions.isEmpty else { return }
        
        if instantiatedSessions.count == 1, currentServiceID == service.id {
            let sessionIndex = instantiatedSessions[0]
            removeWebViewAndCleanObserver(for: service, sessionIndex: sessionIndex)
            activeIndicesByID[service.id] = 0
            
            navigateAwayFromService(at: serviceIndex)
            refreshInstantiationState()
        } else {
            collapsibleServiceSelector?.collapse()
            collapsibleSessionSelector?.collapse()
            collapsibleServiceSelector?.isInteractionEnabled = false
            collapsibleSessionSelector?.isInteractionEnabled = false
            
            let alert = NSAlert()
            alert.messageText = "Close all sessions for \(service.name)?"
            alert.informativeText = "\(instantiatedSessions.count) session\(instantiatedSessions.count == 1 ? "" : "s") will be closed."
            alert.addButton(withTitle: "Close All")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            
            collapsibleServiceSelector?.isInteractionEnabled = true
            collapsibleSessionSelector?.isInteractionEnabled = true
            
            if response == .alertFirstButtonReturn {
                closeAllSessionsForService(at: serviceIndex)
            }
        }
    }
    
    func closeAllSessionsForService(at serviceIndex: Int) {
        guard services.indices.contains(serviceIndex) else { return }
        let service = services[serviceIndex]
        
        for sessionIndex in 0..<10 {
            if webViewManager.getWebView(for: service, sessionIndex: sessionIndex) != nil {
                removeWebViewAndCleanObserver(for: service, sessionIndex: sessionIndex)
            }
        }
        activeIndicesByID[service.id] = 0
        
        if currentServiceID == service.id {
            navigateAwayFromService(at: serviceIndex)
        }
        
        refreshInstantiationState()
    }
    
    func navigateAwayFromService(at serviceIndex: Int) {
        let leftServices  = stride(from: serviceIndex - 1, through: 0, by: -1).map { services[$0] }
        let rightServices = stride(from: serviceIndex + 1, to: services.count, by: 1).map { services[$0] }
        
        for svc in (leftServices + rightServices) {
            let activeSession = activeIndicesByID[svc.id] ?? 0
            if webViewManager.getWebView(for: svc, sessionIndex: activeSession) != nil {
                let svcIndex = services.firstIndex(where: { $0.id == svc.id })!
                selectService(at: svcIndex)
                return
            }
            if let anySession = (0..<10).first(where: { webViewManager.getWebView(for: svc, sessionIndex: $0) != nil }) {
                let svcIndex = services.firstIndex(where: { $0.id == svc.id })!
                activeIndicesByID[svc.id] = anySession
                selectService(at: svcIndex)
                return
            }
        }
        
        showEmptyState()
    }
    
    func showEmptyState() {
        findBarViewController?.tabWillHide()
        findBarViewController = nil
        webViewManager.hideAll()
        
        canGoBackObservation = nil
        canGoForwardObservation = nil
        isLoadingNavObservation = nil
        
        titleLabel?.stringValue = ""
        
        if let service = currentService(),
           let idx = services.firstIndex(where: { $0.id == service.id }) {
            serviceSelector?.selectedSegment = idx
            collapsibleServiceSelector?.selectedSegment = idx
        } else {
            serviceSelector?.selectedSegment = -1
            collapsibleServiceSelector?.selectedSegment = -1
        }
        sessionSelector?.selectedSegment = -1
        collapsibleSessionSelector?.selectedSegment = -1
        
        serviceSelector?.needsDisplay = true
        sessionSelector?.needsDisplay = true
        
        if let contentView = window?.contentView {
            updateWindowMarginAndLayout()
            contentView.addSubview(emptyStateView, positioned: .above, relativeTo: nil)
        }
        
        updateEmptyStateShortcuts(force: true)
        emptyStateView.isHidden = false
        
        layoutSelectors()
    }
    
    func updateEmptyStateShortcuts(force: Bool = false) {
        guard force || !emptyStateView.isHidden else { return }
        var openSessions: [UUID: [Int: String]] = [:]
        for service in services {
            var activeSessions: [Int: String] = [:]
            for idx in 0..<10 {
                if webViewManager != nil, let webView = webViewManager.getWebView(for: service, sessionIndex: idx) {
                    let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    activeSessions[idx] = (title == nil || title!.isEmpty) ? "Session \(idx + 1)" : title!
                }
            }
            openSessions[service.id] = activeSessions
        }
        
        emptyStateView.updateShortcuts(
            services: services,
            appShortcuts: Settings.shared.appShortcutBindings,
            openSessions: openSessions,
            activeEngine: currentService()
        )
    }
    
    func setupSessionTitleObserver(for service: Service, sessionIndex: Int, webView: WKWebView) {
        let key = TabIdentifier(serviceID: service.id, sessionIndex: sessionIndex)
        guard sessionTitleObservations[key] == nil else { return }
        
        sessionTitleObservations[key] = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateEmptyStateShortcuts()
            }
        }
    }

    func removeWebViewAndCleanObserver(for service: Service, sessionIndex: Int) {
        webViewManager.removeWebView(for: service, sessionIndex: sessionIndex)
        updateSessionTooltip(for: service, sessionIndex: sessionIndex)
        let key = TabIdentifier(serviceID: service.id, sessionIndex: sessionIndex)
        sessionTitleObservations[key] = nil
        saveTabsState()
    }

    func hideEmptyState() {
        emptyStateView?.isHidden = true
    }

    func handleServiceMouseDown(at index: Int) {
        selectService(at: index, focusWebView: false)
    }

    private func findBarController(for webView: WKWebView) -> FindBarViewController {
        findBarViewControllers = findBarViewControllers.filter { $0.value.webView != nil }
        let key = ObjectIdentifier(webView)
        if let controller = findBarViewControllers[key], controller.webView === webView {
            return controller
        }

        let controller = FindBarViewController()
        controller.delegate = self
        if let tabView = webView.superview {
            controller.attach(to: webView, in: tabView)
        }
        findBarViewControllers[key] = controller
        return controller
    }
}
