import AppKit
import WebKit

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

        // Switching engines never lands on a hidden pinned-tab slot.
        if let current = activeIndicesByID[selectedService.id],
           !selectedService.visibleSessionIndices.contains(current),
           let first = selectedService.visibleSessionIndices.first {
            activeIndicesByID[selectedService.id] = first
        } else if activeIndicesByID[selectedService.id] == nil {
            activeIndicesByID[selectedService.id] = selectedService.visibleSessionIndices.first ?? 0
        }
        
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
        // Cold path: once onboarding completes, the manager is never entered.
        if !Settings.shared.hasCompletedGhostOnboarding {
            GhostOnboardingManager.shared.serviceDidSwitch()
        }
        saveTabsState()
        refreshModifierHUDHighlight()
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
        // Pinned-tab engines only expose slots with a URL defined.
        // Programmatic switches to a hidden slot never create an empty page.
        guard service.visibleSessionIndices.contains(bounded) else { return }
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
        // Cold path: once onboarding completes, the manager is never entered.
        if !Settings.shared.hasCompletedGhostOnboarding {
            GhostOnboardingManager.shared.sessionDidSwitch()
        }
        saveTabsState()
        refreshModifierHUDHighlight()
    }

    func reloadServices() {
        reloadServices(Settings.shared.services)
    }

    func reloadServices(_ services: [Service]? = nil) {
        let newServices = services ?? Settings.shared.loadSettings()
        updateServices(newServices: newServices)
    }

    /// Commit-only behind `TabCloseGate`: engine deletes and encryption flips
    /// destroy live tabs, so the settings flows that mutate services warn
    /// through `unloadInfosNeedingConfirmation(for:)` before reaching this.
    private func updateServices(newServices: [Service]) {
        let incomingIDs = Set(newServices.map { $0.id })
        let existingIDs = Set(activeIndicesByID.keys)

        let removedIDs = existingIDs.subtracting(incomingIDs)
        for id in removedIDs {
            activeIndicesByID.removeValue(forKey: id)
        }

        for service in newServices {
            let visible = service.visibleSessionIndices
            if let current = activeIndicesByID[service.id] {
                if !visible.contains(current), let first = visible.first {
                    activeIndicesByID[service.id] = first
                }
            } else {
                activeIndicesByID[service.id] = visible.first ?? 0
            }
        }

        webViewManager.updateServices(newServices)
        services = newServices
        syncCurrentServiceSelection()
        // Session segment counts must reflect the new model before anything
        // syncs a selection into them: pinned-tab edits change which slots
        // are visible, so a model-fresh index can exceed a stale count.
        updateSessionSelector()
        refreshServiceSegments()
        updateActiveWebview()
        layoutSelectors()
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
        refreshModifierHUDContents()
    }

    // MARK: - Temporary sessions
    //
    // Ephemeral hard-temporary tabs run on an isolated non-persistent store and
    // are temporary by construction. They never flip in place: leaving one
    // means opening a normal tab or closing the private one. No page script
    // runs in them, so websites cannot detect Quiper through injection.

    /// Opens a new ephemeral hard-temporary tab.
    /// No-ops with an error sound when no free slot remains.
    func createQuiperPrivateTemporarySession() {
        guard let service = currentService() else { return }
        // Temporary tabs must land on a visible button, otherwise the user
        // could not see or switch back to them.
        let candidates = service.isPinnedTabs ? service.visibleSessionIndices : Array(SessionSlots.range)
        guard let freeIndex = candidates.first(where: {
            webViewManager.getWebView(for: service, sessionIndex: $0) == nil
        }) else {
            playErrorSound()
            NSLog("[Quiper] No free session slot for temporary tab")
            return
        }
        let webView = webViewManager.getOrCreateWebView(
            for: service,
            sessionIndex: freeIndex,
            dragArea: dragArea,
            isQuiperPrivate: true
        )
        setupSessionTitleObserver(for: service, sessionIndex: freeIndex, webView: webView)
        refreshInstantiationState()
        switchSession(to: freeIndex)
    }

    /// Replaces a session with an ephemeral tab in the same slot. Used by
    /// action fallback: the website would have transformed this tab in place,
    /// so the anonymous tab takes its slot instead of opening beside it. The
    /// previous page (typically logged-out with nothing to keep) is discarded.
    /// Never morphs a webview: the old page is torn down and a fresh
    /// ephemeral one is created at the same index.
    func replaceSessionWithEphemeral(serviceID: UUID, sessionIndex: Int) {
        guard let service = services.first(where: { $0.id == serviceID }) else { return }
        let replacedTab = TabIdentifier(serviceID: serviceID, sessionIndex: sessionIndex)
        guard webViewManager.webView(for: replacedTab) != nil else {
            createEphemeralReplacement(service: service, sessionIndex: sessionIndex)
            return
        }
        Task {
            guard await self.requestCloseTabs([replacedTab], reason: .replaceWithEphemeral) else { return }
            guard let service = self.services.first(where: { $0.id == serviceID }) else { return }
            self.createEphemeralReplacement(service: service, sessionIndex: sessionIndex)
        }
    }

    private func createEphemeralReplacement(service: Service, sessionIndex: Int) {
        let webView = webViewManager.getOrCreateWebView(
            for: service,
            sessionIndex: sessionIndex,
            dragArea: dragArea,
            isQuiperPrivate: true
        )
        setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
        refreshInstantiationState()
        if currentService()?.id == service.id {
            switchSession(to: sessionIndex)
        }
    }

    /// Opens a normal persistent tab when leaving an ephemeral one. Used by
    /// "New Session" from inside a Quiper-private tab.
    func createNormalSessionAfterPrivate() {
        guard let service = currentService() else { return }
        let candidates = service.isPinnedTabs ? service.visibleSessionIndices : Array(SessionSlots.range)
        guard let freeIndex = candidates.first(where: {
            webViewManager.getWebView(for: service, sessionIndex: $0) == nil
        }) else {
            playErrorSound()
            NSLog("[Quiper] No free session slot for new session")
            return
        }
        let webView = webViewManager.getOrCreateWebView(
            for: service,
            sessionIndex: freeIndex,
            dragArea: dragArea,
            isQuiperPrivate: false
        )
        setupSessionTitleObserver(for: service, sessionIndex: freeIndex, webView: webView)
        refreshInstantiationState()
        switchSession(to: freeIndex)
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

    /// Single gate for the currently visible tab. Every HUD highlight and
    /// modifier-ring data source goes through here.
    func currentTabIdentifier() -> TabIdentifier? {
        guard let service = currentService() else { return nil }
        let activeIndex = activeIndicesByID[service.id] ?? 0
        return TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
    }

    func updateActiveWebview(focusWebView: Bool = true, forceCreate: Bool = false) {
        guard let service = currentService(), webViewManager != nil else { return }
        var activeIndex = activeIndicesByID[service.id] ?? 0
        // A pinned-tab slot without a URL has no button and no page.
        // Never auto-create there; an engine with no URLs shows empty state.
        if service.isPinnedTabs, !service.visibleSessionIndices.contains(activeIndex) {
            if let first = service.visibleSessionIndices.first {
                activeIndex = first
                activeIndicesByID[service.id] = first
            } else {
                webViewManager.hideAll()
                webViewManager.hideAllSessionPopups()
                showEmptyState()
                return
            }
        }
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
                    self?.refreshModifierHUDContents()
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
            webViewManager.hideAllSessionPopups()
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

        // Sync last: restoring the active tab's popups re-keys them, so a
        // session switch back to a popup-owning tab leaves the popup (not
        // the shield-blocked webview behind it) holding focus. Matches the
        // overlay show() path order.
        webViewManager.syncPopupVisibility(forActiveTab: currentTab)
    }
    
    func stepSession(by delta: Int) {
        guard let service = currentService() else { return }
        let visible = service.visibleSessionIndices
        guard !visible.isEmpty else { return }
        let current = activeIndicesByID[service.id] ?? visible[0]
        let position = visible.firstIndex(of: current) ?? 0
        let nextPosition = (position + delta % visible.count + visible.count) % visible.count
        switchSession(to: visible[nextPosition])
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

        guard webViewManager.webView(for: closedTab) != nil else {
            reselectAfterClosing(service: service, closedSession: currentSession, closedServiceIndex: currentServiceIndex)
            return
        }
        Task {
            guard await self.requestCloseTabs([closedTab], reason: .closeCurrentSession) else { return }
            self.reselectAfterClosing(service: service, closedSession: currentSession, closedServiceIndex: currentServiceIndex)
        }
    }

    /// Picks the tab to show after `closedSession` is gone: nearest live
    /// session to the left, then right, then a neighboring engine when the
    /// setting allows, otherwise the empty state. Shared by every path that
    /// closes the active tab.
    func reselectAfterClosing(service: Service, closedSession: Int, closedServiceIndex: Int) {
        func nearestInstantiatedSession(in svc: Service, excluding: Int? = nil) -> Int? {
            let sessions = (0..<10).filter { $0 != excluding && webViewManager.getWebView(for: svc, sessionIndex: $0) != nil }
            return sessions.first
        }

        let remainingSessionsCount = (0..<10).filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }.count
        if remainingSessionsCount == 0 {
            activeIndicesByID[service.id] = 0
        }

        let leftSessions  = stride(from: closedSession - 1, through: 0, by: -1)
        let rightSessions = stride(from: closedSession + 1, to: 10, by: 1)

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
            let leftServices  = stride(from: closedServiceIndex - 1, through: 0, by: -1).map { services[$0] }
            let rightServices = stride(from: closedServiceIndex + 1, to: services.count, by: 1).map { services[$0] }

            for svc in (leftServices + rightServices) {
                let activeSession = activeIndicesByID[svc.id] ?? 0
                let targetSession: Int?
                if webViewManager.getWebView(for: svc, sessionIndex: activeSession) != nil {
                    targetSession = activeSession
                } else {
                    targetSession = nearestInstantiatedSession(in: svc)
                }
                if let session = targetSession {
                    guard let svcIndex = services.firstIndex(where: { $0.id == svc.id }) else { continue }
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

        let closedTab = TabIdentifier(serviceID: service.id, sessionIndex: sessionIndex)
        guard webViewManager.webView(for: closedTab) != nil else { return }

        let currentSession = activeIndicesByID[service.id] ?? 0
        let currentServiceIndex = services.firstIndex(where: { $0.id == service.id }) ?? 0
        Task {
            guard await self.requestCloseTabs([closedTab], reason: .closeCurrentSession) else { return }

            let remainingSessionsCount = (0..<10).filter { self.webViewManager.getWebView(for: service, sessionIndex: $0) != nil }.count
            if remainingSessionsCount == 0 {
                self.activeIndicesByID[service.id] = 0
            }

            if sessionIndex == currentSession {
                self.reselectAfterClosing(service: service, closedSession: sessionIndex, closedServiceIndex: currentServiceIndex)
            } else {
                self.refreshInstantiationState()
            }
        }
    }
    
    func handleServiceMiddleClick(at serviceIndex: Int) {
        guard services.indices.contains(serviceIndex) else { return }
        let service = services[serviceIndex]

        let instantiatedSessions = (0..<10).filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }

        guard !instantiatedSessions.isEmpty else { return }

        if instantiatedSessions.count == 1, currentServiceID == service.id {
            let closedTab = TabIdentifier(serviceID: service.id, sessionIndex: instantiatedSessions[0])
            Task {
                guard await self.requestCloseTabs([closedTab], reason: .closeCurrentSession) else { return }
                self.activeIndicesByID[service.id] = 0

                self.navigateAwayFromService(at: serviceIndex)
                self.refreshInstantiationState()
            }
        } else {
            collapsibleServiceSelector?.collapse()
            collapsibleSessionSelector?.collapse()
            collapsibleServiceSelector?.isInteractionEnabled = false
            collapsibleSessionSelector?.isInteractionEnabled = false

            Task {
                let tabs = instantiatedSessions.map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
                // Bulk closes always confirm. Without unsaved page state the
                // gate shows the pre-existing count dialog; otherwise the
                // unsaved-changes warning names the affected sessions.
                let blocking = await self.webViewManager.tabsRequiringConfirmation(tabs)
                let confirmed: Bool
                if blocking.isEmpty {
                    confirmed = self.runCloseAllSessionsAlert(serviceName: service.name, count: instantiatedSessions.count)
                } else {
                    confirmed = await self.confirmUnload(tabs: blocking, reason: .closeAllSessions(serviceName: service.name))
                }

                self.collapsibleServiceSelector?.isInteractionEnabled = true
                self.collapsibleSessionSelector?.isInteractionEnabled = true

                if confirmed {
                    self.closeAllSessionsForService(at: serviceIndex)
                }
            }
        }
    }

    private func runCloseAllSessionsAlert(serviceName: String, count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close all sessions for \(serviceName)?"
        alert.informativeText = "\(count) session\(count == 1 ? "" : "s") will be closed."
        alert.addButton(withTitle: "Close All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Commit-only behind the gate: destroys every live session of the
    /// engine and navigates away. Confirmation happens in
    /// `handleServiceMiddleClick` before reaching this.
    func closeAllSessionsForService(at serviceIndex: Int) {
        guard services.indices.contains(serviceIndex) else { return }
        let service = services[serviceIndex]

        let tabs = (0..<10)
            .filter { webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
            .map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
        commitClosingTabs(tabs)
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
        webViewManager.hideAllSessionPopups()
        windowOutlineView?.setLoading(false)
        
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
                self?.refreshModifierHUDContents()
            }
        }
    }

    func removeWebViewAndCleanObserver(for service: Service, sessionIndex: Int) {
        removeTabWithoutSaving(for: service.id, sessionIndex: sessionIndex)
        saveTabsState()
    }

    /// Single-tab teardown without persisting. Bulk closes batch through
    /// `commitClosingTabs`, which persists once at the end.
    func removeTabWithoutSaving(for serviceID: UUID, sessionIndex: Int) {
        if let service = services.first(where: { $0.id == serviceID }) {
            webViewManager.removeWebView(for: service, sessionIndex: sessionIndex)
            updateSessionTooltip(for: service, sessionIndex: sessionIndex)
        } else {
            webViewManager.removeWebView(for: serviceID, sessionIndex: sessionIndex)
        }
        sessionTitleObservations[TabIdentifier(serviceID: serviceID, sessionIndex: sessionIndex)] = nil
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
