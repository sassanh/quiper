import AppKit
import Carbon

extension MainWindowController {
    
    // MARK: - Input Handling
    
    func setShortcutsEnabled(_ enabled: Bool) {
        if enabled {
            if keyDownEventMonitor == nil {
                keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self = self else { return event }
                    if event.type == .keyDown {
                        if GhostOnboardingManager.shared.isActive {
                            if event.keyCode == kVK_Return || event.keyCode == kVK_Space {
                                GhostOnboardingManager.shared.advanceStep()
                            }
                            // Swallow ALL keys during onboarding — no shortcuts, no typing
                            return nil
                        }
                        
                        // Invalidate Command modifier tap-timings upon keyboard activity
                        self.lastCommandPressedTime = 0
                        self.lastCommandReleasedTime = 0
                        self.wasBothCmdsDown = false
                        
                        if self.modifierHUDView != nil {
                            if event.keyCode == kVK_Escape {
                                self.hideModifierHUD()
                                return nil // Swallow escape so it doesn't hide the main window
                            }
                        }
                        if self.modifierHUDView != nil {
                            let hasModifier = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control)
                            if hasModifier {
                                self.hideModifierHUD()
                            }
                        }
                        if self.handleCommandShortcut(event: event) == true {
                            return nil
                        }
                    } else if event.type == .flagsChanged {
                        self.handleFlagsChanged(event: event)
                    }
                    return event
                }
            }
        } else {
            if let monitor = keyDownEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownEventMonitor = nil
            }
        }
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
        return mainWindow?.attachedSheet != nil
            || NSApp.windows.contains { $0 !== mainWindow && $0.isVisible && $0.isKeyWindow && !($0 is ActivePanel) }
    }

    func handleFlagsChanged(event: NSEvent) {
        if !(skipModalCheck || !hasModalWindow) { return }
        
        if GhostOnboardingManager.shared.isActive {
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
        
        var shouldExpandSession = false
        let sessionMask = NSEvent.ModifierFlags(rawValue: appShortcuts.sessionDigitsModifiers)
        if appShortcuts.sessionDigitsModifiers > 0 && modifiers == sessionMask {
             shouldExpandSession = true
        } else if let alt = appShortcuts.sessionDigitsAlternateModifiers, alt > 0,
                  modifiers == NSEvent.ModifierFlags(rawValue: alt) {
             shouldExpandSession = true
        }
        
        var shouldExpandService = false
        let servicePrimaryMask = NSEvent.ModifierFlags(rawValue: appShortcuts.serviceDigitsPrimaryModifiers)
        if appShortcuts.serviceDigitsPrimaryModifiers > 0 && modifiers == servicePrimaryMask {
             shouldExpandService = true
        } else if let sec = appShortcuts.serviceDigitsSecondaryModifiers, sec > 0,
                  modifiers == NSEvent.ModifierFlags(rawValue: sec) {
             shouldExpandService = true
        }
        
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
        
        let shouldShowHeader = (shouldExpandSession || shouldExpandService) && Settings.shared.showHiddenBarOnModifiers
        if isModifiersForHeaderDown != shouldShowHeader {
            isModifiersForHeaderDown = shouldShowHeader
            updateHeaderVisibility()
        }
    }
    
    private func showModifierHUD() {
        guard let contentView = window?.contentView else { return }
        NSLog("[QuiperDebug] showModifierHUD called, current HUD is \(modifierHUDView == nil ? "nil" : "not nil")")
        if modifierHUDView == nil {
            modifierHUDView = ModifierHUDView(frame: contentView.bounds, windowController: self)
        }
        if let hud = modifierHUDView, hud.superview == nil {
            hud.show(in: contentView)
        }
    }
    
    func hideModifierHUD() {
        NSLog("[QuiperDebug] hideModifierHUD called")
        if let hud = modifierHUDView, hud.superview != nil {
            hud.hide()
            modifierHUDView = nil
        }
    }
    
    func toggleModifierHUD() {
        NSLog("[QuiperDebug] toggleModifierHUD called, HUD is \(modifierHUDView == nil ? "nil" : "not nil"), superview is \(modifierHUDView?.superview == nil ? "nil" : "not nil")")
        if modifierHUDView != nil && modifierHUDView?.superview != nil {
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
        let appShortcuts = Settings.shared.appShortcutBindings
        let config = HotkeyManager.Configuration(keyCode: UInt32(keyCode), modifierFlags: modifiers.rawValue)

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isControl = modifiers.contains(.control)
        let isOption = modifiers.contains(.option)
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isControl && isShift && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        if isEmptyStateActive {
            if let service = services.first(where: { $0.activationShortcut == config }) {
                _ = selectService(withURL: service.url)
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
            if matches(config, appShortcuts.configuration(for: .previousService)) || matches(config, appShortcuts.alternateConfiguration(for: .previousService)) {
                stepService(by: -1)
                return true
            }
            
            if isCommand {
                switch key {
                case "m":
                    toggleWindowSize()
                    return true
                case "h", "q":
                    hide()
                    return true
                case ",":
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
        
        if let action = Settings.shared.customActions.first(where: { $0.shortcut == config }) {
            performCustomAction(action)
            return true
        }
        
        if let service = services.first(where: { $0.activationShortcut == config }) {
            _ = selectService(withURL: service.url)
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
            if key == "i" {
                toggleInspector()
                return true
            } else if key == "r" {
                // Allow Option+Command+R to fall through
            } else {
                return false
            }
        }

        switch key {
        case "m":
            toggleWindowSize()
            return true
        case "h":
            hide()
            return true
        case "q":
            hide()
            return true
        case "w":
            closeCurrentTab()
            return true
        case "r":
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
        case "f":
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.show()
            return true
        case "g":
            guard !isInspectorFocused() else {
                return false
            }
            findBarViewController.handleFindRepeat(shortcutShifted: isShift)
            return true
        case ",":
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return true
        case "=":
            guard !isInspectorFocused() else {
                return false
            }
            zoom(by: Zoom.step)
            return true
        case "-":
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
    
    private func matches(_ lhs: HotkeyManager.Configuration, _ rhs: HotkeyManager.Configuration?) -> Bool {
        guard let rhs = rhs, !rhs.isDisabled else { return false }
        return lhs.keyCode == rhs.keyCode && lhs.modifierFlags == rhs.modifierFlags
    }
}
