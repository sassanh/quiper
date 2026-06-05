import AppKit
import WebKit

extension MainWindowController {
    
    // MARK: - Actions & Menus
    
    @objc func sessionActionsButtonTapped(_ sender: NSButton) {
        let menu = buildSessionActionsMenu()
        guard !menu.items.isEmpty else { return }
        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
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
                    layoutSelectors()
                }
            } catch {
                NSLog("[MainWindowController] Manual lock unmount failed: %@", error.localizedDescription)
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
        }
    }
    
    func setupInactivityMonitoring() {
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved]) { [weak self] event in
            self?.lastActivityTime = Date()
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
                        if self.currentService()?.id == service.id {
                            self.updateActiveWebview(focusWebView: false)
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
    func webViewDidUpdateTitle(_ title: String, for webView: WKWebView) {
        guard webView == currentWebView() else { return }
        updateTitleLabel(from: webView)
    }
    
    func webViewDidUpdateLoading(_ isLoading: Bool, for webView: WKWebView) {
        guard webView == currentWebView() else { return }
        updateLoadingIndicator(for: webView)
    }
    
    func webViewDidFinishNavigation(_ webView: WKWebView) {
        guard webView == currentWebView() else { return }
        
        if webView.title?.isEmpty ?? true {
             updateTitleLabel(withFallback: "-")
        }
        
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
        updateSessionSelector()
        layoutSelectors()
    }
}
