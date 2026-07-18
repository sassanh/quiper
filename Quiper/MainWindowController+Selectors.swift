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

                let rsButtonSpace: CGFloat = 24 + gap
                let trashButtonSpace: CGFloat = 24 + gap
                let requiredWidth = minTitleWidth + rsButtonSpace + trashButtonSpace + rightOffset + inset + staticSessionWidth + staticServiceWidth + (2 * gap) + (2 * titleAreaMargin)

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
        
        var leftSideMaxX: CGFloat
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
        
        let showHistoryBtn = !isEmptyStateActive
        if showHistoryBtn {
            promptHistoryButton.isHidden = false
            let historyX = leftSideMaxX + gap
            promptHistoryButton.frame = NSRect(
                x: historyX,
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )
            leftSideMaxX = promptHistoryButton.frame.maxX
        } else {
            promptHistoryButton.isHidden = true
        }
        
        let rsButtonSize: CGFloat = 24
        
        let trashX: CGFloat
        let rsX: CGFloat
        if let sessionSel = activeSessionSel {
            trashX = sessionSel.frame.minX - gap - rsButtonSize
            rsX = trashX - gap - rsButtonSize
        } else {
            trashX = rightReferenceX - rsButtonSize
            rsX = trashX - gap - rsButtonSize
        }
        
        trashSessionButton.frame = NSRect(
            x: trashX,
            y: buttonY,
            width: rsButtonSize,
            height: rsButtonSize
        )
        
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
            trashSessionButton.isHidden = true
        } else {
            refreshStopButton.isHidden = false
            trashSessionButton.isHidden = false
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
        
        let rightSideMinX: CGFloat
        if shouldShowManualLock {
            rightSideMinX = manualLockButton.frame.minX
        } else if !refreshStopButton.isHidden {
            rightSideMinX = refreshStopButton.frame.minX
        } else if !trashSessionButton.isHidden {
            rightSideMinX = trashSessionButton.frame.minX
        } else if let sessionSel = activeSessionSel {
            rightSideMinX = sessionSel.frame.minX
        } else {
            rightSideMinX = rightReferenceX
        }
        
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
        let items = services.map { $0.name }
        
        if let segControl = serviceSelector {
            segControl.segmentCount = items.count
            segControl.customLockedStates = services.map { $0.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: $0.id) }
            segControl.customLabels = items
        }
        
        for (index, item) in items.enumerated() {
            serviceSelector?.setLabel(item, forSegment: index)
            serviceSelector?.setToolTip(services[index].name, forSegment: index)
            serviceSelector?.setImage(nil, forSegment: index)
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

    static func sessionTooltipTitle(pageTitle: String?, fallbackTitle: String? = nil, sessionIndex: Int) -> String {
        for title in [pageTitle, fallbackTitle] {
            let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedTitle.isEmpty {
                return trimmedTitle
            }
        }
        return "Session \(sessionIndex == 9 ? 0 : sessionIndex + 1)"
    }

    func updateSessionTooltip(
        for service: Service,
        sessionIndex: Int,
        preferredTitle: String? = nil,
        isLoading: Bool? = nil
    ) {
        guard service.url == currentServiceURL else { return }

        let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex)
        let toolTip = webView.map {
            Self.sessionTooltipTitle(
                pageTitle: preferredTitle ?? $0.title,
                fallbackTitle: webViewManager.sessionTitle(for: service, sessionIndex: sessionIndex),
                sessionIndex: sessionIndex
            )
        }
        let segment = segmentIndex(forSession: sessionIndex)

        sessionSelector?.setToolTip(toolTip, forSegment: segment)
        collapsibleSessionSelector?.setToolTip(toolTip, forSegment: segment)

        if let toolTip, let selector = sessionSelector {
            QuickTooltip.shared.updateIfVisible(
                with: toolTip,
                for: selector,
                segment: segment,
                isLoading: isLoading ?? webView?.isLoading ?? false
            )
        }
    }

    func updateSessionSelector() {
        guard let service = currentService() else { return }
        let index = activeIndicesByURL[service.url] ?? 0
        let segmentIdx = segmentIndex(forSession: index)

        for sessionIndex in 0..<10 {
            updateSessionTooltip(for: service, sessionIndex: sessionIndex)
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
        let font = serviceSelector?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: serviceSelector?.controlSize ?? .regular))
        return services.reduce(0) { partialResult, service in
            let size = (service.name as NSString).size(withAttributes: [.font: font])
            let isLocked = service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
            let w = size.width + 16 + (isLocked ? 13 : 0)
            return partialResult + w
        }
    }

    func sessionIndex(forSegment segment: Int) -> Int {
        segment == 9 ? 9 : segment
    }

    func segmentIndex(forSession session: Int) -> Int {
        session == 9 ? 9 : session
    }
}
