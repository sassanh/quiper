import AppKit
import WebKit

extension MainWindowController {
    
    // MARK: - Selector Layout & Synchronization
    
    func updateSelectorsMode() {
        let mode = Settings.shared.selectorDisplayMode
        let windowWidth = window?.frame.width ?? 0

        let useCompact: Bool
        if GhostOnboardingManager.shared.isActive {
            useCompact = true
        } else {
            switch mode {
            case .expanded: useCompact = false
            case .compact: useCompact = true
            case .auto:
                let inset: CGFloat = 4
                let isHiddenMode = Settings.shared.topBarVisibility == .hidden
                let gap: CGFloat = isHiddenMode ? 8 : 4
                let buttonSize: CGFloat = 24
                let minimumServiceWidth: CGFloat = 150
                let titleAreaMargin: CGFloat = 2
                let minTitleWidth: CGFloat = 120

                let showActionsButton = Settings.shared.dockVisibility == .never
                let rightOffset = showActionsButton ? (inset + buttonSize + gap) : inset

                let staticServiceWidth = max(minimumServiceWidth, estimatedWidthForServiceSegments())
                let staticSessionWidth = sessionSelector?.fittingSize.width ?? 0

                let rsButtonSpace: CGFloat = 20 + gap
                let requiredWidth = minTitleWidth + rsButtonSpace + rightOffset + inset + staticSessionWidth + staticServiceWidth + (2 * gap) + (2 * titleAreaMargin)

                useCompact = windowWidth < requiredWidth
            }
        }

        serviceSelector?.isHidden = useCompact
        collapsibleServiceSelector?.isHidden = !useCompact
 
        let isEngineLocked: Bool = {
            guard let service = currentService() else { return false }
            return service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        }()
 
        if isEngineLocked {
            sessionSelector?.isHidden = true
            collapsibleSessionSelector?.isHidden = true
        } else {
            sessionSelector?.isHidden = useCompact
            collapsibleSessionSelector?.isHidden = !useCompact
        }

        syncSelectorSelections()
    }
    
    func syncSelectorSelections() {
        let serviceIdx = services.firstIndex(where: { $0.url == currentServiceURL }) ?? 0
        serviceSelector?.selectedSegment = serviceIdx
        collapsibleServiceSelector?.selectedSegment = serviceIdx
        
        if isEmptyStateActive {
            sessionSelector?.selectedSegment = -1
            collapsibleSessionSelector?.selectedSegment = -1
        } else {
            let sessionIdx = segmentIndex(forSession: activeIndicesByURL[currentServiceURL ?? ""] ?? 0)
            sessionSelector?.selectedSegment = sessionIdx
            collapsibleSessionSelector?.selectedSegment = sessionIdx
        }
    }

    func layoutSelectors() {
        updateSelectorsMode()
        
        guard let drag = dragArea,
              let title = titleLabel,
              let actionsBtn = sessionActionsButton else { return }
        
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        findBarViewController?.layoutIn(parentWindow: window!, topOffset: isBottom ? 0 : Constants.DRAGGABLE_AREA_HEIGHT)

        let activeServiceSel = (serviceSelector?.isHidden == false) ? serviceSelector : (collapsibleServiceSelector?.isHidden == false ? collapsibleServiceSelector : nil)
        let activeSessionSel = (sessionSelector?.isHidden == false) ? sessionSelector : (collapsibleSessionSelector?.isHidden == false ? collapsibleSessionSelector : nil)
        
        guard let serviceSel = activeServiceSel else { return }

        let isHiddenMode = Settings.shared.topBarVisibility == .hidden

        let headerHeight = drag.bounds.size.height
        let selectorHeight: CGFloat = 25
        let gap: CGFloat = isHiddenMode ? 8 : 4
        let buttonSize: CGFloat = 24
        let minimumServiceWidth: CGFloat = 150

        let inset: CGFloat = isHiddenMode ? 0 : 4

        let selectorY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - selectorHeight) / 2
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - selectorHeight) / 2
            }
        }()

        let buttonY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - buttonSize) / 2
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - buttonSize) / 2
            }
        }()

        let showActionsButton = Settings.shared.dockVisibility == .never
        actionsBtn.isHidden = !showActionsButton

        if showActionsButton {
            actionsBtn.frame = NSRect(
                x: drag.bounds.width - inset - buttonSize,
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )
        } else {
            actionsBtn.frame = .zero
        }

        let rightReferenceX = showActionsButton ? (actionsBtn.frame.minX - gap) : (drag.bounds.width - inset)

        let sessionWidth: CGFloat
        if let sessionSel = activeSessionSel {
            if let coll = sessionSel as? CollapsibleSelector {
                sessionWidth = coll.currentWidth
            } else {
                sessionWidth = sessionSel.fittingSize.width
            }
        } else {
            sessionWidth = 0
        }

        let serviceWidth: CGFloat
        if let coll = serviceSel as? CollapsibleSelector {
            serviceWidth = coll.currentWidth
        } else {
            serviceWidth = max(minimumServiceWidth, estimatedWidthForServiceSegments())
        }

        let maxServiceWidth = max(minimumServiceWidth,
                                  rightReferenceX - gap - sessionWidth - (sessionWidth > 0 ? gap : 0))
        let actualServiceWidth = min(serviceWidth, maxServiceWidth)

        serviceSel.frame = NSRect(
            x: inset,
            y: selectorY,
            width: actualServiceWidth,
            height: selectorHeight
        )

        if let sessionSel = activeSessionSel {
            let sessionX = rightReferenceX - sessionWidth
            sessionSel.frame = NSRect(
                x: sessionX,
                y: selectorY,
                width: sessionWidth,
                height: selectorHeight
            )
        }

        let titleAreaMargin: CGFloat = 2
        
        let navGroupWidth = navigationButtonGroup.idealWidth
        let showNav = !isEmptyStateActive && !navigationButtonGroup.isHidden && navGroupWidth > 0
        
        let leftSideMaxX: CGFloat
        if showNav {
            let navX = serviceSel.frame.maxX + gap
            navigationButtonGroup.frame = NSRect(
                x: navX,
                y: selectorY,
                width: navGroupWidth,
                height: selectorHeight
            )
            leftSideMaxX = navigationButtonGroup.frame.maxX
        } else {
            leftSideMaxX = serviceSel.frame.maxX
            navigationButtonGroup.isHidden = true
        }
        
        let rsButtonSize: CGFloat = 24
        let rsX: CGFloat
        if let sessionSel = activeSessionSel {
            rsX = sessionSel.frame.minX - gap - rsButtonSize
        } else {
            rsX = rightReferenceX - rsButtonSize
        }
        
        refreshStopButton.frame = NSRect(
            x: rsX,
            y: buttonY,
            width: rsButtonSize,
            height: rsButtonSize
        )
        
        let isEngineLocked = {
            guard let service = currentService() else { return false }
            return service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        }()
        
        if isEmptyStateActive || isEngineLocked {
            refreshStopButton.isHidden = true
        } else {
            refreshStopButton.isHidden = false
        }
        
        let shouldShowManualLock = {
            guard let service = currentService() else { return false }
            return !isEmptyStateActive && service.isEncrypted && EncryptedVolumeManager.shared.isUnlocked(for: service.id)
        }()
        
        if shouldShowManualLock {
            manualLockButton.isHidden = false
            let lockX = rsX - gap - rsButtonSize
            manualLockButton.frame = NSRect(
                x: lockX,
                y: buttonY,
                width: rsButtonSize,
                height: rsButtonSize
            )
        } else {
            manualLockButton.isHidden = true
        }
        
        let rightSideMinX = shouldShowManualLock ? manualLockButton.frame.minX : (refreshStopButton.isHidden ? rsX : refreshStopButton.frame.minX)
        
        let titleAreaX = leftSideMaxX + gap + titleAreaMargin
        let titleWidth = max(0, rightSideMinX - gap - titleAreaMargin - titleAreaX)
        
        let minTitleAreaWidth: CGFloat = 40
        let shouldHideTitleArea = titleWidth < minTitleAreaWidth
        
        if let borderView = loadingBorderView {
            borderView.frame = NSRect(
                x: titleAreaX,
                y: selectorY,
                width: titleWidth,
                height: selectorHeight
            )
            borderView.isHidden = isEmptyStateActive || shouldHideTitleArea || !borderView.isAnimating
        }
        
        let titlePadding: CGFloat = 4
        let titleLabelWidth = max(0, titleWidth - titlePadding * 2)
        let titleHeight = title.intrinsicContentSize.height
        let titleY: CGFloat = {
            if isHiddenMode {
                let visualBarHeight = headerHeight + barBorderWidth
                let centerFromVisualBottom = (visualBarHeight - titleHeight) / 2
                return isBottom ? centerFromVisualBottom - barBorderWidth : centerFromVisualBottom
            } else {
                return (headerHeight - titleHeight) / 2
            }
        }()
        title.frame = NSRect(
            x: titleAreaX + titlePadding,
            y: titleY,
            width: titleLabelWidth,
            height: titleHeight
        )
        title.isHidden = shouldHideTitleArea
    }

    func refreshServiceSegments() {
        serviceSelector?.segmentCount = services.count
        let items = services.map { $0.name }
        
        for (index, item) in items.enumerated() {
            serviceSelector?.setLabel(item, forSegment: index)
            serviceSelector?.setToolTip(services[index].name, forSegment: index)
        }

        collapsibleServiceSelector?.setItems(items)
        
        if let idx = services.firstIndex(where: { $0.url == currentServiceURL }) {
            collapsibleServiceSelector?.selectedSegment = idx
            serviceSelector?.selectedSegment = idx
        } else {
            if services.isEmpty {
                currentServiceURL = nil
                currentServiceName = nil
                titleLabel?.stringValue = ""
                collapsibleServiceSelector?.selectedSegment = -1
                serviceSelector?.selectedSegment = -1
                loadingBorderView?.stopAnimating()
            } else {
                collapsibleServiceSelector?.selectedSegment = 0
                serviceSelector?.selectedSegment = 0
            }
            currentServiceName = services.first?.name
        }
        layoutSelectors()
    }

    func syncCurrentServiceSelection() {
        if let url = currentServiceURL,
           let match = services.first(where: { $0.url == url }) {
            currentServiceName = match.name
            return
        }
        if let name = currentServiceName,
           let match = services.first(where: { $0.name == name }) {
            currentServiceURL = match.url
            currentServiceName = match.name
            return
        }
        currentServiceName = services.first?.name
        currentServiceURL = services.first?.url
    }

    func updateSessionSelector() {
        guard let service = currentService() else { return }
        let index = activeIndicesByURL[service.url] ?? 0
        let segmentIdx = segmentIndex(forSession: index)
        
        if let selector = sessionSelector {
            for sessionIdx in 0..<10 {
                let segIdx = segmentIndex(forSession: sessionIdx)
                let title = webViewManager.getWebView(for: service, sessionIndex: sessionIdx)?.title ?? "Session \(sessionIdx == 9 ? 0 : sessionIdx + 1)"
                selector.setToolTip(title, forSegment: segIdx)
                collapsibleSessionSelector?.setToolTip(title, forSegment: segIdx)
            }
        } else if let collapsible = collapsibleSessionSelector {
             for sessionIdx in 0..<10 {
                let segIdx = segmentIndex(forSession: sessionIdx)
                let title = webViewManager.getWebView(for: service, sessionIndex: sessionIdx)?.title ?? "Session \(sessionIdx == 9 ? 0 : sessionIdx + 1)"
                collapsible.setToolTip(title, forSegment: segIdx)
            }
        }

        if isEmptyStateActive {
            sessionSelector?.selectedSegment = -1
            collapsibleSessionSelector?.selectedSegment = -1
        } else {
            sessionSelector?.selectedSegment = segmentIdx
            collapsibleSessionSelector?.selectedSegment = segmentIdx
        }
        sessionSelector?.needsDisplay = true
        collapsibleSessionSelector?.needsDisplay = true
    }

    var activeServiceSelector: NSView? {
        if let sel = serviceSelector, !sel.isHidden { return sel }
        if let sel = collapsibleServiceSelector, !sel.isHidden { return sel }
        return nil
    }

    var activeSessionSelector: NSView? {
        if let sel = sessionSelector, !sel.isHidden { return sel }
        if let sel = collapsibleSessionSelector, !sel.isHidden { return sel }
        return nil
    }

    func estimatedWidthForServiceSegments() -> CGFloat {
        let font = serviceSelector?.font ?? NSFont.systemFont(ofSize: 13)
        return services.reduce(0) { partialResult, service in
            let size = (service.name as NSString).size(withAttributes: [.font: font])
            return partialResult + size.width + 20
        }
    }

    func sessionIndex(forSegment segment: Int) -> Int {
        segment == 9 ? 9 : segment
    }

    func segmentIndex(forSession session: Int) -> Int {
        session == 9 ? 9 : session
    }
}
