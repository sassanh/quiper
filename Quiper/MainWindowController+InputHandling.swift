import AppKit
import Carbon
import WebKit

extension MainWindowController {
    
    // MARK: - Input Handling
    
    func setShortcutsEnabled(_ enabled: Bool) {
        if enabled {
            if keyDownEventMonitor == nil {
                keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self = self else { return event }
                    return self.handleLocalEvent(event)
                }
            }
        } else {
            if let monitor = keyDownEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownEventMonitor = nil
            }
        }
    }

    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            if GhostOnboardingManager.shared.isActive {
                GhostOnboardingManager.shared.handleTipKey(keyCode: event.keyCode)
                // Swallow ALL keys during onboarding — no shortcuts, no typing
                return nil
            }
            
            // Invalidate Command modifier tap-timings upon keyboard activity
            self.lastCommandPressedTime = 0
            self.lastCommandReleasedTime = 0
            self.wasBothCmdsDown = false
            
            if event.keyCode == kVK_Escape {
                if self.isCyclingHistory {
                    self.cancelHistoryCycling()
                    return nil
                }
                if self.modifierHUDKind != nil {
                    self.hideModifierHUDRing()
                    return nil
                }
                if self.isSelectorSuggestActive {
                    self.cancelSelectorSuggest()
                    return nil
                }
                if let hud = self.locationBarHUDView, !hud.isHidden {
                    self.hideLocationBarHUD()
                    return nil
                }
                if let hud = self.promptHistoryHUDView, !hud.isHidden {
                    self.hidePromptHistoryHUD()
                    return nil
                }
                if let hud = self.modifierHUDView, !hud.isHidden {
                    self.hideModifierHUD()
                    return nil // Swallow escape so it doesn't hide the main window
                }
                if let webView = self.currentWebView(), webView.isLoading {
                    self.webViewManager.stopLoading(webView)
                    return nil // Swallow escape so it stops loading
                }
            }
            if let hud = self.promptHistoryHUDView, !hud.isHidden {
                if hud.handleHUDShortcut(event) {
                    return nil
                }
                let isEditingShortcut = event.modifierFlags.contains(.command) && [0, 6, 7, 8, 9, 12, 15, 40, 51, 117].contains(event.keyCode)
                let hasModifier = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control)
                if hasModifier && !isEditingShortcut {
                    self.hidePromptHistoryHUD()
                }
            }
            if let hud = self.modifierHUDView, !hud.isHidden {
                let hasModifier = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control)
                if hasModifier {
                    self.hideModifierHUD()
                }
            }
            if skipModalCheck || !hasModalWindow {
                if self.handleCommandShortcut(event: event) == true {
                    return nil
                }
            }
        } else if event.type == .flagsChanged {
            self.handleFlagsChanged(event: event)
        }
        return event
    }
    
    func showHeaderTemporarily() {
        guard Settings.shared.topBarVisibility == .hidden else { return }
        isHeaderForcedVisibleForAction = true
        updateHeaderVisibility()
        headerActionTimer?.invalidate()
        headerActionTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isHeaderForcedVisibleForAction = false
                self?.updateHeaderVisibility()
            }
        }
    }

    var hasModalWindow: Bool {
        let mainWindow = window
        if mainWindow?.attachedSheet != nil { return true }
        if NSApp.modalWindow != nil { return true }

        return NSApp.windows.contains { window in
            guard window !== mainWindow, window.isVisible, window.isKeyWindow else { return false }
            if window is ActivePanel || window is InteractiveHUDPanel { return false }
            if Self.isTransientSystemInputWindow(window) { return false }
            // Session popups are Quiper's own UI, not foreign modals:
            // shortcuts (session/service switching, hide, actions) must keep
            // working while a popup holds key status.
            if let manager = webViewManager, manager.isPopupWindow(window) { return false }
            return true
        }
    }

    /// macOS betas spawn transient system input windows inside the app's own
    /// window list (the Siri-related `NSCampoLightweightUIHostWindow`, accent
    /// popups). They can hold key status spontaneously but are not modals and
    /// must never disable Quiper's shortcuts.
    private static func isTransientSystemInputWindow(_ window: NSWindow) -> Bool {
        // Check multiple representations for robustness across Swift
        // mangling / beta vs CI toolchains. Real host is
        // `NSCampoLightweightUIHostWindow`; test mock is
        // `MockCampoLightweightUIHostWindow` (Swift-mangled).
        let candidates: [String] = [
            String(describing: type(of: window)),
            NSStringFromClass(type(of: window)),
            window.className,
            String(describing: window.classForCoder),
            window.identifier?.rawValue ?? ""
        ]
        for name in candidates {
            let lower = name.lowercased()
            if lower.contains("campo") || lower.contains("lightweight") {
                return true
            }
        }
        return false
    }

    func handleFlagsChanged(event: NSEvent) {
        // Ending the recent-tabs ring on ⌘ release outranks modal gating:
        // transient system input UI (e.g. the accent-popup host window on
        // recent macOS) can hold key status and would otherwise strand the
        // ring HUD on screen with no event ever dismissing it.
        if isCyclingHistory {
            let requiredFlags = NSEvent.ModifierFlags.command.rawValue
            let currentFlags = event.modifierFlags.rawValue
            if (currentFlags & requiredFlags) != requiredFlags {
                endHistoryCycling()
            }
        }

        if !(skipModalCheck || !hasModalWindow) {
            hideModifierHUDRing()
            return
        }

        if GhostOnboardingManager.shared.isActive {
            hideModifierHUDRing()
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let now = event.timestamp
        
        let isLeftCmdDown = (event.modifierFlags.rawValue & UInt(NX_DEVICELCMDKEYMASK)) != 0
        let isRightCmdDown = (event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK)) != 0
        let bothCmdsDown = isLeftCmdDown && isRightCmdDown
        
        if bothCmdsDown && !wasBothCmdsDown && Settings.shared.enableHUDCmdEscape {
            toggleModifierHUD()
        }
        wasBothCmdsDown = bothCmdsDown
        
        // Double-tap on Command detection
        let isCmdKey = event.keyCode == 55 || event.keyCode == 54 // Left command = 55, Right command = 54
        if isCmdKey {
            let containsCmd = modifiers.contains(.command)
            if containsCmd {
                // Command pressed down
                if modifiers == .command { // Only command is down, no other modifier
                    let diff = now - lastCommandReleasedTime
                    if diff < 0.3 && Settings.shared.enableHUDDoubleTapCmd {
                        toggleModifierHUD()
                    }
                    lastCommandPressedTime = now
                } else {
                    lastCommandPressedTime = 0
                    lastCommandReleasedTime = 0
                }
            } else {
                // Command released
                if modifiers.isEmpty { // No modifiers left down
                    let pressDiff = now - lastCommandPressedTime
                    if pressDiff < 0.3 {
                        lastCommandReleasedTime = now
                    } else {
                        lastCommandReleasedTime = 0
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              let hud = self.modifierHUDView,
                              !hud.isHidden,
                              !hud.isHiding else { return }
                        self.modifierHUDWindow?.makeKey()
                        hud.focusSearchField()
                    }
                } else {
                    lastCommandPressedTime = 0
                    lastCommandReleasedTime = 0
                }
            }
        } else {
            // Some other modifier key was changed, invalidate command tap
            lastCommandPressedTime = 0
            lastCommandReleasedTime = 0
        }

        let appShortcuts = Settings.shared.appShortcutBindings

        let sessionHeld = isSessionDigitModifiers(modifiers, appShortcuts: appShortcuts)
        let engineHeld = isEngineDigitModifiers(modifiers, appShortcuts: appShortcuts)
        let sessionBehavior = Settings.shared.sessionModifierHoldBehavior
        let engineBehavior = Settings.shared.engineModifierHoldBehavior

        // A released ring confirms its highlight and dismisses without
        // opening the other ring: releasing one key of a chord (e.g. Ctrl of
        // Cmd+Ctrl) transiently matches the other modifier set, and answering
        // a confirmation with a fresh popup is the surprise. The show
        // branches below skip the confirming event.
        let didConfirmRingSelection: Bool = {
            guard let kind = modifierHUDKind, !isCyclingHistory else { return false }
            let kindReleased: Bool = {
                switch kind {
                case .sessions: return !sessionHeld
                case .engines: return !engineHeld
                }
            }()
            guard kindReleased else { return false }
            guard commitModifierHUDHighlight() else { return false }
            hideModifierHUDRing()
            return true
        }()

        // History ring wins over modifier rings sharing the same modifiers.
        if isCyclingHistory {
            hideModifierHUDRing()
        } else if sessionHeld && sessionBehavior == .hud && modifierHUDKind != .sessions && !didConfirmRingSelection {
            showModifierHUDRing(kind: .sessions)
        } else if engineHeld && engineBehavior == .hud && modifierHUDKind != .engines && !didConfirmRingSelection {
            // Sessions wins when both modifiers match at once.
            if !(sessionHeld && sessionBehavior == .hud) {
                showModifierHUDRing(kind: .engines)
            }
        } else if modifierHUDKind != nil && !sessionHeld && !engineHeld {
            hideModifierHUDRing(committingHighlight: true)
        } else if modifierHUDKind == .sessions && (!sessionHeld || sessionBehavior != .hud) {
            hideModifierHUDRing(committingHighlight: true)
        } else if modifierHUDKind == .engines && (!engineHeld || engineBehavior != .hud) {
            hideModifierHUDRing(committingHighlight: true)
        }

        let shouldExpandSession = sessionHeld && sessionBehavior == .expand
        let shouldExpandService = engineHeld && engineBehavior == .expand
        
        if let sessionSel = collapsibleSessionSelector, !sessionSel.isHidden && Settings.shared.showHiddenBarOnModifiers {
            if shouldExpandSession {
                if !sessionSel.isExpanded {
                    sessionSel.expand() 
                }
            } else {
                if sessionSel.isExpanded && (skipSafeAreaCheck || !isMouseInSafeArea(for: sessionSel)) {
                     sessionSel.collapse()
                }
            }
        }
        
        if let serviceSel = collapsibleServiceSelector, !serviceSel.isHidden && Settings.shared.showHiddenBarOnModifiers {
            if shouldExpandService {
                if !serviceSel.isExpanded {
                    serviceSel.expand()
                }
            } else {
                if serviceSel.isExpanded && (skipSafeAreaCheck || !isMouseInSafeArea(for: serviceSel)) {
                    serviceSel.collapse()
                }
            }
        }
        
        let sessionRevealsHeader = sessionHeld && sessionBehavior != .off
        let engineRevealsHeader = engineHeld && engineBehavior != .off
        let shouldShowHeader = (sessionRevealsHeader || engineRevealsHeader) && Settings.shared.showHiddenBarOnModifiers
        if isModifiersForHeaderDown != shouldShowHeader {
            isModifiersForHeaderDown = shouldShowHeader
            updateHeaderVisibility()
        }
    }

    // MARK: - Modifier-hold HUD rings

    private func isSessionDigitModifiers(_ modifiers: NSEvent.ModifierFlags, appShortcuts: AppShortcutBindings) -> Bool {
        if appShortcuts.sessionDigitsModifiers > 0,
           modifiers == NSEvent.ModifierFlags(rawValue: appShortcuts.sessionDigitsModifiers) {
            return true
        }
        if let alt = appShortcuts.sessionDigitsAlternateModifiers, alt > 0,
           modifiers == NSEvent.ModifierFlags(rawValue: alt) {
            return true
        }
        return false
    }

    private func isEngineDigitModifiers(_ modifiers: NSEvent.ModifierFlags, appShortcuts: AppShortcutBindings) -> Bool {
        if appShortcuts.serviceDigitsPrimaryModifiers > 0,
           modifiers == NSEvent.ModifierFlags(rawValue: appShortcuts.serviceDigitsPrimaryModifiers) {
            return true
        }
        if let sec = appShortcuts.serviceDigitsSecondaryModifiers, sec > 0,
           modifiers == NSEvent.ModifierFlags(rawValue: sec) {
            return true
        }
        return false
    }

    private func modifierHUDItems(kind: ModifierHUDKind) -> [TabIdentifier] {
        switch kind {
        case .sessions:
            guard let service = currentService(), webViewManager != nil else { return [] }
            return sessionIndicesForHUD(service: service).map {
                TabIdentifier(serviceID: service.id, sessionIndex: $0)
            }
        case .engines:
            return services.map { service in
                let active = activeIndicesByID[service.id]
                    ?? service.visibleSessionIndices.first
                    ?? 0
                return TabIdentifier(serviceID: service.id, sessionIndex: active)
            }
        }
    }

    /// Sessions with live content, tabs restored from a previous launch that
    /// have no webview yet, and pinned slots, which are definitionally open
    /// whether or not they were visited. The single gate for the sessions
    /// ring so a held modifier never hides a reachable tab.
    func sessionIndicesForHUD(service: Service) -> [Int] {
        var indices = Set<Int>()
        if webViewManager != nil {
            for index in service.visibleSessionIndices
                where webViewManager.getWebView(for: service, sessionIndex: index) != nil {
                indices.insert(index)
            }
        }
        if service.isPinnedTabs {
            indices.formUnion(service.visibleSessionIndices)
        } else if let saved = Settings.shared.persistedTabState?.openTabs[service.id] {
            for index in saved.keys where service.visibleSessionIndices.contains(index) {
                indices.insert(index)
            }
        }
        return indices.sorted()
    }

    /// Applies the current items, highlight, and card content for `kind`.
    /// Returns the items so callers can hide the ring when it empties.
    /// A highlight set by hover/arrows survives the rebuild while its card
    /// still exists, so live refreshes never snap it back to the selection.
    /// Callbacks are wired before the override rebuilds the cards, so the
    /// first build already sees them.
    @discardableResult
    private func applyModifierHUDOverride(kind: ModifierHUDKind) -> [TabIdentifier] {
        let items = modifierHUDItems(kind: kind)
        let previousHighlight = tabHistoryHUDView?.currentOverrideHighlight
        let highlight: TabIdentifier? = {
            if let previousHighlight, items.contains(previousHighlight) {
                return previousHighlight
            }
            return currentTabIdentifier()
        }()
        tabHistoryHUDView?.onHoverTab = { [weak self] tab in
            guard let self, self.modifierHUDKind != nil else { return }
            self.tabHistoryHUDView?.updateOverrideHighlight(tab ?? self.currentTabIdentifier())
        }
        tabHistoryHUDView?.onSelectTab = { [weak self] tab in
            self?.selectModifierHUDTab(tab)
        }
        switch kind {
        case .sessions:
            tabHistoryHUDView?.showOverride(
                items: items,
                highlight: highlight,
                digit: { $0.sessionIndex == 9 ? 10 : $0.sessionIndex + 1 },
                title: { [weak self] tab in
                    guard let self,
                          let service = self.services.first(where: { $0.id == tab.serviceID }) else {
                        return "Empty Session"
                    }
                    if let title = self.webViewManager.getWebView(for: service, sessionIndex: tab.sessionIndex)?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty {
                        return title
                    }
                    if let saved = Settings.shared.persistedTabState?.tabTitles[tab.serviceID]?[tab.sessionIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !saved.isEmpty {
                        return saved
                    }
                    if let pinned = service.pinnedURL(for: tab.sessionIndex),
                       let host = URL(string: pinned)?.host,
                       !host.isEmpty {
                        return host
                    }
                    return "Empty Session"
                }
            )
        case .engines:
            let order = Dictionary(uniqueKeysWithValues: services.enumerated().map { ($1.id, $0) })
            tabHistoryHUDView?.showOverride(
                items: items,
                highlight: highlight,
                digit: { order[$0.serviceID].map { $0 == 9 ? 10 : $0 + 1 } ?? ($0.sessionIndex == 9 ? 10 : $0.sessionIndex + 1) },
                title: { [weak self] tab in
                    guard let self,
                          let service = self.services.first(where: { $0.id == tab.serviceID }) else {
                        return "Empty Session"
                    }
                    let page = self.webViewManager.getWebView(for: service, sessionIndex: tab.sessionIndex)?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let page, !page.isEmpty else { return service.name }
                    return "\(service.name) — \(page)"
                },
                icon: { [weak self] tab in
                    guard let self,
                          let service = self.services.first(where: { $0.id == tab.serviceID }) else {
                        return nil
                    }
                    if let cached = self.engineIconCache[service.id] {
                        return cached
                    }
                    guard let base64 = service.iconBase64,
                          let data = Data(base64Encoded: base64),
                          let image = NSImage(data: data) else {
                        return nil
                    }
                    self.engineIconCache[service.id] = image
                    return image
                }
            )
        }
        return items
    }

    /// Click selection for a modifier-ring card. Selects immediately like a
    /// digit press; the ring itself dismisses on modifier release as usual.
    private func selectModifierHUDTab(_ tab: TabIdentifier) {
        guard let kind = modifierHUDKind else { return }
        switch kind {
        case .sessions:
            guard tab.serviceID == currentService()?.id else { return }
            switchSession(to: tab.sessionIndex)
        case .engines:
            guard let index = services.firstIndex(where: { $0.id == tab.serviceID }) else { return }
            selectService(at: index)
        }
        // The click may have moved key status to the ring panel; hand it
        // back so typing keeps going to the newly selected tab.
        window?.makeKeyAndOrderFront(nil)
        if let webView = currentWebView() {
            window?.makeFirstResponder(webView)
        }
        refreshModifierHUDContents()
    }

    /// Single gate for the preamble shared by both ring showers: the prompt,
    /// modifier-search, and location-bar HUDs compete with the ring window.
    private func hideHUDsCompetingWithRing() {
        hidePromptHistoryHUD()
        hideModifierHUD()
        hideLocationBarHUD()
    }

    func showModifierHUDRing(kind: ModifierHUDKind) {
        guard !isCyclingHistory, window != nil else { return }
        collapsibleSessionSelector?.collapse()
        collapsibleServiceSelector?.collapse()
        modifierHUDKind = kind
        hideHUDsCompetingWithRing()
        // Ensure the window/view exist before applying the override:
        // showOverride on a nil view would silently drop the items.
        ensureTabHistoryHUDWindow()
        let items = applyModifierHUDOverride(kind: kind)
        guard !items.isEmpty else {
            hideModifierHUDRing()
            return
        }
        // applyModifierHUDOverride already rebuilt the cards once.
        updateModifierHUDWindowFrame()
        tabHistoryHUDWindow?.orderFront(nil)
        raiseHUDWindow(tabHistoryHUDWindow)
        tabHistoryHUDView?.isHidden = false
        captureCurrentTabPreview()
    }

    func hideModifierHUDRing(committingHighlight: Bool = false) {
        guard modifierHUDKind != nil else { return }
        if committingHighlight {
            commitModifierHUDHighlight()
        }
        modifierHUDKind = nil
        tabHistoryHUDView?.clearOverride()
        if isCyclingHistory {
            tabHistoryHUDView?.updateSelection()
            updateHUDWindowFrame()
        } else {
            hideTabHistoryHUD()
        }
    }

    /// Selects the hovered/arrow-highlighted card when the modifier is
    /// released. Returns whether a selection happened; no-op when the
    /// highlight already matches the current tab.
    @discardableResult
    private func commitModifierHUDHighlight() -> Bool {
        guard modifierHUDKind != nil,
              let highlight = tabHistoryHUDView?.currentOverrideHighlight,
              highlight != currentTabIdentifier() else { return false }
        selectModifierHUDTab(highlight)
        return true
    }

    /// Arrow-key navigation for an open ring. Left/Right step through ring
    /// order without wrapping; Up/Down move a visual row, staying put when
    /// no card exists above or below.
    private func stepModifierHUDHighlight(by delta: Int) {
        guard modifierHUDKind != nil,
              let items = tabHistoryHUDView?.currentOverrideItems,
              !items.isEmpty else { return }
        let anchor = tabHistoryHUDView?.currentOverrideHighlight ?? currentTabIdentifier()
        let startIndex = anchor.flatMap { items.firstIndex(of: $0) } ?? 0
        let nextIndex = startIndex + delta
        guard items.indices.contains(nextIndex) else { return }
        tabHistoryHUDView?.updateOverrideHighlight(items[nextIndex])
    }

    private func moveModifierHUDHighlightVertically(by rows: Int) {
        guard modifierHUDKind != nil,
              let view = tabHistoryHUDView,
              let items = view.currentOverrideItems,
              !items.isEmpty,
              view.currentMaxItemsPerRow > 0 else { return }
        let anchor = view.currentOverrideHighlight ?? currentTabIdentifier()
        let startIndex = anchor.flatMap { items.firstIndex(of: $0) } ?? 0
        let targetIndex = startIndex + rows * view.currentMaxItemsPerRow
        guard items.indices.contains(targetIndex) else { return }
        view.updateOverrideHighlight(items[targetIndex])
    }

    func refreshModifierHUDHighlight() {
        guard modifierHUDKind != nil else { return }
        tabHistoryHUDView?.updateOverrideHighlight(currentTabIdentifier())
        updateModifierHUDWindowFrame()
        captureCurrentTabPreview()
    }

    /// Snapshots the visible tab so the sessions ring shows a fresh preview
    /// for it. Departure snapshots (in `updateActiveWebview`) cover visited
    /// tabs; this covers the current one, which is never departed while the
    /// ring is open. No-op unless the sessions ring is visible.
    private func captureCurrentTabPreview() {
        guard modifierHUDKind == .sessions,
              let current = currentTabIdentifier(),
              let service = services.first(where: { $0.id == current.serviceID }),
              webViewManager != nil,
              let webView = webViewManager.getWebView(for: service, sessionIndex: current.sessionIndex) else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            guard let img = image, error == nil else { return }
            DispatchQueue.main.async {
                self?.tabPreviews[current] = img
                self?.refreshModifierHUDContents()
            }
        }
    }

    /// Rebuilds an open ring when its contents change (tab added/closed,
    /// services changed, titles or icons arrived). Hides the ring when it
    /// empties. No-op unless a ring is visible.
    func refreshModifierHUDContents() {
        guard let kind = modifierHUDKind, !isCyclingHistory else { return }
        let items = applyModifierHUDOverride(kind: kind)
        guard !items.isEmpty else {
            hideModifierHUDRing()
            return
        }
        updateModifierHUDWindowFrame()
    }
    
    private func showModifierHUD() {
        guard let parentWindow = window else { return }
        hidePromptHistoryHUD()
        hideLocationBarHUD()
        cancelHistoryCycling()
        
        if modifierHUDWindow == nil {
            let panel = InteractiveHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 492, height: 465),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            configureHUDPanel(panel, parentWindow: parentWindow)
            
            let hud = ModifierHUDView(frame: panel.contentView?.bounds ?? .zero, windowController: self)
            hud.autoresizingMask = [.width, .height]
            panel.contentView = hud
            
            modifierHUDView = hud
            modifierHUDWindow = panel
            
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        
        alignHUDWindow(modifierHUDWindow, width: 492, height: 465)
        modifierHUDWindow?.makeKeyAndOrderFront(nil)
        raiseHUDWindow(modifierHUDWindow)
        modifierHUDView?.show()
    }
    
    func hideModifierHUD() {
        if let hud = modifierHUDView, !hud.isHidden, !hud.isHiding {
            hud.hide()
            return
        }
        modifierHUDWindow?.orderOut(nil)
    }
    
    func toggleModifierHUD() {
        if let hud = modifierHUDView, hud.isHiding {
            return
        } else if let hud = modifierHUDView, !hud.isHidden {
            hideModifierHUD()
        } else {
            showModifierHUD()
        }
    }
    
    private func isMouseInSafeArea(for selector: CollapsibleSelector) -> Bool {
        guard let panel = selector.expandedPanel else { return false }
        let mouseInScreen = NSEvent.mouseLocation
        let padding = selector.safeAreaPadding
        let safeFrame = panel.frame.insetBy(dx: -padding, dy: -padding)
        return safeFrame.contains(mouseInScreen)
    }

    func handleCommandShortcut(event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt16(event.keyCode)
        NSLog("[TabHistory] keydown keyCode: %d, modifiers: %lu, Grave is: %d", keyCode, modifiers.rawValue, kVK_ANSI_Grave)
        let appShortcuts = Settings.shared.appShortcutBindings
        let config = HotkeyManager.Configuration(keyCode: UInt32(keyCode), modifierFlags: modifiers.rawValue)

        let isControl = modifiers.contains(.control)
        let isOption = modifiers.contains(.option)
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        // Arrow-key navigation and Enter commit for an open modifier ring.
        // Only when the held modifiers are exactly the ring's own digit
        // modifiers, so bindings like Cmd+Shift+Arrow keep working.
        if let ringKind = modifierHUDKind {
            let matchesRingModifiers: Bool = {
                switch ringKind {
                case .sessions:
                    return isSessionDigitModifiers(modifiers, appShortcuts: appShortcuts)
                case .engines:
                    return isEngineDigitModifiers(modifiers, appShortcuts: appShortcuts)
                }
            }()
            if matchesRingModifiers {
                if keyCode == UInt16(kVK_Return) {
                    commitModifierHUDHighlight()
                    return true
                }
                switch Int(keyCode) {
                case kVK_LeftArrow:
                    stepModifierHUDHighlight(by: -1)
                    return true
                case kVK_RightArrow:
                    stepModifierHUDHighlight(by: 1)
                    return true
                case kVK_UpArrow:
                    moveModifierHUDHighlightVertically(by: -1)
                    return true
                case kVK_DownArrow:
                    moveModifierHUDHighlightVertically(by: 1)
                    return true
                default:
                    break
                }
            }
        }

        if isControl && isShift && keyCode == UInt16(kVK_ANSI_Q) {
            NSApp.terminate(nil)
            return true
        }

        if isEmptyStateActive {
            if let service = services.first(where: { $0.activationShortcut == config }) {
                handleActivationShortcut(for: service)
                return true
            }
            if let digit = digitValue(for: keyCode) {
                if (appShortcuts.sessionDigitsModifiers > 0 && modifiers.rawValue == appShortcuts.sessionDigitsModifiers) ||
                    (appShortcuts.sessionDigitsAlternateModifiers.map { $0 > 0 && modifiers.rawValue == $0 } ?? false) {
                    let index = digit == 0 ? 9 : digit - 1
                    switchSession(to: index)
                    return true
                }

                let targetIndex: Int? = {
                    if digit == 0 {
                        return services.count >= 10 ? 9 : nil
                    }
                    return (1...services.count).contains(digit) ? digit - 1 : nil
                }()
                if appShortcuts.serviceDigitsPrimaryModifiers > 0 && modifiers.rawValue == appShortcuts.serviceDigitsPrimaryModifiers {
                    if let idx = targetIndex {
                        selectService(at: idx)
                        return true
                    }
                }
                if let secondary = appShortcuts.serviceDigitsSecondaryModifiers,
                   secondary > 0,
                   modifiers.rawValue == secondary {
                    if let idx = targetIndex {
                        selectService(at: idx)
                        return true
                    }
                }
            }
            
            if matches(config, appShortcuts.configuration(for: .nextService)) || matches(config, appShortcuts.alternateConfiguration(for: .nextService)) {
                stepService(by: 1)
                return true
            }
            
            let lockConfig = appShortcuts.configuration(for: .lockCurrentEngine)
            let altLockConfig = appShortcuts.alternateConfiguration(for: .lockCurrentEngine)
            
            let lockAllConfig = HotkeyManager.Configuration(keyCode: lockConfig.keyCode, modifierFlags: lockConfig.modifierFlags | NSEvent.ModifierFlags.shift.rawValue)
            let altLockAllConfig = altLockConfig.map { HotkeyManager.Configuration(keyCode: $0.keyCode, modifierFlags: $0.modifierFlags | NSEvent.ModifierFlags.shift.rawValue) }
            
            if matches(config, lockAllConfig) || matches(config, altLockAllConfig) {
                handleLockAllEnginesShortcut()
                return true
            }
            
            if matches(config, lockConfig) || matches(config, altLockConfig) {
                handleLockCurrentEngineShortcut()
                return true
            }
            if matches(config, appShortcuts.configuration(for: .previousService)) || matches(config, appShortcuts.alternateConfiguration(for: .previousService)) {
                stepService(by: -1)
                return true
            }
            
            if isCommand {
                switch keyCode {
                case UInt16(kVK_ANSI_M):
                    toggleWindowSize()
                    return true
                case UInt16(kVK_ANSI_H), UInt16(kVK_ANSI_Q):
                    hide()
                    return true
                case UInt16(kVK_ANSI_Y):
                    togglePromptHistoryHUD()
                    return true
                case UInt16(kVK_ANSI_Comma):
                    guard isShift else {
                        break
                    }
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                    return true
                default:
                    break
                }
            }
            
            if isCommand || isControl || isOption {
                return true
            }
            return false
        }

        if matches(config, appShortcuts.configuration(for: .nextSession)) || matches(config, appShortcuts.alternateConfiguration(for: .nextSession)) {
            stepSession(by: 1)
            return true
        }
        
        let lockConfig = appShortcuts.configuration(for: .lockCurrentEngine)
        let altLockConfig = appShortcuts.alternateConfiguration(for: .lockCurrentEngine)
        
        let lockAllConfig = HotkeyManager.Configuration(keyCode: lockConfig.keyCode, modifierFlags: lockConfig.modifierFlags | NSEvent.ModifierFlags.shift.rawValue)
        let altLockAllConfig = altLockConfig.map { HotkeyManager.Configuration(keyCode: $0.keyCode, modifierFlags: $0.modifierFlags | NSEvent.ModifierFlags.shift.rawValue) }
        
        if matches(config, lockAllConfig) || matches(config, altLockAllConfig) {
            handleLockAllEnginesShortcut()
            return true
        }
        
        if matches(config, lockConfig) || matches(config, altLockConfig) {
            handleLockCurrentEngineShortcut()
            return true
        }
        if matches(config, appShortcuts.configuration(for: .previousSession)) || matches(config, appShortcuts.alternateConfiguration(for: .previousSession)) {
            stepSession(by: -1)
            return true
        }

        if matches(config, appShortcuts.configuration(for: .nextService)) || matches(config, appShortcuts.alternateConfiguration(for: .nextService)) {
            stepService(by: 1)
            return true
        }
        if matches(config, appShortcuts.configuration(for: .previousService)) || matches(config, appShortcuts.alternateConfiguration(for: .previousService)) {
            stepService(by: -1)
            return true
        }
        
        // Hard temporary tab: Quiper-level shortcut, not an action. Opens an
        // isolated ephemeral tab in the current engine. Checked before custom
        // actions so it wins over any persisted soft-action shortcut.
        if matches(config, ephemeralTemporaryShortcut) {
            createQuiperPrivateTemporarySession()
            return true
        }

        if let action = Settings.shared.customActions.first(where: { $0.shortcut == config }) {
            performCustomAction(action)
            return true
        }
        
        if let service = services.first(where: { $0.activationShortcut == config }) {
            handleActivationShortcut(for: service)
            return true
        }
        
        if let digit = digitValue(for: keyCode) {
            if (appShortcuts.sessionDigitsModifiers > 0 && modifiers.rawValue == appShortcuts.sessionDigitsModifiers) ||
                (appShortcuts.sessionDigitsAlternateModifiers.map { $0 > 0 && modifiers.rawValue == $0 } ?? false) {
                let index = digit == 0 ? 9 : digit - 1
                switchSession(to: index)
                return true
            }
            let targetIndex: Int? = {
                if digit == 0 {
                    return services.count >= 10 ? 9 : nil
                }
                return (1...services.count).contains(digit) ? digit - 1 : nil
            }()

            if appShortcuts.serviceDigitsPrimaryModifiers > 0 && modifiers.rawValue == appShortcuts.serviceDigitsPrimaryModifiers {
                if let idx = targetIndex {
                    selectService(at: idx)
                    return true
                }
            }
            if let secondary = appShortcuts.serviceDigitsSecondaryModifiers,
               secondary > 0,
               modifiers.rawValue == secondary {
                if let idx = targetIndex {
                    selectService(at: idx)
                    return true
                }
            }
        }

        if !isCommand {
            return false
        }

        if isControl || isOption {
            if keyCode == UInt16(kVK_ANSI_I) {
                toggleInspector()
                return true
            } else if keyCode == UInt16(kVK_ANSI_R) {
                // Allow Option+Command+R to fall through
            } else {
                return false
            }
        }

        switch keyCode {
        case UInt16(kVK_ANSI_M):
            toggleWindowSize()
            return true
        case UInt16(kVK_ANSI_H), UInt16(kVK_ANSI_Q):
            hide()
            return true
        case UInt16(kVK_ANSI_Y):
            togglePromptHistoryHUD()
            return true
        case UInt16(kVK_ANSI_L):
            guard isShift else {
                return false
            }
            toggleLocationBarHUD()
            return true
        case UInt16(kVK_ANSI_W):
            // A popup is a window, not a tab: Cmd+W dismisses just the
            // focused popup. A sheet attached to the popup is modal to it,
            // so Cmd+W must not escape to the tab close path there either.
            if let keyWindow = NSApp.keyWindow, let manager = webViewManager,
               keyWindow.attachedSheet == nil, manager.isPopupWindow(keyWindow) {
                keyWindow.close()
                return true
            }
            closeCurrentTab()
            return true
        case UInt16(kVK_ANSI_R):
            guard !isInspectorFocused() else {
                return false
            }
            if isShift {
                reinstantiateActiveWebView(nil)
            } else if isOption {
                reloadActiveWebViewFromOrigin(nil)
            } else {
                reloadActiveWebView(nil)
            }
            return true
        case UInt16(kVK_ANSI_F):
            if let popupFindBar = focusedPopupFindBar() {
                popupFindBar.show()
                return true
            }
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.show()
            return true
        case UInt16(kVK_ANSI_G):
            if let popupFindBar = focusedPopupFindBar() {
                popupFindBar.handleFindRepeat(shortcutShifted: isShift)
                return true
            }
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.handleFindRepeat(shortcutShifted: isShift)
            return true
        case UInt16(kVK_ANSI_Comma):
            guard isShift else {
                return false
            }
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return true
        case UInt16(kVK_ANSI_Equal):
            guard !isInspectorFocused() else {
                return false
            }
            zoom(by: Zoom.step)
            return true
        case UInt16(kVK_ANSI_Minus):
            guard !isInspectorFocused() else {
                return false
            }
            zoom(by: -Zoom.step)
            return true
        default:
            break
        }

        if keyCode == UInt16(kVK_ANSI_KeypadPlus) {
            zoom(by: Zoom.step)
            return true
        }
        if keyCode == UInt16(kVK_ANSI_KeypadMinus) {
            zoom(by: -Zoom.step)
            return true
        }
        if (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)) && isShift {
            performMenuResetZoom(nil)
            return true
        }

        return false
    }
    
    private func digitValue(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Keypad0): return 0
        case UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_Keypad1): return 1
        case UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_Keypad2): return 2
        case UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_Keypad3): return 3
        case UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_Keypad4): return 4
        case UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_Keypad5): return 5
        case UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_Keypad6): return 6
        case UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_Keypad7): return 7
        case UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_Keypad8): return 8
        case UInt16(kVK_ANSI_9), UInt16(kVK_ANSI_Keypad9): return 9
        default: return nil
        }
    }

    private func isInspectorFocused() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        
        var current: NSView? = responder as? NSView
        while let view = current {
            let className = String(describing: type(of: view))
            if className.contains("Inspector") {
                return true
            }
            current = view.superview
        }
        
        if let window = responder as? NSWindow {
             return String(describing: type(of: window)).contains("Inspector")
        }
        
        return false
    }

    /// The find bar for the focused session popup, if the key window is one
    /// of `WebViewManager`'s popup windows. Cmd+F / Cmd+G route here instead
    /// of the main window's find bar while a popup holds key status.
    private func focusedPopupFindBar() -> FindBarViewController? {
        guard let keyWindow = NSApp.keyWindow,
              let manager = webViewManager,
              manager.isPopupWindow(keyWindow),
              let popupWebView = manager.popupWebView(for: keyWindow),
              let popupFindBar = manager.findBarController(forPopupWebView: popupWebView) else {
            return nil
        }
        return popupFindBar
    }
    
    private func handleActivationShortcut(for service: Service) {
        let alreadyActiveEngine = currentService()?.id == service.id
        if Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut, alreadyActiveEngine {
            hide()
            return
        }
        _ = selectService(withID: service.id)
    }

    private func matches(_ lhs: HotkeyManager.Configuration, _ rhs: HotkeyManager.Configuration?) -> Bool {
        guard let rhs = rhs, !rhs.isDisabled else { return false }
        return lhs.keyCode == rhs.keyCode && lhs.modifierFlags == rhs.modifierFlags
    }

    /// Quiper-level hard-temporary shortcut: Cmd+P. Not a custom action;
    /// it opens an isolated ephemeral tab directly.
    private var ephemeralTemporaryShortcut: HotkeyManager.Configuration {
        HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_P),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
    }

    // MARK: - Tab History Cycling & HUD Methods
    
    func showTabHistoryHUD() {
        guard window != nil else { return }
        if isCyclingHistory {
            modifierHUDKind = nil
            tabHistoryHUDView?.clearOverride()
        }
        hideHUDsCompetingWithRing()
        ensureTabHistoryHUDWindow()

        tabHistoryHUDView?.updateSelection()
        updateHUDWindowFrame()

        tabHistoryHUDWindow?.orderFront(nil)
        raiseHUDWindow(tabHistoryHUDWindow)
        tabHistoryHUDView?.isHidden = false
    }

    /// Single gate for creating the shared history/modifier ring window.
    private func ensureTabHistoryHUDWindow() {
        guard let parentWindow = window else { return }
        if tabHistoryHUDWindow != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureHUDPanel(panel, parentWindow: parentWindow)

        let hud = TabHistoryHUDView(frame: panel.contentView?.bounds ?? .zero, windowController: self)
        hud.autoresizingMask = [.width, .height]
        panel.contentView = hud

        tabHistoryHUDView = hud
        tabHistoryHUDWindow = panel

        parentWindow.addChildWindow(panel, ordered: .above)
    }
    
    func hideTabHistoryHUD() {
        tabHistoryHUDView?.isHidden = true
        tabHistoryHUDWindow?.orderOut(nil)
    }
    func updateHUDWindowFrame() {
        guard tabHistoryHUDView != nil else { return }
        let (hudWidth, hudHeight) = tabHistoryHUDContentSize()
        alignHUDWindow(tabHistoryHUDWindow, width: hudWidth, height: hudHeight)
    }

    /// Single gate for the shared ring window's content size.
    private func tabHistoryHUDContentSize() -> (width: CGFloat, height: CGFloat) {
        guard let hudView = tabHistoryHUDView else { return (500, 200) }

        let itemsCount = hudView.currentItemsCount
        let maxItemsPerRow = hudView.currentMaxItemsPerRow
        let rowCount = max(1, (itemsCount + maxItemsPerRow - 1) / max(1, maxItemsPerRow))

        let hudWidth: CGFloat = 32 + CGFloat(maxItemsPerRow) * 148 + CGFloat(maxItemsPerRow - 1) * 12
        let hudHeight: CGFloat = 32 + CGFloat(rowCount) * 130 + CGFloat(max(0, rowCount - 1)) * 12
        return (hudWidth, hudHeight)
    }

    /// Sizes the shared ring window like the history ring but anchors it just
    /// inside the webview edge next to the toolbar (top/bottom per settings),
    /// so the modifier rings never read as the centered history ring and
    /// never cover the toolbar. Mirrors `alignLocationBarHUDWindow` insets.
    func updateModifierHUDWindowFrame() {
        guard tabHistoryHUDView != nil, let parentWindow = window else { return }
        let (hudWidth, hudHeight) = tabHistoryHUDContentSize()
        let headerInset = currentMargin + CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        let gap: CGFloat = 24
        let targetY: CGFloat = {
            if Settings.shared.dragAreaPosition == .bottom {
                return parentWindow.frame.minY + headerInset + gap
            } else {
                return parentWindow.frame.maxY - headerInset - gap - hudHeight
            }
        }()
        tabHistoryHUDWindow?.setFrame(
            alignedHUDFrame(width: hudWidth, height: hudHeight, y: targetY),
            display: true,
            animate: false
        )
    }
    
    func performPendingHistorySwitch() {
        guard isCyclingHistory, let targetTab = highlightedTab else { return }
        
        guard let service = currentService() else { return }
        let activeIndex = activeIndicesByID[service.id] ?? 0
        let currentTab = TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
        if currentTab == targetTab { return }
        
        isExecutingHistoryNavigation = true
        if service.id != targetTab.serviceID {
            guard selectService(withID: targetTab.serviceID) else {
                isExecutingHistoryNavigation = false
                return
            }
        }
        switchSession(to: targetTab.sessionIndex)
        isExecutingHistoryNavigation = false
        
        lastHistorySwitchTime = Date()
    }
    
    func handleGraveKeyDown(currentModifiers: NSEvent.ModifierFlags? = nil) {
        hideModifierHUDRing()
        guard !isActiveSpaceWebFullscreen else {
            showWebFullScreenBanner()
            return
        }
        guard !tabHistory.isEmpty else { return }
        
        let effectiveRingSize = tabHistory.count + 1
        
        if effectiveRingSize == 2 {
            let targetTab = tabHistory[0]
            isExecutingHistoryNavigation = true
            if currentService()?.id != targetTab.serviceID {
                guard selectService(withID: targetTab.serviceID) else {
                    isExecutingHistoryNavigation = false
                    return
                }
            }
            switchSession(to: targetTab.sessionIndex)
            isExecutingHistoryNavigation = false
            
            if let startTab = lastActiveTab, startTab != targetTab {
                tabHistory.removeAll { $0 == startTab }
                tabHistory.insert(startTab, at: 0)
                tabHistory.removeAll { $0 == targetTab }
                if tabHistory.count > 1 {
                    tabHistory = Array(tabHistory.prefix(1))
                }
                lastActiveTab = targetTab
            }
            return
        }
        
        if isGraveKeyHeld { return }
        isGraveKeyHeld = true
        
        let directionChanged = isCyclingHistory && !isCyclingForward
        isCyclingForward = true
        
        if !isCyclingHistory {
            isCyclingHistory = true
            cyclingHistoryIndex = 0
            if let service = currentService() {
                let activeIndex = activeIndicesByID[service.id] ?? 0
                cyclingStartTab = TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
            }
            highlightedTab = cyclingStartTab
            showTabHistoryHUD()
        } else if directionChanged {
            var cycleTabs = tabHistory
            if let start = cyclingStartTab {
                cycleTabs.append(start)
            }
            if let currIdx = cycleTabs.firstIndex(where: { $0 == highlightedTab }) {
                cyclingHistoryIndex = (currIdx + 1) % cycleTabs.count
            }
        }
        
        advanceHistoryCycling(allowRotation: true)

        // The Carbon hotkey callback is delivered asynchronously: on a fast
        // ⌘` tap, Cmd can already be released by the time this runs, so the
        // flagsChanged-based cycle end never fires. Finish the gesture now.
        guard areCommandModifiersHeld(currentModifiers) else {
            endHistoryCycling()
            return
        }

        // Start keyboard repeat delay timer (400ms)
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.startRapidHistoryRepeat()
            }
        }
    }

    func handleGraveBackwardKeyDown(currentModifiers: NSEvent.ModifierFlags? = nil) {
        hideModifierHUDRing()
        guard !isActiveSpaceWebFullscreen else {
            showWebFullScreenBanner()
            return
        }
        guard !tabHistory.isEmpty else { return }
        
        let effectiveRingSize = tabHistory.count + 1
        
        if effectiveRingSize == 2 {
            let targetTab = tabHistory[0]
            isExecutingHistoryNavigation = true
            if currentService()?.id != targetTab.serviceID {
                guard selectService(withID: targetTab.serviceID) else {
                    isExecutingHistoryNavigation = false
                    return
                }
            }
            switchSession(to: targetTab.sessionIndex)
            isExecutingHistoryNavigation = false
            
            if let startTab = lastActiveTab, startTab != targetTab {
                tabHistory.removeAll { $0 == startTab }
                tabHistory.insert(startTab, at: 0)
                tabHistory.removeAll { $0 == targetTab }
                if tabHistory.count > 1 {
                    tabHistory = Array(tabHistory.prefix(1))
                }
                lastActiveTab = targetTab
            }
            return
        }
        
        if isGraveKeyHeld { return }
        isGraveKeyHeld = true
        
        let directionChanged = isCyclingHistory && isCyclingForward
        isCyclingForward = false
        
        if !isCyclingHistory {
            isCyclingHistory = true
            if let service = currentService() {
                let activeIndex = activeIndicesByID[service.id] ?? 0
                cyclingStartTab = TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
            }
            
            var cycleTabs = tabHistory
            if let start = cyclingStartTab {
                cycleTabs.append(start)
            }
            cyclingHistoryIndex = max(0, cycleTabs.count - 2)
            highlightedTab = cyclingStartTab
            showTabHistoryHUD()
        } else if directionChanged {
            var cycleTabs = tabHistory
            if let start = cyclingStartTab {
                cycleTabs.append(start)
            }
            if let currIdx = cycleTabs.firstIndex(where: { $0 == highlightedTab }) {
                cyclingHistoryIndex = (currIdx - 1 + cycleTabs.count) % cycleTabs.count
            }
        }
        
        advanceHistoryCycling(allowRotation: true)

        // Same asynchronous-delivery guard as the forward variant above.
        guard areCommandModifiersHeld(currentModifiers) else {
            endHistoryCycling()
            return
        }

        // Start keyboard repeat delay timer (400ms)
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.startRapidHistoryRepeat()
            }
        }
    }

    /// Whether the ⌘ modifier is still down. `currentModifiers` lets callers
    /// (and tests) pin the state at gesture time instead of reading live.
    private func areCommandModifiersHeld(_ currentModifiers: NSEvent.ModifierFlags?) -> Bool {
        let modifiers = currentModifiers ?? NSEvent.modifierFlags
        return modifiers.contains(.command)
    }
    
    private func startRapidHistoryRepeat() {
        guard isGraveKeyHeld && isCyclingHistory else { return }
        
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.advanceHistoryCycling(allowRotation: false)
            }
        }
    }
    
    func handleGraveKeyUp() {
        isGraveKeyHeld = false
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = nil
    }
    
    func advanceHistoryCycling(allowRotation: Bool) {
        guard isCyclingHistory else { return }
        
        var cycleTabs = tabHistory
        if let start = cyclingStartTab {
            cycleTabs.append(start)
        }
        guard !cycleTabs.isEmpty else { return }
        
        let currentHighlightedIndex = (cyclingHistoryIndex - (isCyclingForward ? 1 : -1) + cycleTabs.count) % cycleTabs.count
        
        if !allowRotation {
            if isCyclingForward {
                if currentHighlightedIndex == cycleTabs.count - 2 {
                    return
                }
            } else {
                if currentHighlightedIndex == cycleTabs.count - 1 {
                    return
                }
            }
        }
        
        let nextIndex = cyclingHistoryIndex
        let targetTab = cycleTabs[nextIndex]
        highlightedTab = targetTab
        
        tabHistoryHUDView?.updateSelection()
        
        if isCyclingForward {
            cyclingHistoryIndex = (cyclingHistoryIndex + 1) % cycleTabs.count
        } else {
            cyclingHistoryIndex = (cyclingHistoryIndex - 1 + cycleTabs.count) % cycleTabs.count
        }
    }
    
    func cancelHistoryCycling() {
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = nil
        historyDebounceTimer?.invalidate()
        historyDebounceTimer = nil
        
        hideTabHistoryHUD()
        
        isCyclingHistory = false
        highlightedTab = nil
        cyclingStartTab = nil
        isGraveKeyHeld = false
    }
    
    func endHistoryCycling() {
        historyRepeatTimer?.invalidate()
        historyRepeatTimer = nil
        historyDebounceTimer?.invalidate()
        historyDebounceTimer = nil
        
        performPendingHistorySwitch()
        
        hideTabHistoryHUD()
        
        guard isCyclingHistory else { return }
        isCyclingHistory = false
        highlightedTab = nil
        lastHistorySwitchTime = nil
        
        guard let startTab = cyclingStartTab, let service = currentService() else {
            cyclingStartTab = nil
            return
        }
        
        let activeIndex = activeIndicesByID[service.id] ?? 0
        let currentTab = TabIdentifier(serviceID: service.id, sessionIndex: activeIndex)
        
        if startTab != currentTab {
            tabHistory.removeAll { $0 == startTab }
            tabHistory.insert(startTab, at: 0)
            
            tabHistory.removeAll { $0 == currentTab }
            
            let ringSize = Settings.shared.tabNavigationRingSize
            if tabHistory.count > ringSize - 1 {
                tabHistory = Array(tabHistory.prefix(ringSize - 1))
            }
            
            lastActiveTab = currentTab
        }
        
        cyclingStartTab = nil
    }
}
