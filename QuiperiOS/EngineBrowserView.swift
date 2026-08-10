import Combine
import SwiftUI
import UIKit

struct EngineBrowserView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingEnginePicker = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isScrollCollapsed = false
    @State private var isFindBarVisible = false
    @State private var displayedFindStatus: String?
    @State private var toolbarExtent: CGFloat = 0
    @FocusState private var isFindFieldFocused: Bool

    @State private var isRingVisible = false
    @State private var ringItems: [RingDisplayItem] = []
    @State private var ringHighlightedTab: TabIdentifier?
    @State private var ringCardFrames: [TabIdentifier: CGRect] = [:]
    @State private var ringPreviews: [TabIdentifier: UIImage] = [:]
    @State private var ringSelection: RingSelectionState?
    @State private var ringSelectionProgress: CGFloat = 0
    @State private var isRingSelectionAnimating = false
    @State private var isRingPresentationPending = false
    @State private var isRingQuickEndPending = false
    @State private var ringMountedTab: TabIdentifier?
    @State private var ringScrollOffset: CGFloat = 0
    @State private var ringMaxScrollOffset: CGFloat = 0
    @State private var ringScrollVelocityTarget: CGFloat = 0
    @State private var ringAutoScrollTimer: Timer?
    @State private var ringScrollDwellTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: toolbarAlignment) {
                webContent(
                    viewportLayout: browserViewportLayout(
                        safeAreaInsets: geo.safeAreaInsets
                    )
                )
                    .background(Color.black)
                    .opacity(selectionDimOpacity)
                    .ignoresSafeArea(.container)
                if !isMinimized {
                    if isFindBarVisible {
                        findBar
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: toolbarAnchor)))
                            .reportsToolbarExtent()
                            .zIndex(ringSelection != nil ? 40 : 0)
                    } else {
                        toolbarControls(landscape: landscape)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: toolbarAnchor)))
                            .reportsToolbarExtent()
                            .zIndex(ringSelection != nil ? 40 : 0)
                    }
                }
                if isMinimized {
                    island
                        .padding(toolbarEdge, islandEdgePadding(bottomInset: geo.safeAreaInsets.bottom))
                        .transition(.scale(scale: 0.6, anchor: toolbarAnchor).combined(with: .opacity))
                        .reportsToolbarExtent()
                        .zIndex(ringSelection != nil ? 40 : 0)
                }
                if isRingVisible {
                    ringOverlay
                        .zIndex(20)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                if let selection = ringSelection {
                    ringSelectionOverlay(selection)
                        .zIndex(30)
                }
                if UITestSupport.isEnabled {
                    uiTestControls
                        .zIndex(100)
                }
            }
            .onPreferenceChange(ToolbarExtentPreferenceKey.self) { extent in
                toolbarExtent = extent
            }
        }
        .ignoresSafeArea(isFindBarVisible ? [] : .keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard !environment.isRingOverlayActive else {
                dismissKeyboard()
                return
            }
            let height = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            withAnimation(islandAnimation) {
                isKeyboardVisible = true
                keyboardHeight = height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(islandAnimation) {
                isKeyboardVisible = false
                keyboardHeight = 0
            }
        }
        .onReceive(activeSession?.$isBarCollapsed.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { collapsed in
            withAnimation(islandAnimation) {
                isScrollCollapsed = collapsed
            }
        }
        .onReceive(activeSession?.$findStatusText.eraseToAnyPublisher() ?? Just<String?>(nil).eraseToAnyPublisher()) { status in
            displayedFindStatus = status
        }
        .onChange(of: activeSession?.id) {
            isScrollCollapsed = false
            dismissRing()
            if isFindBarVisible {
                closeFindBar()
            }
            wireRingGestureCallbacks()
        }
        .onChange(of: environment.thumbnailsRevision) {
            if isRingVisible {
                loadRingPreviews()
            }
        }
        .onChange(of: environment.shouldDismissSensitiveUI) { _, shouldDismiss in
            guard shouldDismiss else { return }
            showingSettings = false
            showingHistory = false
            showingEnginePicker = false
            if isFindBarVisible {
                closeFindBar()
            }
            dismissRing()
        }
        .onAppear {
            wireRingGestureCallbacks()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in environment.registerUserActivity() }
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(environment)
        }
        .sheet(isPresented: $showingHistory) {
            PromptHistoryView()
                .environmentObject(environment)
        }
        .sheet(isPresented: $showingEnginePicker) {
            EnginePickerView()
                .environmentObject(environment)
                .presentationDetents([.medium, .large])
        }
    }

    private var isMinimized: Bool {
        guard !isFindBarVisible else { return false }
        return isScrollCollapsed || (environment.dragAreaPosition == .bottom && isKeyboardVisible)
    }

    private var toolbarAlignment: Alignment {
        environment.dragAreaPosition == .top ? .top : .bottom
    }

    private var toolbarEdge: Edge.Set {
        environment.dragAreaPosition == .top ? .top : .bottom
    }

    private var toolbarAnchor: UnitPoint {
        environment.dragAreaPosition == .top ? .top : .bottom
    }

    private func browserViewportLayout(safeAreaInsets: EdgeInsets) -> BrowserViewportLayout {
        switch environment.dragAreaPosition {
        case .top:
            return BrowserViewportLayout(
                obscuredContentInsets: UIEdgeInsets(
                    top: safeAreaInsets.top + toolbarExtent,
                    left: 0,
                    bottom: safeAreaInsets.bottom,
                    right: 0
                )
            )
        case .bottom:
            return BrowserViewportLayout(
                obscuredContentInsets: UIEdgeInsets(
                    top: safeAreaInsets.top,
                    left: 0,
                    bottom: safeAreaInsets.bottom + toolbarExtent,
                    right: 0
                )
            )
        }
    }

    private func islandEdgePadding(bottomInset: CGFloat) -> CGFloat {
        guard environment.dragAreaPosition == .bottom else { return 12 }
        return isKeyboardVisible ? max(0, keyboardHeight - bottomInset) : 12
    }

    private var islandTapAction: () -> Void {
        {
            if isKeyboardVisible {
                dismissKeyboard()
            }
            activeSession?.expandBar()
        }
    }

    private var activeServiceID: UUID {
        environment.activeService?.id ?? environment.services.first?.id ?? UUID()
    }

    private var activeSessionIndex: Int {
        environment.activeSessionIndex(for: activeServiceID)
    }

    private var activeSession: WebViewSession? {
        guard let service = environment.activeService else { return nil }
        guard !environment.isServiceLocked(service.id) else { return nil }
        if !environment.autoCreateSessionOnEmptyEngineActivation,
           environment.hasNoSessions(for: service.id) {
            return nil
        }
        return environment.webViewSession(
            for: service.id,
            sessionIndex: activeSessionIndex,
            initialURL: environment.activeSessionURL(for: service.id)
        )
    }

    /// True only when a real session is active; when the engine is empty (no
    /// session auto-created) no slot should appear selected in the selector.
    private var hasActiveSession: Bool {
        activeSession != nil
    }

    private var islandAnimation: Animation {
        .spring(response: 0.45, dampingFraction: 0.68)
    }

    /// Fades the current web view itself toward black while the ring selection
    /// zooms in, so the page we are transitioning from reliably darkens (a
    /// SwiftUI color overlay alone can fail to dim a WKWebView's composited
    /// layer).
    private var selectionDimOpacity: CGFloat {
        guard isRingSelectionAnimating, ringSelection != nil else { return 1 }
        return 1 - 0.9 * min(1, ringSelectionProgress * 3)
    }

    @ViewBuilder
    private var island: some View {
        if let session = activeSession {
            Island(
                session: session,
                service: environment.activeService,
                sessionIndex: activeSessionIndex,
                tapAction: islandTapAction
            )
        }
    }

    private func dismissKeyboard() {
        isFindFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openFindBar() {
        isFindBarVisible = true
        activeSession?.expandBar()
        isFindFieldFocused = true
        Task { @MainActor in
            await Task.yield()
            guard isFindBarVisible, isFindFieldFocused else { return }
            UIApplication.shared.sendAction(
                #selector(UIResponderStandardEditActions.selectAll(_:)),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    private func closeFindBar() {
        isFindBarVisible = false
        isFindFieldFocused = false
        activeSession?.resetFind()
        dismissKeyboard()
    }

    private func clearFindQuery() {
        activeSession?.setFindQuery("")
    }

    // MARK: - Double-tap navigation ring

    private func wireRingGestureCallbacks() {
        guard let session = activeSession else { return }
        session.onRingSecondTapDown = { [self] location in
            self.ringSecondTapDown(at: location)
        }
        session.onRingHoldBegan = { [self] in
            self.ringHoldBegan()
        }
        session.onRingHoldUpdate = { [self] location in
            self.ringHoldUpdate(at: location)
        }
        session.onRingQuickEnd = { [self] location in
            self.ringQuickEnd(at: location)
        }
        session.onRingHoldEnd = { [self] location in
            self.ringHoldEnd(at: location)
        }
        session.onRingCancel = { [self] in
            self.cancelRing()
        }
    }

    private func ringSecondTapDown(at location: CGPoint) {
        dismissKeyboard()
        let items = environment.navigationRingItems()
        guard items.count > 1 else { return }
        guard environment.tabNavigationRingSize > 2 else { return }
        environment.setRingOverlayActive(true)
        isRingPresentationPending = true
        activeSession?.suspendWebViewInteraction()
        Task { @MainActor [self] in
            let fresh = await activeSession?.captureFreshSnapshot()
            guard isRingPresentationPending else { return }
            presentRing(items: items, highlighted: items[1], currentThumbnail: fresh)
            if isRingQuickEndPending {
                isRingQuickEndPending = false
                ringSelect(highlighted: ringHighlightedTab)
            }
        }
    }

    /// Ring size 2: a quick double-tap switches straight to the MRU tab, no HUD.
    private func ringSwitchToNext() {
        guard let next = environment.navigationRingItems().dropFirst().first else { return }
        environment.setActiveSession(for: next.serviceID, index: next.sessionIndex)
    }

    private func ringHoldBegan() {
        guard !isRingVisible, !isRingPresentationPending else { return }
        dismissKeyboard()
        let items = environment.navigationRingItems()
        guard items.count > 1 else { return }
        environment.setRingOverlayActive(true)
        presentRing(items: items, highlighted: items[1])
        activeSession?.suspendWebViewInteraction()
    }

    private func ringHoldUpdate(at location: CGPoint) {
        guard isRingVisible else { return }
        guard let webView = activeSession?.webView else { return }
        let point = webView.convert(location, to: nil)
        if let item = ringItem(atGlobal: point) {
            ringHighlightedTab = item.tab
        }
        handleRingAutoScroll(at: point)
    }

    private func ringQuickEnd(at location: CGPoint) {
        activeSession?.resumeWebViewInteraction()
        guard !isRingPresentationPending else {
            isRingQuickEndPending = true
            return
        }
        if !isRingVisible {
            ringSwitchToNext()
            return
        }
        ringSelect(highlighted: ringHighlightedTab)
    }

    private func ringHoldEnd(at location: CGPoint) {
        guard !isRingPresentationPending else {
            isRingPresentationPending = false
            isRingQuickEndPending = false
            activeSession?.resumeWebViewInteraction()
            environment.setRingOverlayActive(false)
            return
        }
        guard isRingVisible else {
            activeSession?.resumeWebViewInteraction()
            return
        }
        activeSession?.resumeWebViewInteraction()
        if let tab = ringItem(at: location)?.tab {
            ringSelect(tab: tab)
        } else {
            dismissRing()
        }
    }

    private func cancelRing() {
        activeSession?.resumeWebViewInteraction()
        dismissRing()
    }

    // MARK: - Ring edge auto-scroll

    private static let ringEdgeZone: CGFloat = 80
    private static let ringMaxScrollSpeed: CGFloat = 700
    private static let ringScrollDwell: UInt64 = 300_000_000

    private func ringAutoScrollVelocity(at point: CGPoint) -> CGFloat {
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.height ?? 0
        guard screenHeight > 0 else { return 0 }
        let topDistance = point.y
        let bottomDistance = screenHeight - point.y
        if topDistance < Self.ringEdgeZone {
            return Self.ringMaxScrollSpeed * (1 - topDistance / Self.ringEdgeZone)
        }
        if bottomDistance < Self.ringEdgeZone {
            return -Self.ringMaxScrollSpeed * (1 - bottomDistance / Self.ringEdgeZone)
        }
        return 0
    }

    private func handleRingAutoScroll(at point: CGPoint) {
        let velocity = ringAutoScrollVelocity(at: point)
        guard velocity != 0 else {
            stopRingAutoScroll()
            return
        }
        ringScrollVelocityTarget = velocity
        guard ringAutoScrollTimer == nil else { return }
        guard ringScrollDwellTask == nil else { return }
        ringScrollDwellTask = Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: Self.ringScrollDwell)
            self.ringScrollDwellTask = nil
            guard self.ringScrollVelocityTarget != 0, self.ringAutoScrollTimer == nil else { return }
            self.startRingAutoScrollTimer()
        }
    }

    private func startRingAutoScrollTimer() {
        guard ringAutoScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [self] _ in
            self.stepRingAutoScroll()
        }
        RunLoop.main.add(timer, forMode: .common)
        ringAutoScrollTimer = timer
    }

    private func stepRingAutoScroll() {
        let maxOffset = ringMaxScrollOffset
        guard maxOffset > 0 else {
            stopRingAutoScroll()
            return
        }
        ringScrollOffset += ringScrollVelocityTarget * (1.0 / 60.0)
        ringScrollOffset = min(0, max(-maxOffset, ringScrollOffset))
    }

    private func stopRingAutoScroll() {
        ringScrollDwellTask?.cancel()
        ringScrollDwellTask = nil
        ringAutoScrollTimer?.invalidate()
        ringAutoScrollTimer = nil
        ringScrollVelocityTarget = 0
    }

    private func ringSelect(highlighted tab: TabIdentifier?) {
        if let tab {
            ringSelect(tab: tab)
        } else {
            dismissRing()
        }
    }

    private func ringSelect(tab: TabIdentifier) {
        stopRingAutoScroll()
        dismissKeyboard()
        guard let service = environment.services.first(where: { $0.id == tab.serviceID }) else {
            dismissRing()
            return
        }
        let fromFrame: CGRect
        if let frame = ringCardFrames[tab] {
            fromFrame = frame
        } else if let webView = activeSession?.webView {
            fromFrame = webView.convert(webView.bounds, to: nil)
        } else {
            fromFrame = .zero
        }
        ringSelection = RingSelectionState(
            tab: tab,
            service: service,
            title: environment.ringTitle(for: tab),
            fromFrame: fromFrame,
            preview: ringPreviews[tab]
        )
        isRingSelectionAnimating = true
        isRingVisible = false
        refreshSelectionThumbnailIfNeeded(tab: tab)
        mountTargetForLoading(tab: tab)
        withAnimation(
            .spring(response: 0.375, dampingFraction: 0.8),
            completionCriteria: .logicallyComplete
        ) {
            ringSelectionProgress = 1
        } completion: {
            guard self.ringSelection?.tab == tab else { return }
            self.unmountMountedTarget()
            self.environment.setActiveSession(for: tab.serviceID, index: tab.sessionIndex)
            withAnimation(.easeOut(duration: 0.25)) {
                self.ringSelection = nil
                self.ringSelectionProgress = 0
            }
            self.isRingSelectionAnimating = false
            self.environment.setRingOverlayActive(false)
        }
    }

    private func ringItem(at location: CGPoint) -> RingDisplayItem? {
        guard let webView = activeSession?.webView else { return nil }
        return ringItem(atGlobal: webView.convert(location, to: nil))
    }

    private func ringItem(atGlobal point: CGPoint) -> RingDisplayItem? {
        for item in ringItems {
            guard let frame = ringCardFrames[item.tab] else { continue }
            if frame.contains(point) {
                return item
            }
        }
        return nil
    }

    private func presentRing(items: [TabIdentifier], highlighted: TabIdentifier?, currentThumbnail: UIImage? = nil) {
        ringItems = items.compactMap { tab in
            guard let service = environment.services.first(where: { $0.id == tab.serviceID }) else { return nil }
            return RingDisplayItem(tab: tab, service: service, title: environment.ringTitle(for: tab))
        }
        ringHighlightedTab = highlighted
        ringCardFrames = [:]
        ringPreviews = [:]
        ringSelection = nil
        ringSelectionProgress = 0
        isRingSelectionAnimating = false
        isRingPresentationPending = false
        unmountMountedTarget()
        ringScrollOffset = 0
        ringMaxScrollOffset = 0
        isRingVisible = true
        loadRingPreviews()
        if let currentThumbnail, let tab = currentActiveTab {
            ringPreviews[tab] = currentThumbnail
        }
    }

    /// Fills ring previews from the stored thumbnails, which are captured when
    /// each session is left and refreshed on page load. The current session's
    /// fresh snapshot is seeded by the deferred ring presentation.
    private func loadRingPreviews() {
        for item in ringItems {
            if let image = environment.ringThumbnail(for: item.tab) {
                ringPreviews[item.tab] = image
            }
        }
    }

    private func dismissRing() {
        stopRingAutoScroll()
        activeSession?.resumeWebViewInteraction()
        isRingVisible = false
        isRingPresentationPending = false
        isRingQuickEndPending = false
        ringHighlightedTab = nil
        ringCardFrames = [:]
        ringPreviews = [:]
        ringScrollOffset = 0
        ringMaxScrollOffset = 0
        if !isRingSelectionAnimating {
            ringSelection = nil
            ringSelectionProgress = 0
            unmountMountedTarget()
            environment.setRingOverlayActive(false)
        }
    }

    private var currentActiveTab: TabIdentifier? {
        guard let service = environment.activeService else { return nil }
        return TabIdentifier(serviceID: service.id, sessionIndex: environment.activeSessionIndex(for: service.id))
    }

    /// The tab the toolbar chrome presents as active while a ring selection zooms
    /// in, so the engine and session buttons reflect the target immediately at
    /// selection time instead of only after the zoom animation completes.
    private var chromeActiveTab: TabIdentifier? {
        ringSelection?.tab ?? currentActiveTab
    }

    /// When the selected tab is the live page itself, capture it fresh so the
    /// animation morphs the exact on-screen state instead of a stored thumbnail.
    private func refreshSelectionThumbnailIfNeeded(tab: TabIdentifier) {
        guard tab == currentActiveTab, let session = activeSession else { return }
        session.captureSnapshot { [self] image in
            if let image {
                self.ringPreviews[tab] = image
            }
        }
    }

    /// Attaches the target session's web view (hidden, behind the current one)
    /// as soon as a selection starts, so it re-attaches and resumes loading while
    /// the thumbnail animation plays, instead of starting cold at reveal time.
    private func mountTargetForLoading(tab: TabIdentifier) {
        guard tab != currentActiveTab else { return }
        unmountMountedTarget()
        let target = environment.webViewSession(
            for: tab.serviceID,
            sessionIndex: tab.sessionIndex,
            initialURL: environment.sessionURL(for: tab.serviceID, slot: tab.sessionIndex)
        )
        target.loadIfNeeded()
        guard let host = activeSession?.webView.superview,
              target.webView.superview !== host else { return }
        target.webView.isHidden = true
        host.insertSubview(target.webView, at: 0)
        ringMountedTab = tab
    }

    private func unmountMountedTarget() {
        defer { ringMountedTab = nil }
        guard let tab = ringMountedTab,
              let target = environment.existingSession(for: tab.serviceID, sessionIndex: tab.sessionIndex),
              target.webView.superview != nil else { return }
        target.webView.removeFromSuperview()
        target.webView.isHidden = false
    }

    private static let ringTopInset: CGFloat = 40
    private static let ringRowSpacing: CGFloat = 12
    private static let ringMinCardWidth: CGFloat = 150
    private static let ringVerticalPadding: CGFloat = 24

    private var ringOverlay: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width - 40
            let columns = Self.ringGridColumns(containerWidth: containerWidth)
            let rows = max(1, (ringItems.count + columns.count - 1) / columns.count)
            let gridViewportHeight = geo.size.height - Self.ringTopInset
            let rowsVisible: CGFloat = ringItems.count <= 4 ? 2 : 2.3
            let cardHeight = max(80, (gridViewportHeight - Self.ringVerticalPadding * 2 - Self.ringRowSpacing) / rowsVisible)
            let contentHeight = CGFloat(rows) * cardHeight
                + CGFloat(max(0, rows - 1)) * Self.ringRowSpacing
                + Self.ringVerticalPadding * 2
            let maxOffset = max(0, contentHeight - gridViewportHeight)

            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: Self.ringTopInset)
                    ZStack(alignment: .top) {
                        LazyVGrid(columns: columns, spacing: Self.ringRowSpacing) {
                            ForEach(ringItems) { item in
                                ringCard(item, targetHeight: cardHeight)
                            }
                        }
                        .padding(.vertical, Self.ringVerticalPadding)
                        .offset(y: ringScrollOffset)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onPreferenceChange(RingFrameKey.self) { frames in
                ringCardFrames = frames
            }
            .onAppear {
                ringMaxScrollOffset = maxOffset
            }
            .onChange(of: geo.size.height) {
                ringMaxScrollOffset = maxOffset
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation-ring-overlay")
        .accessibilityLabel("Navigation ring")
    }

    private static func ringGridColumns(containerWidth: CGFloat) -> [GridItem] {
        let count = max(1, Int((containerWidth + Self.ringRowSpacing) / (Self.ringMinCardWidth + Self.ringRowSpacing)))
        return Array(repeating: GridItem(.flexible(), spacing: Self.ringRowSpacing), count: count)
    }

    private func ringCard(_ item: RingDisplayItem, targetHeight: CGFloat) -> some View {
        let isHighlighted = item.tab == ringHighlightedTab
        let preview = ringPreviews[item.tab]
        return ZStack(alignment: .bottom) {
            if let preview {
                GeometryReader { proxy in
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .systemBackground))
            }
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                HStack {
                    EngineIconView(service: item.service, size: 16)
                    Text(SessionSlots.label(for: item.tab.sessionIndex))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isHighlighted ? .white : .white.opacity(0.9))
                    Spacer()
                }
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? .white : .white.opacity(0.85))
                    .lineLimit(2)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: targetHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(isHighlighted ? 1 : 0.25), lineWidth: isHighlighted ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .background(
            GeometryReader { innerProxy in
                Color.clear.preference(
                    key: RingFrameKey.self,
                    value: [item.tab: innerProxy.frame(in: .global)]
                )
            }
        )
        .accessibilityIdentifier("ring-session-\(item.tab.sessionIndex)")
        .accessibilityLabel("Ring \(SessionSlots.tooltipTitle(for: item.tab.sessionIndex))")
    }

    private static func ringScale(from rect: CGRect, to size: CGSize) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 1 }
        return min(size.width / rect.width, size.height / rect.height)
    }

    private func ringSelectionOverlay(_ selection: RingSelectionState) -> some View {
        GeometryReader { geo in
            let localOrigin = geo.frame(in: .global).origin
            let size = geo.size
            let fromLocal = CGRect(
                x: selection.fromFrame.minX - localOrigin.x,
                y: selection.fromFrame.minY - localOrigin.y,
                width: selection.fromFrame.width,
                height: selection.fromFrame.height
            )
            let scale = Self.ringScale(from: fromLocal, to: size)
            let progress = ringSelectionProgress
            let interpolated = CGRect(
                x: fromLocal.midX + (size.width / 2 - fromLocal.midX) * progress - (fromLocal.width / 2) * (1 + (scale - 1) * progress),
                y: fromLocal.midY + (size.height / 2 - fromLocal.midY) * progress - (fromLocal.height / 2) * (1 + (scale - 1) * progress),
                width: fromLocal.width * (1 + (scale - 1) * progress),
                height: fromLocal.height * (1 + (scale - 1) * progress)
            )
            ZStack {
                Color.black.opacity(0.75 * min(1, progress * 3))
                ZStack(alignment: .bottom) {
                    if let preview = ringPreviews[selection.tab] ?? selection.preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: interpolated.width, height: interpolated.height)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .systemBackground))
                    }
                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        HStack {
                            EngineIconView(service: selection.service, size: 16)
                            Text(SessionSlots.label(for: selection.tab.sessionIndex))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        Text(selection.title)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(10)
                }
                .frame(width: interpolated.width, height: interpolated.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .position(x: interpolated.midX, y: interpolated.midY)
            }
            .opacity(progress < 0.05 ? 0 : 1)
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    private func toolbarControls(landscape: Bool) -> some View {
        VStack(spacing: 10) {
            if landscape {
                landscapeControls
            } else {
                portraitControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassContainer()
    }

    private var portraitControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                engineSelectorButton
                actionsMenu
                Spacer(minLength: 4)
                navigationControls
            }
            sessionSelector(flexible: false)
        }
    }

    private var landscapeControls: some View {
        HStack(spacing: 10) {
            engineSelectorButton
            actionsMenu
            sessionSelector(flexible: true)
            navigationControls
        }
        .frame(maxWidth: .infinity)
    }

    private var findBar: some View {
        HStack(spacing: 10) {
            findField
            if let status = displayedFindStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("find-status")
            }
            findIconButton(systemImage: "chevron.up", label: "Previous match") {
                activeSession?.stepFind(forward: false)
            }
            findIconButton(systemImage: "chevron.down", label: "Next match") {
                activeSession?.stepFind(forward: true)
            }
            findIconButton(systemImage: "xmark", label: "Close find") {
                closeFindBar()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassContainer()
    }

    private var findField: some View {
        HStack(spacing: 2) {
            TextField("Find in page", text: findQueryBinding)
                .focused($isFindFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.leading, 10)
                .accessibilityIdentifier("find-field")
            if !(activeSession?.findQuery.isEmpty ?? true) {
                Button {
                    clearFindQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Clear find text")
            } else {
                Spacer().frame(width: 6)
            }
        }
        .frame(height: 34)
        .glassIsland(in: Capsule(), interactive: true)
    }

    private var findQueryBinding: Binding<String> {
        Binding(
            get: { activeSession?.findQuery ?? "" },
            set: { activeSession?.setFindQuery($0) }
        )
    }

    private func findIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34)
                .glassIsland(in: Circle(), interactive: true)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var navigationControls: some View {
        if let session = activeSession {
            NavigationControls(session: session)
        } else {
            EmptyView()
        }
    }

    private var actionsMenu: some View {
        Menu {
            if environment.customActions.isEmpty {
                Text("No Actions")
            } else {
                ForEach(environment.customActions) { action in
                    Button {
                        environment.runAction(action, for: activeServiceID)
                    } label: {
                        Label(action.name.isEmpty ? "Action" : action.name, systemImage: "bolt.fill")
                    }
                }
            }
            Divider()
            if let service = environment.activeService, service.isEncrypted {
                if environment.isServiceLocked(service.id) {
                    Button {
                        Task { await environment.unlockService(service.id) }
                    } label: {
                        Label("Unlock Engine", systemImage: "lock.open")
                    }
                } else {
                    Button {
                        environment.lockService(service.id)
                    } label: {
                        Label("Lock Engine", systemImage: "lock")
                    }
                }
                Divider()
            }
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                showingHistory = true
            } label: {
                Label("Prompt History", systemImage: "clock.arrow.circlepath")
            }
            Button {
                openFindBar()
            } label: {
                Label("Find in Page", systemImage: "magnifyingglass")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt")
                    .font(.system(size: 15))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .accessibilityLabel("Actions")
        .accessibilityIdentifier("actions-menu")
    }

    private var engineSelectorButton: some View {
        let service = chromeActiveTab.flatMap { tab in
            environment.services.first { $0.id == tab.serviceID }
        }
        return Button {
            showingEnginePicker = true
        } label: {
            HStack(spacing: 8) {
                EngineIconView(service: service, size: 18)
                Text(service?.name ?? "Select Engine")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let service, service.isEncrypted {
                    Image(systemName: environment.isServiceLocked(service.id) ? "lock.fill" : "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Select engine")
        .accessibilityIdentifier("engine-selector-button")
    }

    private func sessionSelector(flexible: Bool) -> some View {
        let serviceID = chromeActiveTab?.serviceID ?? activeServiceID
        let activeSlot = chromeActiveTab?.sessionIndex ?? activeSessionIndex
        return HStack(spacing: 6) {
            ForEach(SessionSlots.range, id: \.self) { slot in
                let isActive = hasActiveSession && slot == activeSlot
                let isLoaded = environment.isSessionLoaded(for: serviceID, slot: slot)
                Button {
                    environment.setActiveSession(for: serviceID, index: slot)
                } label: {
                    Text(SessionSlots.label(for: slot))
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .frame(
                            minWidth: flexible ? 24 : 30,
                            idealWidth: 30,
                            maxWidth: flexible ? .infinity : 30
                        )
                        .frame(height: 30)
                        .foregroundStyle(segmentForeground(isActive: isActive, isLoaded: isLoaded))
                        .background(
                            isActive ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Close Session", role: .destructive) {
                        environment.closeSession(for: activeServiceID, at: slot)
                    }
                }
                .accessibilityLabel(SessionSlots.tooltipTitle(for: slot))
                .accessibilityIdentifier("session-\(slot)")
                .accessibilityValue(isActive ? "active" : isLoaded ? "loaded" : "empty")
                .disabled(environment.isServiceLocked(serviceID))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .glassIsland(in: RoundedRectangle(cornerRadius: 14), interactive: true)
    }

    private func segmentForeground(isActive: Bool, isLoaded: Bool) -> Color {
        if isActive { return .white }
        if !isLoaded { return .primary.opacity(0.3) }
        return .primary
    }

    private func webContent(viewportLayout: BrowserViewportLayout) -> some View {
        ZStack {
            if let service = environment.activeService, environment.isServiceLocked(service.id) {
                lockedEngineView(service)
            } else if let session = activeSession {
                WebKitBrowserView(
                    session: session,
                    viewportLayout: viewportLayout
                )
                    .id(session.id)
            } else if environment.services.isEmpty {
                ContentUnavailableView("No Engines", systemImage: "globe", description: Text("Add an engine in Settings."))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Open Session")
                        .font(.headline)
                    Text("Start a session for \(environment.activeService?.name ?? "this engine").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("New Session") {
                        if let serviceID = environment.activeService?.id ?? environment.services.first?.id {
                            environment.setActiveSession(for: serviceID, index: 0)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityIdentifier("web-content")
    }

    private func lockedEngineView(_ service: Service) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("\(service.name) Is Locked")
                .font(.title2.bold())
            Text("Authenticate to decrypt this engine’s settings, drafts, prompt history, and tab state.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let error = environment.securityError(for: service.id) {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            Button {
                Task { await environment.unlockService(service.id) }
            } label: {
                HStack {
                    if environment.securityOperationServiceIDs.contains(service.id) {
                        ProgressView()
                    }
                    Text("Unlock Engine")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(environment.securityOperationServiceIDs.contains(service.id))
            if environment.securityError(for: service.id) != nil {
                Button("Open Settings") {
                    showingSettings = true
                }
            }
        }
        .padding(28)
    }

    private var uiTestControls: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    ringHoldBegan()
                } label: {
                    Image(systemName: "testtube.2")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open navigation ring")
                .accessibilityValue(isFindFieldFocused ? "find-focused" : "find-unfocused")
                .accessibilityIdentifier("ui-test-open-ring")
            }
            Spacer()
        }
        .padding(8)
    }
}

private struct RingDisplayItem: Identifiable {
    let tab: TabIdentifier
    let service: Service?
    let title: String
    var id: String { "\(tab.serviceID.uuidString)-\(tab.sessionIndex)" }
}

private struct RingSelectionState {
    let tab: TabIdentifier
    let service: Service?
    let title: String
    let fromFrame: CGRect
    let preview: UIImage?
}

private struct RingFrameKey: PreferenceKey {
    static var defaultValue: [TabIdentifier: CGRect] = [:]
    static func reduce(value: inout [TabIdentifier: CGRect], nextValue: () -> [TabIdentifier: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ToolbarExtentPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportsToolbarExtent() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ToolbarExtentPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

struct EnginePickerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(environment.services) { service in
                    Button {
                        environment.setActiveService(service.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            EngineIconView(service: service, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .foregroundStyle(Color.primary)
                                if let url = URL(string: service.url), let host = url.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if service.isEncrypted {
                                Image(systemName: environment.isServiceLocked(service.id) ? "lock.fill" : "lock.open.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if service.id == environment.activeService?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct NavigationControls: View {
    @ObservedObject var session: WebViewSession

    var body: some View {
        HStack(spacing: 10) {
            if session.canGoBack {
                Button {
                    session.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassIsland(in: Circle(), interactive: true)
                }
                .accessibilityLabel("Back")
            }

            if session.canGoForward {
                Button {
                    session.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassIsland(in: Circle(), interactive: true)
                }
                .accessibilityLabel("Forward")
            }

            Button {
                if session.isLoading {
                    session.stopLoading()
                } else {
                    session.reload()
                }
            } label: {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 34, height: 34)
                    .glassIsland(in: Circle(), interactive: true)
            }
            .padding(4)
            .overlay {
                if session.isLoading {
                    LoadingRing(shape: Circle(), lineWidth: 3)
                }
            }
            .accessibilityLabel(session.isLoading ? "Stop" : "Reload")
        }
    }
}

private struct Island: View {
    @ObservedObject var session: WebViewSession
    let service: Service?
    let sessionIndex: Int
    let tapAction: () -> Void

    var body: some View {
        Button(action: tapAction) {
            HStack(spacing: 10) {
                Text(SessionSlots.label(for: sessionIndex))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor)
                    )
                HStack(spacing: 6) {
                    EngineIconView(service: service, size: 18)
                    Text(service?.name ?? "Select Engine")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(4)
        .overlay {
            if session.isLoading {
                LoadingRing(shape: Capsule(), lineWidth: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hide keyboard")
    }
}

private struct LoadingRing<S: Shape>: View {
    let shape: S
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation) { context in
            RingCanvas(
                shape: shape,
                lineWidth: lineWidth,
                phase: phase(at: context.date)
            )
        }
        .allowsHitTesting(false)
    }

    private func phase(at date: Date) -> CGFloat {
        let seconds = date.timeIntervalSinceReferenceDate
        let progress = seconds.truncatingRemainder(dividingBy: 1.5) / 1.5
        return CGFloat(progress)
    }
}

private struct RingCanvas<S: Shape>: View {
    let shape: S
    let lineWidth: CGFloat
    let phase: CGFloat

    var body: some View {
        Canvas { canvas, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let path = shape.path(in: rect)
            let segmentFraction: CGFloat = 0.16
            let start = phase
            let end = phase + segmentFraction
            canvas.stroke(path, with: .color(Color.accentColor.opacity(0.25)), lineWidth: lineWidth)
            if end <= 1 {
                canvas.stroke(
                    path.trim(from: start, to: end).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            } else {
                canvas.stroke(
                    path.trim(from: start, to: 1).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                canvas.stroke(
                    path.trim(from: 0, to: end - 1).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}
