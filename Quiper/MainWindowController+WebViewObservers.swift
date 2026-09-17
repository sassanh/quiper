import AppKit
import WebKit

extension MainWindowController {
    
    // MARK: - WebView State Observation & Observation Handlers
    
    func observeNavigationState(of webView: WKWebView) {
        canGoBackObservation = nil
        canGoForwardObservation = nil
        isLoadingNavObservation = nil
        
        updateNavigationButtons(for: webView)
        
        canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateNavigationButtons(for: webView)
            }
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateNavigationButtons(for: webView)
            }
        }
        isLoadingNavObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.refreshStopButton?.isLoadingState = webView.isLoading
            }
        }
    }
    
    func updateNavigationButtons(for webView: WKWebView) {
        let showBack = webView.canGoBack
        let showForward = webView.canGoForward
        
        let wasHidden = navigationButtonGroup.isHidden
        
        navigationButtonGroup.update(showBack: showBack, showForward: showForward)
        refreshStopButton.isLoadingState = webView.isLoading
        
        let nowHidden = navigationButtonGroup.isHidden
        if wasHidden != nowHidden || !nowHidden {
            layoutSelectors()
        }
    }
    
    func updateTitleLabel(from webView: WKWebView) {
        let title = webView.title ?? ""
        setTitleLabelText(title)
        
        let isLoading = webView.isLoading
        
        if let label = titleLabel {
            if label.isTruncated() {
                QuickTooltip.shared.updateIfVisible(with: title, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
        if let service = currentService() {
            let activeIndex = activeIndicesByID[service.id] ?? 0
            updateSessionTooltip(
                for: service,
                sessionIndex: activeIndex,
                preferredTitle: title,
                isLoading: isLoading
            )
        }
        
        updateLoadingIndicator(for: webView)
    }
    
    func updateLoadingIndicator(for webView: WKWebView) {
        let isLoading = webView.isLoading
        let isTopBarHidden = Settings.shared.topBarVisibility == .hidden
        
        if isLoading && !isTopBarHidden {
            loadingBorderView?.startAnimating()
        } else {
            loadingBorderView?.stopAnimating()
        }
        windowOutlineView?.setLoading(isLoading && isTopBarHidden)
        
        guard let service = webViewManager.service(for: webView),
              currentService()?.id == service.id,
              let sessionIndex = (0...9).first(where: { webViewManager.getWebView(for: service, sessionIndex: $0) == webView }) else { return }
        
        let preferredTitle: String?
        if let labelTitle = titleLabel?.stringValue, labelTitle.isEmpty,
           let activeIdx = activeIndicesByID[service.id],
           activeIdx == sessionIndex {
            preferredTitle = ""
        } else {
            preferredTitle = webView.title
        }

        updateSessionTooltip(
            for: service,
            sessionIndex: sessionIndex,
            preferredTitle: preferredTitle,
            isLoading: isLoading
        )
    }
    
    func updateTitleLabel(withFallback fallback: String) {
        setTitleLabelText(fallback)
        
        if let label = titleLabel {
            if label.isTruncated() {
                QuickTooltip.shared.updateIfVisible(with: fallback, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
        if let service = currentService() {
            let activeIndex = activeIndicesByID[service.id] ?? 0
            updateSessionTooltip(
                for: service,
                sessionIndex: activeIndex,
                isLoading: false
            )
        }
        
        loadingBorderView?.stopAnimating()
        windowOutlineView?.setLoading(false)
    }

    /// Whether the active tab is temporary. Single read point for every
    /// ephemeral-chrome refresh so the title, badge, and outline agree.
    func isActiveTabTemporary() -> Bool {
        guard let service = currentService(), webViewManager != nil else { return false }
        return webViewManager.isTemporaryTab(
            serviceID: service.id,
            sessionIndex: activeIndicesByID[service.id] ?? 0
        )
    }

    /// Sets the topbar title, refreshing all ephemeral chrome: a badge hugging
    /// the title text and a dashed window outline. The title text itself lays
    /// out exactly as plain titles do.
    private func setTitleLabelText(_ raw: String) {
        titleLabel?.stringValue = raw
        let isTemporary = isActiveTabTemporary()
        windowOutlineView?.setEphemeral(isTemporary)
        positionEphemeralBadge()
    }

    /// Pins the badge just left of the rendered (centered) title text instead
    /// of the title area's edge, so it sticks to the title. Hides when the
    /// title is empty, truncated, or the area is crowded.
    func positionEphemeralBadge() {
        guard let badge = ephemeralBadgeView, let title = titleLabel, !title.isHidden else {
            ephemeralBadgeView?.isHidden = true
            return
        }
        guard isActiveTabTemporary() else {
            badge.isHidden = true
            return
        }
        let raw = title.stringValue
        guard !raw.isEmpty else {
            badge.isHidden = true
            return
        }
        let font = title.font ?? .systemFont(ofSize: 12, weight: .medium)
        let textWidth = (raw as NSString).size(withAttributes: [.font: font]).width
        let badgeSize: CGFloat = 13
        let gap: CGFloat = 5
        let textX = title.frame.minX + max(0, (title.frame.width - textWidth) / 2)
        let badgeX = textX - gap - badgeSize
        guard badgeX >= title.frame.minX else {
            badge.isHidden = true
            return
        }
        badge.frame = NSRect(
            x: badgeX,
            y: title.frame.midY - badgeSize / 2,
            width: badgeSize,
            height: badgeSize
        )
        badge.isHidden = false
    }
}
