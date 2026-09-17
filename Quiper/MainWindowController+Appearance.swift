import AppKit

extension MainWindowController {
    
    // MARK: - Appearance & Theming

    /// True only when the user can actually interact with the overlay content.
    /// Settings and update prompts take key in child windows; the overlay
    /// behind them counts as unfocused so its animations freeze.
    var hasWindowFocus: Bool {
        guard let window else { return false }
        guard window.isKeyWindow, NSApp.isActive else { return false }
        if AppDelegate.sharedSettingsWindow.isVisible { return false }
        if UpdatePromptWindowController.shared.window?.isVisible == true { return false }
        return true
    }

    /// Single gate for focus-driven chrome state. Animation freezing
    /// (outline, title border, tooltip) and the composer indicator hide
    /// always follow focus. Visuals (vibrancy, outline/margin dim, header
    /// dim, content transparency, focus shield) follow the focus-loss
    /// effect setting. Web content is only faded, never recolored.
    func updateFocusAppearance() {
        let focused = hasWindowFocus
        let effectOn = !focused && Settings.shared.focusLossEffectEnabled
        windowOutlineView?.setWindowFocused(focused)
        windowMarginView?.setWindowFocused(focused)
        loadingBorderView?.setWindowFocused(focused)
        QuickTooltip.shared.setWindowFocused(focused)
        webViewManager?.setWindowHasFocus(focused)
        backgroundEffectView?.state = effectOn ? .inactive : .active
        webViewManager?.setContentTransparent(effectOn)
        emptyStateView?.alphaValue = effectOn ? 0.5 : 1.0
        setHeaderDimmed(effectOn)
        setFocusShieldHidden(!effectOn)
    }

    /// Shows the transparent focus shield when unfocused. Repositions it
    /// directly below the header first: web wrappers added later also go
    /// below the header and would otherwise end up above the shield.
    private func setFocusShieldHidden(_ hidden: Bool) {
        guard let shieldView = focusShieldView else { return }
        if hidden {
            shieldView.isHidden = true
        } else {
            if let contentView = window?.contentView, let drag = dragArea,
               shieldView.superview === contentView {
                contentView.addSubview(shieldView, positioned: .below, relativeTo: drag)
            }
            shieldView.isHidden = false
        }
    }

    /// Dims header controls when unfocused. This gate owns dragArea
    /// subviews' alphaValue; subviews must not manage their own alpha.
    /// dragArea.alphaValue itself stays owned by header show/hide logic.
    private func setHeaderDimmed(_ dimmed: Bool) {
        let alpha: CGFloat = dimmed ? 0.5 : 1.0
        dragArea?.subviews.forEach { $0.alphaValue = alpha }
    }
    
    @objc func appearanceSettingsChanged() {
        updateWindowMarginAndLayout()
    }
    
    @objc func handleWindowAppearanceChanged(_ notification: Notification) {
        applyWindowAppearance()
        updateWindowMarginAndLayout()
    }
    
    @objc func handleColorSchemeChanged(_ notification: Notification) {
        applyColorScheme()
    }

    func applyColorScheme() {
        let scheme = Settings.shared.colorScheme
        let appearance = scheme.nsAppearance
        window?.appearance = appearance
        blurWindow?.appearance = appearance
        applyWindowAppearance()
    }
    
    func currentThemeSettings() -> ThemeAppearanceSettings? {
        guard let win = window else { return nil }
        let effectiveAppearance = win.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? Settings.shared.windowAppearance.dark : Settings.shared.windowAppearance.light
    }
    
    func applyWindowAppearance() {
        guard let win = window, let themeSettings = currentThemeSettings() else { return }
        
        win.isOpaque = false
        win.backgroundColor = .clear
        setWindowBlurRadius(win, radius: 1)
        
        if blurWindow == nil {
            let bw = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            bw.isOpaque = false
            bw.backgroundColor = .clear
            bw.hasShadow = false
            bw.ignoresMouseEvents = true
            win.addChildWindow(bw, ordered: .below)
            blurWindow = bw
            updateCollectionBehaviorForVisibilityState()
        }
        
        guard let bw = blurWindow else { return }
        
        bw.backgroundColor = .clear
        bw.contentView?.wantsLayer = true
        
        switch themeSettings.mode {
        case .macOSEffects:
            bw.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            setWindowBlurRadius(bw, radius: themeSettings.blurRadius)
            
            backgroundEffectView?.isHidden = false
            backgroundEffectView?.material = themeSettings.material.nsMaterial
            contentColorView?.isHidden = true

        case .solidColor:
            backgroundEffectView?.isHidden = true
            contentColorView?.isHidden = true
            
            bw.contentView?.layer?.backgroundColor = themeSettings.backgroundColor.nsColor.cgColor
            setWindowBlurRadius(bw, radius: themeSettings.blurRadius)
        }
        
        updateBlurWindowFrame()
        win.contentView?.needsDisplay = true
    }
    
    func updateBlurWindowFrame() {
        guard let win = window, let bw = blurWindow, let contentView = win.contentView else { return }
        
        let targetFrame = backgroundEffectView?.frame ?? contentView.bounds
        let rectInScreen = win.convertToScreen(targetFrame)
        
        bw.setFrame(rectInScreen, display: true)
        
        bw.contentView?.wantsLayer = true
        bw.contentView?.layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        bw.contentView?.layer?.masksToBounds = true
        
        bw.contentView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    private func setWindowBlurRadius(_ window: NSWindow, radius: Double) {
        CGSFuncs.initialize()
        
        guard let getMainConnection = CGSFuncs.getMainConnection,
              let setBlurRadius = CGSFuncs.setBlurRadius else { return }
        
        let connection = getMainConnection()
        
        if window.windowNumber > 0 {
             let wid = UInt32(window.windowNumber)
             let intRadius = Int32(radius)
             
             if intRadius > 0 {
                 window.hasShadow = false
                 window.isOpaque = false
             } 

             let result = setBlurRadius(connection, wid, intRadius)
             if result != 0 {
                 NSLog("[Quiper] Warning: CGSSetWindowBackgroundBlurRadius failed: \(result)")
             }
        }
    }
    
    func updateCollectionBehaviorForVisibilityState() {
        guard let window = self.window else { return }

        // During an element-fullscreen session the overlay must stay out of
        // the Space owned by Quiper's own fullscreen content: pin it to a
        // single Space instead of joining all of them, or every Space switch
        // would drag it into the fullscreen Space (`.moveToActiveSpace`).
        if ownedElementFullscreenSpace != nil {
            window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
            return
        }

        let isVisible = window.isVisible
        let behavior: NSWindow.CollectionBehavior = (Settings.shared.showOnAllSpaces || !isVisible)
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        
        window.collectionBehavior = behavior
        
        if let bw = blurWindow {
            let bwBehavior: NSWindow.CollectionBehavior = (Settings.shared.showOnAllSpaces || !isVisible)
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                : [.transient, .ignoresCycle, .fullScreenAuxiliary]
            
            bw.collectionBehavior = bwBehavior
            window.removeChildWindow(bw)
            window.addChildWindow(bw, ordered: .below)
        }
    }
    
    @objc func handleShowOnAllSpacesChanged(_ notification: Notification) {
        updateCollectionBehaviorForVisibilityState()
    }

    @objc func handleFocusLossEffectChanged(_ notification: Notification) {
        updateFocusAppearance()
    }
}
