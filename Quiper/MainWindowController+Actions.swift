import AppKit
import WebKit

extension MainWindowController {
    
    // MARK: - Actions & Menus

    func configureHUDPanel(_ panel: NSPanel, parentWindow: NSWindow) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = parentWindow.level
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    func raiseHUDWindow(_ hudWindow: NSWindow?) {
        guard let parentWindow = window, let hudWindow = hudWindow, hudWindow.isVisible else { return }
        hudWindow.level = parentWindow.level
        parentWindow.addChildWindow(hudWindow, ordered: .above)
        hudWindow.orderFront(nil)
    }

    func raiseVisibleHUDs() {
        raiseHUDWindow(tabHistoryHUDWindow)
        raiseHUDWindow(promptHistoryHUDWindow)
        raiseHUDWindow(modifierHUDWindow)
    }
    
    @objc func sessionActionsButtonTapped(_ sender: NSButton) {
        GhostOnboardingManager.shared.advanceFromMenuClick()
        let menu = buildSessionActionsMenu()
        guard !menu.items.isEmpty else { return }
        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc func promptHistoryButtonTapped(_ sender: HoverIconButton) {
        togglePromptHistoryHUD()
    }

    func showPromptHistoryHUD() {
        guard let parentWindow = window else { return }
        hideModifierHUD()
        cancelHistoryCycling()
        
        if promptHistoryHUDWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            configureHUDPanel(panel, parentWindow: parentWindow)
            
            let hud = PromptHistoryHUDView(frame: panel.contentView?.bounds ?? .zero, windowController: self)
            hud.autoresizingMask = [.width, .height]
            panel.contentView = hud
            
            promptHistoryHUDView = hud
            promptHistoryHUDWindow = panel
            
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        
        alignHUDWindow(promptHistoryHUDWindow, width: 520, height: 480)
        promptHistoryHUDWindow?.orderFront(nil)
        raiseHUDWindow(promptHistoryHUDWindow)
        promptHistoryHUDView?.show()
    }

    func hidePromptHistoryHUD() {
        if let hud = promptHistoryHUDView, !hud.isHidden, !hud.isHiding {
            hud.hide()
            return
        }
        promptHistoryHUDWindow?.orderOut(nil)
    }

    func alignHUDWindow(_ hudWindow: NSWindow?, width: CGFloat, height: CGFloat, offsetY: CGFloat = -50) {
        guard let parentWindow = window, let hudWindow = hudWindow else { return }
        
        let parentFrame = parentWindow.frame
        let screenFrame = (parentWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        var targetX = parentFrame.midX - (width / 2)
        var targetY = parentFrame.midY - (height / 2) + offsetY
        
        // Clamp to screen bounds
        if targetX < screenFrame.minX {
            targetX = screenFrame.minX
        } else if targetX + width > screenFrame.maxX {
            targetX = screenFrame.maxX - width
        }
        
        if targetY < screenFrame.minY {
            targetY = screenFrame.minY
        } else if targetY + height > screenFrame.maxY {
            targetY = screenFrame.maxY - height
        }
        
        hudWindow.setFrame(NSRect(x: targetX, y: targetY, width: width, height: height), display: true, animate: false)
    }

    func togglePromptHistoryHUD() {
        if let hud = promptHistoryHUDView, hud.isHiding {
            return
        } else if let hud = promptHistoryHUDView, !hud.isHidden {
            hidePromptHistoryHUD()
        } else {
            showPromptHistoryHUD()
        }
    }

    @objc func manualLockTapped(_ sender: NSButton) {
        guard let service = currentService(), service.isEncrypted else { return }
        
        NSLog("[MainWindowController] Manual lock requested for service: %@", service.name)
        webViewManager.tearDownAllWebViews(for: service)
        
        updateSessionSelector()
        
        Task {
            do {
                try await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
                await MainActor.run {
                    updateActiveWebview(focusWebView: true, forceCreate: true)
                    updateSessionSelector()
                    refreshServiceSegments()
                    layoutSelectors()
                }
            } catch {
                NSLog("[MainWindowController] Manual lock unmount failed: %@", error.localizedDescription)
            }
        }
    }

    @objc func handleLockCurrentEngineShortcut() {
        guard let service = currentService() else { return }
        
        if service.isEncrypted {
            if EncryptedVolumeManager.shared.isMounted(for: service.id) {
                manualLockTapped(NSButton())
            }
        } else {
            promptToSecureEngine(service)
        }
    }
    
    @objc func handleLockAllEnginesShortcut() {
        let secureServices = services.filter { $0.isEncrypted }
        
        if secureServices.isEmpty {
            if let service = currentService() {
                promptToSecureEngine(service)
            }
        } else {
            for service in secureServices {
                if EncryptedVolumeManager.shared.isMounted(for: service.id) {
                    webViewManager.tearDownAllWebViews(for: service)
                    Task {
                        try? await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
                        if self.currentService()?.id == service.id {
                            await MainActor.run {
                                self.updateActiveWebview(focusWebView: true, forceCreate: true)
                                self.updateSessionSelector()
                                self.layoutSelectors()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func promptToSecureEngine(_ service: Service) {
        let alert = NSAlert()
        alert.messageText = "Secure Engine"
        alert.informativeText = "The current engine (\(service.name)) is not secured. Would you like to enable secure storage for this engine?"
        alert.addButton(withTitle: "Enable Secure Storage")
        alert.addButton(withTitle: "Cancel")
        
        if let window = window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    NotificationCenter.default.post(name: .showSettings, object: nil, userInfo: [
                        "tab": "Engines",
                        "serviceID": service.id,
                        "subtab": "security"
                    ])
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NotificationCenter.default.post(name: .showSettings, object: nil, userInfo: [
                    "tab": "Engines",
                    "serviceID": service.id,
                    "subtab": "security"
                ])
            }
        }
    }

    @objc func refreshStopTapped(_ sender: NSButton) {
        guard let webView = currentWebView() else { return }
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    @objc func closeSessionTapped(_ sender: NSButton) {
        closeCurrentTab()
    }

    func buildSessionActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Session Actions")
        menu.autoenablesItems = false

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = MenuFactory.createEditMenu()
        editMenu.autoenablesItems = false
        editItem.submenu = editMenu
        menu.addItem(editItem)
        
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = MenuFactory.createViewMenu()
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        
        let actionsItem = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        let actionsMenu = MenuFactory.createActionsMenu()
        actionsItem.submenu = actionsMenu
        menu.addItem(actionsItem)
        
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = MenuFactory.createWindowMenu()
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = MenuFactory.createHelpMenu()
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)
        
        menu.addItem(.separator())
        menu.addItem(MenuFactory.createSettingsItem())
        menu.addItem(.separator())
        menu.addItem(MenuFactory.createQuitItem())
        
        return menu
    }

    @objc func performMenuZoomIn(_ sender: Any?) {
        zoom(by: Zoom.step)
    }

    @objc func performMenuZoomOut(_ sender: Any?) {
        zoom(by: -Zoom.step)
    }

    @objc func performMenuResetZoom(_ sender: Any?) {
        guard let service = currentService() else { return }
        webViewManager.applyZoom(Zoom.default, for: service.url)
        Settings.shared.clearZoomLevel(for: service.url)
    }

    func zoom(by delta: CGFloat) {
        guard let service = currentService() else { return }
        let currentZoom = Settings.shared.serviceZoomLevels[service.url] ?? Zoom.default
        let nextZoom = max(Zoom.min, min(Zoom.max, currentZoom + delta))
        
        webViewManager.applyZoom(nextZoom, for: service.url)
        Settings.shared.storeZoomLevel(nextZoom, for: service.url)
    }

    @objc func performMenuHideWindow(_ sender: Any?) {
        hide()
    }

    @objc func performMenuQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc func reloadActiveWebView(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        webView.reload()
    }

    @objc func reloadActiveWebViewFromOrigin(_ sender: Any?) {
        guard let webView = currentWebView() else { return }
        webView.reloadFromOrigin()
    }

    @objc func reinstantiateActiveWebView(_ sender: Any?) {
        guard let service = currentService(),
              let webView = currentWebView(),
              let url = URL(string: service.url) else { return }
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func presentFindPanelFromMenu(_ sender: Any?) {
        findBarViewController.show()
    }

    @objc func performMenuToggleInspector(_ sender: Any?) {
        toggleInspector()
    }

    @objc func performMenuToggleControlCenter(_ sender: Any?) {
        guard Settings.shared.enableHUDCmdEscape else { return }
        toggleModifierHUD()
    }

    @objc func performCustomActionFromMenu(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CustomAction else { return }
        performCustomAction(action)
    }

    func serviceURL(for webView: WKWebView) -> URL? {
        return webViewManager.serviceURL(for: webView)
    }
    
    func handleSwitchAway(from service: Service) {
        guard service.isEncrypted && service.lockOnSwitchAway else { return }
        
        webViewManager.tearDownAllWebViews(for: service)
        Task {
            try? await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
            await MainActor.run {
                self.refreshServiceSegments()
            }
        }
    }
    
    func setupInactivityMonitoring() {
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved,
            .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]) { [weak self] event in
            self?.lastActivityTime = Date()
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                Task { @MainActor [weak self] in
                    guard let self = self, event.window === self.window else { return }
                    self.raiseVisibleHUDs()
                }
            }
            return event
        }
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkInactivityLock()
            }
        }
    }
    
    func checkInactivityLock() {
        let now = Date()
        
        for service in services where service.isEncrypted && service.lockAfterInactivity {
            if EncryptedVolumeManager.shared.isMounted(for: service.id) {
                let timeout: TimeInterval = TimeInterval(service.autoLockInactivityTimeout * 60)
                if now.timeIntervalSince(lastActivityTime) >= timeout {
                    webViewManager.tearDownAllWebViews(for: service)
                    Task {
                        try? await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
                        await MainActor.run {
                            if self.currentService()?.id == service.id {
                                self.updateActiveWebview(focusWebView: false)
                            }
                            self.refreshServiceSegments()
                            self.layoutSelectors()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CollapsibleSelectorDelegate
@MainActor
extension MainWindowController: CollapsibleSelectorDelegate {
    func isLoading(index: Int) -> Bool {
        guard let service = currentService(),
              let webView = webViewManager.getWebView(for: service, sessionIndex: index) else { return false }
        return webView.isLoading
    }
    
    func selector(_ selector: CollapsibleSelector, isInstantiated index: Int) -> Bool {
        if selector === collapsibleServiceSelector {
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            for sessionIdx in 0..<10 {
                if webViewManager.getWebView(for: service, sessionIndex: sessionIdx) != nil {
                    return true
                }
            }
            return false
        } else if selector === collapsibleSessionSelector {
            guard let service = currentService() else { return false }
            return webViewManager.getWebView(for: service, sessionIndex: index) != nil
        }
        return true
    }
    
    func segmentedControl(_ control: SegmentedControl, isInstantiated index: Int) -> Bool {
        if control === serviceSelector {
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            for sessionIdx in 0..<10 {
                if webViewManager.getWebView(for: service, sessionIndex: sessionIdx) != nil {
                    return true
                }
            }
            return false
        } else if control === sessionSelector {
            guard let service = currentService() else { return false }
            return webViewManager.getWebView(for: service, sessionIndex: index) != nil
        }
        return true
    }
    
    func selector(_ selector: CollapsibleSelector, isLocked index: Int) -> Bool {
        if selector === collapsibleServiceSelector {
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            return service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        }
        return false
    }
    
    func segmentedControl(_ control: SegmentedControl, isLocked index: Int) -> Bool {
        if control === serviceSelector {
            guard services.indices.contains(index) else { return false }
            let service = services[index]
            return service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        }
        return false
    }
    
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int) {
    }
    
    func selectorWillExpand(_ selector: CollapsibleSelector) {
        if selector === collapsibleServiceSelector {
            collapsibleSessionSelector?.collapse()
        } else if selector === collapsibleSessionSelector {
            collapsibleServiceSelector?.collapse()
        }
    }
    
    func collapsibleSelector(_ selector: CollapsibleSelector, didChangeExpansionState isExpanded: Bool) {
        if isExpanded {
            startSelectorCursorMonitorIfNeeded()
        }
        updateHeaderVisibility()
    }
    
    private func startSelectorCursorMonitorIfNeeded() {
        guard selectorCursorMonitor == nil else { return }
        selectorCursorMonitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkSelectorSafeZones() }
        }
    }
    
    func stopSelectorCursorMonitor() {
        selectorCursorMonitor?.invalidate()
        selectorCursorMonitor = nil
    }
    
    private func checkSelectorSafeZones() {
        if GhostOnboardingManager.shared.isActive {
            return
        }
        
        let mouse = NSEvent.mouseLocation
        let selectors = [collapsibleSessionSelector, collapsibleServiceSelector].compactMap { $0 }
        var anyExpanded = false
        
        for selector in selectors where selector.isExpanded {
            anyExpanded = true
            
            if isModifiersForHeaderDown { continue }
            if draggingServiceIndex != nil { continue }
            if selector.isTrackingMouse { continue }
            
            if let panel = selector.expandedPanel {
                let safeRect = panel.frame.insetBy(dx: -selector.safeAreaPadding, dy: -selector.safeAreaPadding)
                if !safeRect.contains(mouse) {
                    selector.collapse()
                }
            }
        }
        if !anyExpanded { stopSelectorCursorMonitor() }
    }
}

// MARK: - FindBarDelegate
extension MainWindowController: FindBarDelegate {
    func activeWebViewForFind() -> WKWebView? {
        currentWebView()
    }
}

// MARK: - WebViewManagerDelegate
extension MainWindowController: WebViewManagerDelegate {
    func inputStateRequestSave() {
        saveTabsState()
    }

    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView) {
        guard webView == currentWebView() else { return }
        updateTitleLabel(from: webView)
    }
    
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView) {
        guard webView == currentWebView() else { return }
        updateLoadingIndicator(for: webView)
    }
    
    func webViewDidFinishNavigation(_ webView: WKWebView) {
        saveTabsState()
        guard webView == currentWebView() else { return }
        
        webView.evaluateJavaScript("window.__quiperInputTrackerActive = true", completionHandler: nil)
        
        if webView.title?.isEmpty ?? true {
             updateTitleLabel(withFallback: "-")
        }
        
        // During onboarding, do NOT restore focus to the webview — the HUD must stay first responder
        guard !GhostOnboardingManager.shared.isActive else { return }
        
        window?.makeFirstResponder(webView)
        
        let runFocus: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }
            self.focusInputInActiveWebview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.focusInputInActiveWebview()
            }
        }
        
        DispatchQueue.main.async(execute: runFocus)
    }
    
    func engineDidUnlock(serviceID: UUID) {
        NSLog("[MainWindowController] Engine unlocked successfully: %@", serviceID.uuidString)
        
        if Settings.shared.tabSurvivalPolicy != .never,
           let service = services.first(where: { $0.id == serviceID }) {
            let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID).appendingPathComponent("quiper_tabs.json")
            if let data = try? Data(contentsOf: stateURL),
               let state = try? JSONDecoder().decode(MainWindowController.SecureTabState.self, from: data) {
                
                activeIndicesByURL[service.url] = state.activeIndex
                
                for (sessionIndex, urlString) in state.openTabs {
                    _ = webViewManager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea, targetURL: urlString, loadImmediately: (sessionIndex == state.activeIndex))
                    
                    if let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) {
                        setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
                    }
                }
                
                if currentServiceURL == service.url {
                    updateActiveWebview()
                }
            }
        }
        
        refreshServiceSegments()
        updateSessionSelector()
        layoutSelectors()
    }
}
