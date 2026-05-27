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
        titleLabel?.stringValue = title
        
        let isLoading = webView.isLoading
        
        if let label = titleLabel {
            if label.isTruncated() {
                QuickTooltip.shared.updateIfVisible(with: title, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
        if let service = currentService() {
            let activeIndex = activeIndicesByURL[service.url] ?? 0
            let segIdx = segmentIndex(forSession: activeIndex)
            sessionSelector?.setToolTip(title, forSegment: segIdx)
            collapsibleSessionSelector?.setToolTip(title, forSegment: segIdx)
            
            if let selector = sessionSelector {
                QuickTooltip.shared.updateIfVisible(with: title, for: (selector, segIdx), isLoading: isLoading)
            }
            if let collapsible = collapsibleSessionSelector {
                collapsible.setToolTip(title, forSegment: segIdx)
            }
        }
        
        updateLoadingIndicator(for: webView)
    }
    
    func updateLoadingIndicator(for webView: WKWebView) {
        let isLoading = webView.isLoading
        
        if isLoading {
            loadingBorderView?.startAnimating()
        } else {
            loadingBorderView?.stopAnimating()
        }
        
        guard let serviceUrlStr = serviceURL(for: webView)?.absoluteString,
              serviceUrlStr == currentServiceURL,
              let service = services.first(where: { $0.url == serviceUrlStr }),
              let sessionIndex = (0...9).first(where: { webViewManager.getWebView(for: service, sessionIndex: $0) == webView }) else { return }
        
        let segIdx = segmentIndex(forSession: sessionIndex)
        var title = webView.title ?? ""
        
        if let labelTitle = titleLabel?.stringValue, labelTitle.isEmpty,
           let currentUrl = currentServiceURL,
           let activeIdx = activeIndicesByURL[currentUrl],
           activeIdx == sessionIndex {
            title = ""
        }
        
        if let selector = sessionSelector {
            QuickTooltip.shared.updateIfVisible(with: title, for: (selector, segIdx), isLoading: isLoading)
        }
        if let collapsible = collapsibleSessionSelector {
            collapsible.setToolTip(title, forSegment: segIdx)
        }
    }
    
    func updateTitleLabel(withFallback fallback: String) {
        titleLabel?.stringValue = fallback
        
        if let label = titleLabel {
            if label.isTruncated() {
                QuickTooltip.shared.updateIfVisible(with: fallback, for: label)
            } else {
                QuickTooltip.shared.hide(for: label)
            }
        }
        
        if let service = currentService() {
            let activeIndex = activeIndicesByURL[service.url] ?? 0
            let segIdx = segmentIndex(forSession: activeIndex)
            
            sessionSelector?.setToolTip(fallback, forSegment: segIdx)
            collapsibleSessionSelector?.setToolTip(fallback, forSegment: segIdx)
            
            if let selector = sessionSelector {
                QuickTooltip.shared.updateIfVisible(with: fallback, for: (selector, segIdx), isLoading: false)
            }
        }
        
        loadingBorderView?.stopAnimating()
    }
}
