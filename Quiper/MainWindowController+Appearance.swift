import AppKit

extension MainWindowController {
    
    // MARK: - Appearance & Theming
    
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
        
        let isVisible = window.isVisible
        let behavior: NSWindow.CollectionBehavior = (Settings.shared.showOnAllSpaces || !isVisible)
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        
        window.collectionBehavior = behavior
        
        if let bw = blurWindow {
            bw.collectionBehavior = (Settings.shared.showOnAllSpaces || !isVisible)
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                : [.transient, .ignoresCycle, .fullScreenAuxiliary]
            window.removeChildWindow(bw)
            window.addChildWindow(bw, ordered: .below)
        }
        
        if let findBarPanel = findBarViewController?.panel {
            findBarPanel.collectionBehavior = (Settings.shared.showOnAllSpaces || !isVisible)
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                : [.transient, .ignoresCycle, .fullScreenAuxiliary]
            if findBarPanel.isVisible {
                window.removeChildWindow(findBarPanel)
                window.addChildWindow(findBarPanel, ordered: .above)
            }
        }
    }
    
    @objc func handleShowOnAllSpacesChanged(_ notification: Notification) {
        updateCollectionBehaviorForVisibilityState()
    }
}

