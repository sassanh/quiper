import AppKit

extension MainWindowController {
    
    // MARK: - Header Visibility & Mouse Tracking
    
    @objc func topBarVisibilityChanged() {
        updateWindowMarginAndLayout()
        updateHeaderTrackingArea()
        updateHeaderVisibility(animated: false)
    }
    
    @objc func dragAreaPositionChanged() {
        guard (window?.contentView) != nil else { return }
        windowMarginView?.setRevealed(false, edge: .none, animated: false)
        windowOutlineView?.setRevealed(false, edge: .none, animated: false)
        
        updateWindowMarginAndLayout()
        findBarViewController?.layoutIn(parentWindow: window!, topOffset: Settings.shared.dragAreaPosition == .top ? Constants.DRAGGABLE_AREA_HEIGHT : 0)
        updateHeaderTrackingArea()
        updateHeaderVisibility(animated: false)
    }

    func updateHeaderVisibility(animated: Bool = true) {
        guard !isUpdatingHeaderVisibility else { return }
        isUpdatingHeaderVisibility = true
        defer { isUpdatingHeaderVisibility = false }

        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let isHeaderHovered = isMouseInHeaderTrackingArea
        let isAnySelectorExpanded = (collapsibleSessionSelector?.isExpanded == true) || (collapsibleServiceSelector?.isExpanded == true)

        let shouldShowHeaderIfHidden = isHeaderHovered ||
                                       isModifiersForHeaderDown ||
                                       isHeaderForcedVisibleForAction ||
                                       isAnySelectorExpanded ||
                                       GhostOnboardingManager.shared.isActive

        let temporaryRevealAllowed = skipModalCheck || !hasModalWindow
        let finalVisible = !isHiddenMode || (shouldShowHeaderIfHidden && temporaryRevealAllowed)

        let isBottom = Settings.shared.dragAreaPosition == .bottom
        let edge: WindowMarginView.ThickEdge = isBottom ? .bottom : .top

        if isHiddenMode {
            let currentAlpha = dragArea?.alphaValue ?? 0
            let alreadyVisible = currentAlpha > 0.5
            if finalVisible {
                layoutSelectors()
                windowMarginView?.setRevealed(true, edge: edge, animated: animated)
                windowOutlineView?.setRevealed(true, edge: edge, animated: animated)
                if animated && !alreadyVisible {
                    let slideOffset: CGFloat = 8
                    let translateY: CGFloat = isBottom ? slideOffset : -slideOffset
                    let showDuration: CFTimeInterval = 0.25
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    dragArea?.layer?.transform = CATransform3DMakeTranslation(0, translateY, 0)
                    dragArea?.layer?.opacity = 0
                    CATransaction.commit()
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = showDuration
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        dragArea?.animator().alphaValue = 1.0
                    }
                    let slideAnim = CABasicAnimation(keyPath: "transform")
                    slideAnim.fromValue = CATransform3DMakeTranslation(0, translateY, 0)
                    slideAnim.toValue = CATransform3DIdentity
                    slideAnim.duration = showDuration
                    slideAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    slideAnim.isRemovedOnCompletion = true
                    dragArea?.layer?.add(slideAnim, forKey: "slideIn")
                    dragArea?.layer?.transform = CATransform3DIdentity
                } else if !animated {
                    dragArea?.layer?.removeAllAnimations()
                    dragArea?.layer?.transform = CATransform3DIdentity
                    dragArea?.alphaValue = 1.0
                }
            } else {
                collapsibleSessionSelector?.collapse()
                collapsibleServiceSelector?.collapse()
                stopSelectorCursorMonitor()
                windowMarginView?.setRevealed(false, edge: edge, animated: animated)
                windowOutlineView?.setRevealed(false, edge: edge, animated: animated)
                if animated && alreadyVisible {
                    let slideOffset: CGFloat = 8
                    let translateY: CGFloat = isBottom ? slideOffset : -slideOffset
                    let hideDuration: CFTimeInterval = 0.18
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = hideDuration
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        dragArea?.animator().alphaValue = 0.0
                    }
                    let slideAnim = CABasicAnimation(keyPath: "transform")
                    slideAnim.fromValue = CATransform3DIdentity
                    slideAnim.toValue = CATransform3DMakeTranslation(0, translateY, 0)
                    slideAnim.duration = hideDuration
                    slideAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    slideAnim.isRemovedOnCompletion = true
                    dragArea?.layer?.add(slideAnim, forKey: "slideOut")
                } else if !animated {
                    dragArea?.layer?.removeAllAnimations()
                    dragArea?.layer?.transform = CATransform3DIdentity
                    dragArea?.alphaValue = 0.0
                }
            }
        } else {
            windowMarginView?.setRevealed(false, edge: .none, animated: false)
            windowOutlineView?.setRevealed(false, edge: .none, animated: false)
            dragArea?.isTransparentBackground = false
            dragArea?.layer?.removeAllAnimations()
            dragArea?.layer?.transform = CATransform3DIdentity
            dragArea?.alphaValue = 1.0
            updateWindowMarginAndLayout()
        }
    }

    func updateHeaderTrackingArea() {
        guard let contentView = window?.contentView else { return }
        if let area = headerTrackingArea {
            contentView.removeTrackingArea(area)
        }
        let edgeStrip: CGFloat = 50
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        let y = isBottom ? 0 : contentView.bounds.height - edgeStrip
        let trackingRect = NSRect(x: 0, y: y, width: contentView.bounds.width, height: edgeStrip)
        let area = NSTrackingArea(rect: trackingRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        contentView.addTrackingArea(area)
        headerTrackingArea = area
    }
    
    var isMouseInHeaderTrackingArea: Bool {
        guard let window = self.window,
              let trackingArea = headerTrackingArea,
              let contentView = window.contentView else { return false }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: mouseLocation)
        let viewLocation = contentView.convert(windowLocation, from: nil)
        
        return trackingArea.rect.contains(viewLocation)
    }
    
    override func mouseEntered(with event: NSEvent) {
        if let area = headerTrackingArea, event.trackingArea == area {
            isHeaderHovered = true
            updateHeaderVisibility()
        } else {
            super.mouseEntered(with: event)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if let area = headerTrackingArea, event.trackingArea == area {
            isHeaderHovered = false
            updateHeaderVisibility()
        } else {
            super.mouseExited(with: event)
        }
    }
}
