import AppKit
import WebKit

final class InteractiveHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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

    func raiseHUDWindow(_ hudWindow: NSWindow?, parent: NSWindow? = nil) {
        guard let parentWindow = parent ?? window, let hudWindow = hudWindow, hudWindow.isVisible else { return }
        hudWindow.level = parentWindow.level
        parentWindow.addChildWindow(hudWindow, ordered: .above)
        hudWindow.orderFront(nil)
    }

    func raiseVisibleHUDs() {
        raiseHUDWindow(tabHistoryHUDWindow)
        raiseHUDWindow(promptHistoryHUDWindow)
        raiseHUDWindow(modifierHUDWindow)
        // The location bar rides on whatever window it addresses — a popup
        // or the main window — never the main window by default.
        raiseHUDWindow(locationBarHUDWindow, parent: locationBarHUDWindow?.parent)
    }

    /// Closes every open HUD whose frame does not contain the clicked point,
    /// so clicking anywhere outside a floating panel dismisses it.
    func dismissHUDsOnOutsideClick(at screenPoint: NSPoint) {
        func containsClick(_ hudWindow: NSWindow?) -> Bool {
            guard let hudWindow, hudWindow.isVisible else { return true }
            return hudWindow.frame.contains(screenPoint)
        }

        if !containsClick(tabHistoryHUDWindow) {
            hideTabHistoryHUD()
        }
        if !containsClick(promptHistoryHUDWindow) {
            hidePromptHistoryHUD()
        }
        if !containsClick(modifierHUDWindow) {
            hideModifierHUD()
        }
        if !containsClick(locationBarHUDWindow) {
            hideLocationBarHUD()
        }
    }
    
    @objc func sessionActionsButtonTapped(_ sender: NSButton) {
        // Cold path: once onboarding completes, the manager is never entered.
        if !Settings.shared.hasCompletedGhostOnboarding {
            GhostOnboardingManager.shared.advanceFromMenuClick()
        }
        let menu = buildSessionActionsMenu()
        guard !menu.items.isEmpty else { return }
        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    /// Builds the page-title context menu for `webView`'s page — the single
    /// menu the main window's title and every popup title show; each item
    /// carries the page it operates on. AppKit positions and tracks it (see
    /// HoverTextField.menu(for:)); no manual pop-up needed.
    func makeTitleContextMenu(for webView: WKWebView?) -> NSMenu {
        let menu = NSMenu(title: "Page Title")
        menu.autoenablesItems = false
        let urlString = webView?.url?.absoluteString
        let titleString = pageTitle(for: webView)

        let copyURLItem = NSMenuItem(
            title: "Copy URL",
            action: #selector(copyCurrentPageURL(_:)),
            keyEquivalent: ""
        )
        copyURLItem.target = self
        copyURLItem.representedObject = webView
        copyURLItem.isEnabled = urlString != nil && !(urlString?.isEmpty ?? true)
        menu.addItem(copyURLItem)

        let copyTitleItem = NSMenuItem(
            title: "Copy Title",
            action: #selector(copyCurrentPageTitle(_:)),
            keyEquivalent: ""
        )
        copyTitleItem.target = self
        copyTitleItem.representedObject = webView
        copyTitleItem.isEnabled = titleString != nil
        menu.addItem(copyTitleItem)

        let openItem = NSMenuItem(
            title: "Open in Default Browser",
            action: #selector(openCurrentPageInBrowser(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.representedObject = webView
        openItem.isEnabled = urlString != nil && !(urlString?.isEmpty ?? true)
        menu.addItem(openItem)

        // The engine behind the menu's own page decides the item: a locked
        // secure engine carries a lock and a reason instead of opening a
        // folder that does not exist while its storage is unmounted.
        let openDownloadsItem = NSMenuItem(
            title: "Open Downloads Folder",
            action: #selector(openEngineDownloadsFolder(_:)),
            keyEquivalent: ""
        )
        openDownloadsItem.target = self
        openDownloadsItem.representedObject = webView
        if let service = webView.flatMap({ webViewManager?.service(for: $0) }) {
            if DownloadDestination.canOpenDownloadsFolder(for: service) {
                openDownloadsItem.isEnabled = true
            } else {
                openDownloadsItem.isEnabled = false
                openDownloadsItem.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
                openDownloadsItem.toolTip = "Unlock “\(service.name)” to open its downloads"
            }
        } else {
            openDownloadsItem.isEnabled = false
        }
        menu.addItem(openDownloadsItem)

        menu.addItem(.separator())

        let findItem = NSMenuItem(
            title: "Find...",
            action: #selector(presentFindPanelFromMenu(_:)),
            keyEquivalent: "f"
        )
        findItem.target = self
        findItem.representedObject = webView
        findItem.isEnabled = webView != nil
        menu.addItem(findItem)

        let suggestItem = NSMenuItem(
            title: "Suggest Selector...",
            action: #selector(startSelectorSuggestMode(_:)),
            keyEquivalent: ""
        )
        suggestItem.target = self
        suggestItem.representedObject = webView
        // The shared Suggest Selector gate: a popup's page is judged through
        // its owning tab, exactly like the page's own right-click menu.
        suggestItem.isEnabled = webView.map {
            webViewManager?.webViewAllowsPageSelectorSuggest($0) == true
        } ?? false
        menu.addItem(suggestItem)

        return menu
    }

    /// The main window's title menu: targets the current page.
    func makeTitleContextMenu() -> NSMenu {
        makeTitleContextMenu(for: currentWebView())
    }

    /// A menu action's target page: the item's own target page, falling
    /// back to the focused one for menu-bar invocations.
    func targetPage(from sender: Any?) -> WKWebView? {
        (sender as? NSMenuItem)?.representedObject as? WKWebView ?? focusedPageWebView()
    }

    /// The popup window the focused UI addresses: the location bar's host
    /// while the bar holds key status, the key popup itself, else nil. The
    /// single key-window resolution — the bar shortcut, Cmd+W, reload, and
    /// find all route through it, so they can never disagree about which
    /// popup the keyboard is acting on.
    func focusedPopupWindow() -> NSWindow? {
        guard let keyWindow = NSApp.keyWindow, let manager = webViewManager else { return nil }
        if keyWindow === locationBarHUDWindow,
           let hostWindow = locationBarHUDWindow?.parent,
           manager.isPopupWindow(hostWindow) {
            return hostWindow
        }
        if manager.isPopupWindow(keyWindow) {
            return keyWindow
        }
        return nil
    }

    /// The page the focused UI addresses: the focused popup's page while a
    /// popup — or the location bar hosted on one — holds key status, else
    /// the main window's current tab. Every page-scoped shortcut and menu
    /// routes through this, so the keyboard always acts on the window the
    /// user is working in.
    func focusedPageWebView() -> WKWebView? {
        if let popupWindow = focusedPopupWindow(),
           let popupWebView = webViewManager?.popupWebView(for: popupWindow) {
            return popupWebView
        }
        return currentWebView()
    }

    /// The page title as shown in the toolbar: the webview's title, falling
    /// back to the main window's label text for its own page. Nil when there
    /// is nothing worth copying.
    func pageTitle(for webView: WKWebView?) -> String? {
        if let title = webView?.title, !title.isEmpty {
            return title
        }
        if (webView == nil || webView === currentWebView()),
           let text = titleLabel?.stringValue, !text.isEmpty {
            return text
        }
        return nil
    }

    @objc func copyCurrentPageURL(_ sender: Any?) {
        guard let urlString = targetPage(from: sender)?.url?.absoluteString,
              !urlString.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    @objc func copyCurrentPageTitle(_ sender: Any?) {
        guard let title = pageTitle(for: targetPage(from: sender)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(title, forType: .string)
    }

    @objc func openCurrentPageInBrowser(_ sender: Any?) {
        guard let url = targetPage(from: sender)?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// The title menu's downloads item: opens the folder for the engine that
    /// owns the menu's page, so the menu for one engine never opens another
    /// engine's downloads.
    @objc func openEngineDownloadsFolder(_ sender: Any?) {
        guard let webView = targetPage(from: sender),
              let service = webViewManager?.service(for: webView) else { return }
        DownloadDestination.openDownloadsFolder(for: service, window: webView.window)
    }

    @objc func promptHistoryButtonTapped(_ sender: HoverIconButton) {
        togglePromptHistoryHUD()
    }

    func showPromptHistoryHUD() {
        guard let parentWindow = window else { return }
        hideModifierHUD()
        hideLocationBarHUD()
        cancelHistoryCycling()
        
        if promptHistoryHUDWindow == nil {
            let panel = InteractiveHUDPanel(
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
        KeyFocusGate.shared.focus(promptHistoryHUDWindow)
        raiseHUDWindow(promptHistoryHUDWindow)
        promptHistoryHUDView?.show()
    }

    func hidePromptHistoryHUD() {
        if let hud = promptHistoryHUDView, !hud.isHidden, !hud.isHiding {
            // The fade orders the window out through this same function
            // when it finishes; move focus now so AppKit never chooses.
            KeyFocusGate.shared.willHide(promptHistoryHUDWindow)
            hud.hide()
            return
        }
        KeyFocusGate.shared.orderOut(promptHistoryHUDWindow)
    }

    func alignHUDWindow(_ hudWindow: NSWindow?, width: CGFloat, height: CGFloat, offsetY: CGFloat = -50) {
        guard let parentWindow = window, let hudWindow = hudWindow else { return }

        let targetY = parentWindow.frame.midY - (height / 2) + offsetY
        hudWindow.setFrame(alignedHUDFrame(width: width, height: height, y: targetY), display: true, animate: false)
    }

    /// Computes a HUD frame centered horizontally over the given window
    /// (the main window by default) at the given bottom-edge Y, clamped to
    /// the visible screen.
    func alignedHUDFrame(width: CGFloat, height: CGFloat, y: CGFloat, hostWindow: NSWindow? = nil) -> NSRect {
        guard let parentWindow = hostWindow ?? window else { return .zero }

        let parentFrame = parentWindow.frame
        let screenFrame = (parentWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var targetX = parentFrame.midX - (width / 2)
        if targetX < screenFrame.minX {
            targetX = screenFrame.minX
        } else if targetX + width > screenFrame.maxX {
            targetX = screenFrame.maxX - width
        }

        var targetY = y
        if targetY < screenFrame.minY {
            targetY = screenFrame.minY
        } else if targetY + height > screenFrame.maxY {
            targetY = screenFrame.maxY - height
        }

        return NSRect(x: targetX, y: targetY, width: width, height: height)
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

    /// The window the location bar addresses: the focused popup, so the bar
    /// edits the page the user is on; the main window otherwise. A bar that
    /// already holds key status keeps its own window.
    private func locationBarTargetWindow() -> NSWindow? {
        focusedPopupWindow() ?? window
    }

    /// The page the location bar edits: the host window's own webview — a
    /// popup's page when the bar hangs off a popup, the current tab
    /// otherwise.
    func locationBarTargetWebView() -> WKWebView? {
        guard let hostWindow = locationBarHUDWindow?.parent else { return currentWebView() }
        if hostWindow !== window, let manager = webViewManager, manager.isPopupWindow(hostWindow) {
            return manager.popupWebView(for: hostWindow)
        }
        return currentWebView()
    }

    func showLocationBarHUD(for hostWindow: NSWindow? = nil) {
        guard let targetWindow = hostWindow ?? locationBarTargetWindow() else { return }
        hideModifierHUD()
        hidePromptHistoryHUD()
        cancelHistoryCycling()

        // Keep the toolbar revealed while the bar is open (matters in
        // auto-hide mode). A popup's toolbar is always visible, so only the
        // main window pins its header.
        isHeaderForcedVisibleForLocationBar = targetWindow === window
        updateHeaderVisibility()

        if locationBarHUDWindow == nil {
            let panel = InteractiveHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: Constants.LocationBarHUD.height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            configureHUDPanel(panel, parentWindow: targetWindow)

            let hud = LocationBarHUDView(frame: panel.contentView?.bounds ?? .zero, windowController: self)
            hud.autoresizingMask = [.width, .height]
            panel.contentView = hud

            locationBarHUDView = hud
            locationBarHUDWindow = panel
        }

        // Host the bar on the window it addresses — a popup's bar lives on
        // the popup, the default on the main window — so one bar
        // implementation serves both.
        if let panel = locationBarHUDWindow, panel.parent !== targetWindow {
            panel.parent?.removeChildWindow(panel)
            panel.level = targetWindow.level
            targetWindow.addChildWindow(panel, ordered: .above)
        }

        alignLocationBarHUDWindow()
        KeyFocusGate.shared.focus(locationBarHUDWindow)
        raiseHUDWindow(locationBarHUDWindow, parent: targetWindow)
        locationBarHUDView?.show()
    }

    func hideLocationBarHUD() {
        if let hud = locationBarHUDView, !hud.isHidden, !hud.isHiding {
            // The fade orders the window out through this same function
            // when it finishes; move focus now so AppKit never chooses.
            KeyFocusGate.shared.willHide(locationBarHUDWindow)
            hud.hide()
            return
        }
        KeyFocusGate.shared.orderOut(locationBarHUDWindow)

        // A popup host must not keep the bar attached after dismissal: the
        // popup can close at any time. The main window stays the bar's home.
        if let panel = locationBarHUDWindow, let hostWindow = panel.parent, hostWindow !== window {
            hostWindow.removeChildWindow(panel)
        }

        if isHeaderForcedVisibleForLocationBar {
            isHeaderForcedVisibleForLocationBar = false
            updateHeaderVisibility()
        }
    }

    func toggleLocationBarHUD() {
        toggleLocationBarHUD(for: nil)
    }

    func toggleLocationBarHUD(for hostWindow: NSWindow?) {
        let targetWindow = hostWindow ?? locationBarTargetWindow()
        let isShowingOnTarget = locationBarHUDWindow?.isVisible == true
            || locationBarHUDView?.isHiding == true
        if isShowingOnTarget, targetWindow === locationBarHUDWindow?.parent {
            if locationBarHUDView?.isHiding == true {
                return // dismissal already in flight (e.g. outside click)
            }
            hideLocationBarHUD()
            return
        }
        showLocationBarHUD(for: targetWindow)
    }

    /// Sizes the bar to its host window's width plus a margin on each side,
    /// and places it right next to that window's toolbar: the main window's
    /// drag area (following whichever edge it currently lives on), or a
    /// popup's always-top strip.
    func alignLocationBarHUDWindow() {
        guard let hostWindow = locationBarHUDWindow?.parent ?? window else { return }
        let width = hostWindow.frame.width + 2 * Constants.LocationBarHUD.sideMargin
        let height = Constants.LocationBarHUD.height

        let isMainWindow = hostWindow === window
        let headerInset = (isMainWindow ? currentMargin : 0) + CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        let gap = Constants.LocationBarHUD.headerGap
        let parentFrame = hostWindow.frame
        let isHeaderAtBottom = isMainWindow && Settings.shared.dragAreaPosition == .bottom

        let targetY = isHeaderAtBottom
            ? parentFrame.minY + headerInset + gap
            : parentFrame.maxY - headerInset - gap - height

        locationBarHUDWindow?.setFrame(
            alignedHUDFrame(width: width, height: height, y: targetY, hostWindow: hostWindow),
            display: true,
            animate: false
        )
    }

    @objc func manualLockTapped(_ sender: NSButton) {
        guard let service = currentService(), service.isEncrypted else { return }

        NSLog("[MainWindowController] Manual lock requested for service: %@", service.name)
        Task {
            let tabs = (0..<10)
                .filter { self.webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
                .map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
            guard await self.requestCloseTabs(tabs, reason: .lockService(serviceName: service.name)) else { return }

            self.prepareForLockingEncryptedService(service)
            self.webViewManager.tearDownAllWebViews(for: service)

            self.updateSessionSelector()

            Task {
                do {
                    try await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
                    await MainActor.run {
                        self.updateActiveWebview(focusWebView: true, forceCreate: true)
                        self.updateSessionSelector()
                        self.refreshServiceSegments()
                        self.layoutSelectors()
                    }
                } catch {
                    NSLog("[MainWindowController] Manual lock unmount failed: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Entry for the `Lock Current Engine` binding. The lock screen decides
    /// the meaning, not the mount probe: while the overlay is up the binding
    /// opens the password fallback, so a volume left mounted by an earlier
    /// run still asks for the password; otherwise the binding locks the
    /// engine.
    @objc func handleLockCurrentEngineShortcut() {
        guard let service = currentService() else { return }
        
        if service.isEncrypted {
            if let overlay = currentLockedEngineOverlay() {
                overlay.usePasswordFallback()
            } else if EncryptedVolumeManager.shared.isMounted(for: service.id) {
                manualLockTapped(NSButton())
            }
        } else {
            promptToSecureEngine(service)
        }
    }

    /// The overlay shielding the active tab while its engine is still locked.
    /// Shared by the lock binding's password fallback and the shortcuts that
    /// must stay inert behind the lock.
    func currentLockedEngineOverlay() -> LockOverlayView? {
        guard let tab = currentTabIdentifier(), let manager = webViewManager else { return nil }
        return manager.lockOverlay(for: tab)
    }
    
    @objc func handleLockAllEnginesShortcut() {
        let secureServices = services.filter { $0.isEncrypted }
        
        if secureServices.isEmpty {
            if let service = currentService() {
                promptToSecureEngine(service)
            }
        } else {
            let mountedServices = secureServices.filter { EncryptedVolumeManager.shared.isMounted(for: $0.id) }
            guard !mountedServices.isEmpty else { return }
            Task {
                let tabs = mountedServices.flatMap { service in
                    (0..<10)
                        .filter { self.webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
                        .map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
                }
                guard await self.requestCloseTabs(tabs, reason: .lockAllServices) else { return }
                for service in mountedServices {
                    self.prepareForLockingEncryptedService(service)
                    self.webViewManager.tearDownAllWebViews(for: service)
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
        alert.buttons[1].keyEquivalent = "\u{1b}"
        
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
        webViewManager.refreshOrStop(webView)
    }

    @objc func closeSessionTapped(_ sender: NSButton) {
        closeCurrentTab()
    }

    /// The header's mouse path to `hide()` — the same dismissal the hide
    /// shortcut takes, with every tab left open.
    @objc func hideWindowTapped(_ sender: NSButton) {
        hide()
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
        let helpMenu = MenuFactory.createHelpMenu(includeAbout: true)
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
        webViewManager.applyZoom(Zoom.default, for: service.id)
        Settings.shared.clearZoomLevel(for: service.id)
    }

    func zoom(by delta: CGFloat) {
        guard let service = currentService() else { return }
        let currentZoom = Settings.shared.serviceZoomLevels[service.id] ?? Zoom.default
        let nextZoom = max(Zoom.min, min(Zoom.max, currentZoom + delta))
        
        webViewManager.applyZoom(nextZoom, for: service.id)
        Settings.shared.storeZoomLevel(nextZoom, for: service.id)
    }

    @objc func performMenuHideWindow(_ sender: Any?) {
        hide()
    }

    @objc func performMenuQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc func reloadActiveWebView(_ sender: Any?) {
        focusedPageWebView()?.reload()
    }

    @objc func reloadActiveWebViewFromOrigin(_ sender: Any?) {
        focusedPageWebView()?.reloadFromOrigin()
    }

    @objc func reinstantiateActiveWebView(_ sender: Any?) {
        guard let webView = focusedPageWebView(),
              let url = webViewManager.serviceURL(for: webView) else { return }
        webViewManager.load(url, in: webView)
    }

    /// The find bar for `page`: a popup page's own bar, else the main
    /// window's bar. Menu-bar Find, Cmd+F, and Cmd+G all route through it.
    func findBar(for page: WKWebView?) -> FindBarViewController {
        if let page,
           let popupFindBar = webViewManager?.findBarController(forPopupWebView: page) {
            return popupFindBar
        }
        return findBarViewController
    }

    @objc func presentFindPanelFromMenu(_ sender: Any?) {
        // Menu-bar Find follows the focused window; the title menu passes
        // its own page explicitly through the item.
        findBar(for: targetPage(from: sender)).show()
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

        // Runs async so `selectService` stays synchronous: the switch itself
        // proceeds while the old engine's teardown waits for confirmation.
        // Staying skips the teardown, leaving the engine mounted until the
        // next switch-away re-arms the policy.
        Task {
            let tabs = (0..<10)
                .filter { self.webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
                .map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
            guard await self.requestCloseTabs(tabs, reason: .switchService(serviceName: service.name)) else {
                self.refreshServiceSegments()
                return
            }
            self.prepareForLockingEncryptedService(service)
            self.webViewManager.tearDownAllWebViews(for: service)
            Task {
                try? await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
                await MainActor.run {
                    // The switch already moved on, but the user may have
                    // switched back while the dialog was up: recreate the
                    // view instead of stranding torn-down tabs on screen.
                    if self.currentService()?.id == service.id {
                        self.updateActiveWebview(focusWebView: false)
                    }
                    self.refreshServiceSegments()
                }
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
                // Resolve against the event itself: the clicked window and its
                // coordinate space are authoritative at delivery time.
                let clickScreenPoint: NSPoint
                if let eventWindow = event.window {
                    clickScreenPoint = eventWindow.convertToScreen(
                        NSRect(origin: event.locationInWindow, size: .zero)
                    ).origin
                } else {
                    clickScreenPoint = NSEvent.mouseLocation
                }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.dismissHUDsOnOutsideClick(at: clickScreenPoint)
                    if event.window === self.window {
                        self.raiseVisibleHUDs()
                    }
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
                    Task {
                        let tabs = (0..<10)
                            .filter { self.webViewManager.getWebView(for: service, sessionIndex: $0) != nil }
                            .map { TabIdentifier(serviceID: service.id, sessionIndex: $0) }
                        guard await self.requestCloseTabs(tabs, reason: .autoLock) else {
                            // Staying snoozes the timer so the dialog does not
                            // re-fire on every tick while the user decides.
                            self.lastActivityTime = Date()
                            return
                        }
                        self.prepareForLockingEncryptedService(service)
                        self.webViewManager.tearDownAllWebViews(for: service)
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
}

// MARK: - CollapsibleSelectorDelegate
@MainActor
extension MainWindowController: CollapsibleSelectorDelegate {
    func isLoading(index: Int) -> Bool {
        guard let service = currentService() else { return false }
        let sessionIndex = service.visibleSessionIndices.indices.contains(index)
            ? service.visibleSessionIndices[index]
            : index
        guard let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) else { return false }
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
            let sessionIndex = service.visibleSessionIndices.indices.contains(index)
                ? service.visibleSessionIndices[index]
                : index
            return webViewManager.getWebView(for: service, sessionIndex: sessionIndex) != nil
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
            let sessionIndex = service.visibleSessionIndices.indices.contains(index)
                ? service.visibleSessionIndices[index]
                : index
            return webViewManager.getWebView(for: service, sessionIndex: sessionIndex) != nil
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
extension MainWindowController: FindBarDelegate {}

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

    func webViewDidUpdateFullscreenState(_ state: WKWebView.FullscreenState, for webView: WKWebView) {
        handleElementFullscreenStateChange(state, for: webView)
    }
    
    func webViewDidFinishNavigation(_ webView: WKWebView) {
        saveTabsState()
        selectorSuggestDidReload(webView: webView)
        // A tab finishing load is the only moment its rendered content is
        // guaranteed fresh: snapshot it for the sessions ring. Departure
        // snapshots cover visited tabs and arrival snapshots cover the
        // current one; this covers everything else loading in the open ring.
        if modifierHUDKind == .sessions,
           let (service, sessionIndex) = webViewManager.findServiceAndSession(for: webView),
           service.id == currentService()?.id,
           sessionIndicesForHUD(service: service).contains(sessionIndex) {
            let tab = TabIdentifier(serviceID: service.id, sessionIndex: sessionIndex)
            webView.takeSnapshot(with: nil) { [weak self] image, error in
                guard let img = image, error == nil else { return }
                DispatchQueue.main.async {
                    self?.tabPreviews[tab] = img
                    self?.refreshModifierHUDContents()
                }
            }
        }
        guard webView == currentWebView() else { return }

        // pushInputTrackerState refuses marker-free pages itself.
        webViewManager.pushInputTrackerState(true, to: webView)
        webViewManager.pushRecordingIndicatorState(to: webView)
        
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

        // Metadata loading updates Settings.shared.services. Refresh both of
        // the controller's service snapshots before restoring any sessions so
        // newly-created webviews receive the decrypted engine configuration.
        services = Settings.shared.services
        webViewManager.updateServices(services)
        syncCurrentServiceSelection()
        
        if Settings.shared.tabSurvivalPolicy != .never,
           let service = services.first(where: { $0.id == serviceID }) {
            let stateURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID).appendingPathComponent("quiper_tabs.json")
            if let data = try? Data(contentsOf: stateURL),
               let state = try? JSONDecoder().decode(SecureTabState.self, from: data) {
                
                activeIndicesByID[service.id] = state.activeIndex

                // Pinned-tab sessions instantiate lazily from the engine
                // definition; saved addresses are never replayed.
                if !service.isPinnedTabs {
                    for (sessionIndex, urlString) in state.openTabs {
                        _ = webViewManager.getOrCreateWebView(for: service, sessionIndex: sessionIndex, dragArea: dragArea, targetURL: urlString, restoredTitle: state.tabTitles?[sessionIndex], loadImmediately: (sessionIndex == state.activeIndex))

                        if let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) {
                            setupSessionTitleObserver(for: service, sessionIndex: sessionIndex, webView: webView)
                        }
                    }
                }

                if let securePopups = state.popups {
                    webViewManager.restorePopups(securePopups)
                }
                
                if currentServiceID == service.id {
                    updateActiveWebview()
                }
            }
        }
        
        refreshServiceSegments()
        updateSessionSelector()
        layoutSelectors()
    }
}
