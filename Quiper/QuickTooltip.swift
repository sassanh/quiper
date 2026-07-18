import AppKit
import QuartzCore

struct TooltipTargetID: Equatable {
    let owner: ObjectIdentifier
    let segment: Int?

    init(owner: AnyObject, segment: Int? = nil) {
        self.owner = ObjectIdentifier(owner)
        self.segment = segment
    }
}

struct TooltipVisibilityCoordinator {
    enum State: Equatable {
        case hidden
        case visible(TooltipTargetID)
        case pendingHide(TooltipTargetID, requestID: UInt64)
    }

    enum HideRequest: Equatable {
        case none
        case existing(requestID: UInt64)
        case scheduled(requestID: UInt64)
    }

    private(set) var state: State = .hidden
    private var nextRequestID: UInt64 = 0

    mutating func show(_ target: TooltipTargetID) {
        state = .visible(target)
    }

    mutating func requestHide(for owner: ObjectIdentifier) -> HideRequest {
        switch state {
        case .hidden:
            return .none
        case .visible(let target):
            guard target.owner == owner else { return .none }
            nextRequestID &+= 1
            state = .pendingHide(target, requestID: nextRequestID)
            return .scheduled(requestID: nextRequestID)
        case .pendingHide(let target, let requestID):
            guard target.owner == owner else { return .none }
            return .existing(requestID: requestID)
        }
    }

    mutating func completeHide(requestID: UInt64) -> Bool {
        guard case .pendingHide(_, let pendingRequestID) = state,
              pendingRequestID == requestID else { return false }
        state = .hidden
        return true
    }

    mutating func hideImmediately() {
        state = .hidden
    }

    func canUpdate(_ target: TooltipTargetID) -> Bool {
        guard case .visible(let visibleTarget) = state else { return false }
        return visibleTarget == target
    }
}

/// A high-performance, fast-appearing tooltip panel that replaces the slow system tooltips.
final class QuickTooltip: NSPanel {

    private enum Target {
        case view(owner: NSView, anchor: NSView)
        case segment(control: NSSegmentedControl, index: Int)

        var id: TooltipTargetID {
            switch self {
            case .view(let owner, _):
                return TooltipTargetID(owner: owner)
            case .segment(let control, let index):
                return TooltipTargetID(owner: control, segment: index)
            }
        }
    }
    
    static let shared = QuickTooltip()
    
    private let label: NSTextField
    private let loadingBorderView: LoadingBorderView
    private let shortcutBadge: NSView
    private let shortcutBadgeLabel: NSTextField
    private var labelTrailingConstraint: NSLayoutConstraint?
    private var shortcutBadgeWidth: CGFloat = 0

    private static let horizontalPadding: CGFloat = 8
    private static let shortcutSpacing: CGFloat = 10
    private static let shortcutHorizontalPadding: CGFloat = 7
    private static let shortcutHeight: CGFloat = 20
    
    private var currentTarget: Target?
    private var currentMargin: CGFloat = 4
    private var currentForcedWidth: CGFloat?
    private var currentForcedX: CGFloat?
    private var visibilityCoordinator = TooltipVisibilityCoordinator()
    private var hideTask: Task<Void, Never>?
    
    private init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping // Enable wrapping
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        
        // Shortcut badge — small rounded pill that appears to the right
        shortcutBadge = NSView()
        shortcutBadge.wantsLayer = true
        shortcutBadge.layer?.cornerRadius = 5
        shortcutBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        shortcutBadge.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        shortcutBadge.layer?.borderWidth = 1

        shortcutBadgeLabel = NSTextField(labelWithString: "")
        shortcutBadgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        shortcutBadgeLabel.textColor = .labelColor
        shortcutBadgeLabel.alignment = .center
        shortcutBadgeLabel.isEditable = false
        shortcutBadgeLabel.isSelectable = false
        shortcutBadgeLabel.isBezeled = false
        shortcutBadgeLabel.drawsBackground = false

        loadingBorderView = LoadingBorderView(frame: .zero)
        loadingBorderView.isHidden = true
        
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        ignoresMouseEvents = true
        alphaValue = 0
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        
        shortcutBadge.addSubview(shortcutBadgeLabel)
        visualEffect.addSubview(loadingBorderView)
        visualEffect.addSubview(label)
        visualEffect.addSubview(shortcutBadge)
        
        loadingBorderView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        shortcutBadge.translatesAutoresizingMaskIntoConstraints = false
        shortcutBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let labelTrailing = label.trailingAnchor.constraint(
            equalTo: visualEffect.trailingAnchor,
            constant: -Self.horizontalPadding
        )
        self.labelTrailingConstraint = labelTrailing
        
        NSLayoutConstraint.activate([
            loadingBorderView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            loadingBorderView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            loadingBorderView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            loadingBorderView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            
            label.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.horizontalPadding),
            labelTrailing,

            shortcutBadge.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            shortcutBadge.trailingAnchor.constraint(
                equalTo: visualEffect.trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            shortcutBadge.heightAnchor.constraint(equalToConstant: Self.shortcutHeight),

            shortcutBadgeLabel.leadingAnchor.constraint(
                equalTo: shortcutBadge.leadingAnchor,
                constant: Self.shortcutHorizontalPadding
            ),
            shortcutBadgeLabel.trailingAnchor.constraint(
                equalTo: shortcutBadge.trailingAnchor,
                constant: -Self.shortcutHorizontalPadding
            ),
            shortcutBadgeLabel.centerYAnchor.constraint(equalTo: shortcutBadge.centerYAnchor)
        ])
        
        contentView = visualEffect
        shortcutBadge.isHidden = true
    }
    
    /// Show tooltip immediately
    /// - Parameters:
    ///   - string: The text to show
    ///   - view: The target view to align with
    ///   - margin: Vertical margin from the view
    ///   - forcedWidth: Optional fixed width for the tooltip
    ///   - forcedX: Optional fixed window X coordinate for the tooltip
    ///   - isLoading: Whether to show the loading spinner
    func show(_ string: String, for view: NSView, margin: CGFloat = 4, forcedWidth: CGFloat? = nil, forcedX: CGFloat? = nil, isLoading: Bool = false) {
        guard let window = view.window else { return }
        let target = Target.view(owner: view, anchor: view)

        prepareToShow(target)
        setShortcut(nil)
        let targetRect = view.convert(view.bounds, to: nil)
        performShow(
            string,
            in: window,
            targetRect: targetRect,
            margin: margin,
            forcedWidth: forcedWidth,
            forcedX: forcedX,
            isLoading: isLoading
        )
    }

    /// Show tooltip with a label and a styled shortcut badge
    /// - Parameters:
    ///   - string: The label text to show
    ///   - shortcut: The shortcut string to display in a pill badge (e.g. "⌘Y")
    ///   - view: The target view to align with
    ///   - margin: Vertical margin from the view
    func show(_ string: String, shortcut: String?, for view: NSView, margin: CGFloat = 4) {
        guard let window = view.window else { return }
        let target = Target.view(owner: view, anchor: view)

        prepareToShow(target)
        setShortcut(shortcut)
        let targetRect = view.convert(view.bounds, to: nil)
        performShow(
            string,
            in: window,
            targetRect: targetRect,
            margin: margin,
            forcedWidth: nil,
            forcedX: nil,
            isLoading: false
        )
    }

    /// Configure the shortcut badge: when nil the badge is hidden, otherwise it shows the shortcut string.
    private func setShortcut(_ shortcut: String?) {
        if let shortcut, !shortcut.isEmpty {
            let displayedShortcut = shortcut.replacingOccurrences(of: "⎋", with: "Esc")
            let attributedShortcut = NSAttributedString(
                string: displayedShortcut,
                attributes: [
                    .font: shortcutBadgeLabel.font as Any,
                    .foregroundColor: NSColor.labelColor,
                    .kern: 1
                ]
            )
            shortcutBadgeLabel.attributedStringValue = attributedShortcut
            shortcutBadgeWidth = ceil(shortcutBadgeLabel.intrinsicContentSize.width)
                + (Self.shortcutHorizontalPadding * 2)
            shortcutBadge.isHidden = false
            labelTrailingConstraint?.constant = -(
                Self.horizontalPadding + shortcutBadgeWidth + Self.shortcutSpacing
            )
        } else {
            shortcutBadge.isHidden = true
            shortcutBadgeWidth = 0
            labelTrailingConstraint?.constant = -Self.horizontalPadding
        }
        contentView?.layoutSubtreeIfNeeded()
    }
    
    /// Show tooltip specifically for a segment of an NSSegmentedControl
    func show(_ string: String, for control: NSSegmentedControl, segment: Int, margin: CGFloat = 4, forcedWidth: CGFloat? = nil, forcedX: CGFloat? = nil, isLoading: Bool = false) {
        guard let rect = rectForSegment(segment, in: control),
              let window = control.window else { return }
        let target = Target.segment(control: control, index: segment)

        prepareToShow(target)
        setShortcut(nil)
        let rectInWindow = control.convert(rect, to: nil)
        performShow(string, in: window, targetRect: rectInWindow, margin: margin, forcedWidth: forcedWidth, forcedX: forcedX, isLoading: isLoading)
    }
    
    /// Dynamic update if content changes while showing
    func updateIfVisible(with string: String, for view: NSView, isLoading: Bool = false) {
        updateIfVisible(
            with: string,
            targetID: TooltipTargetID(owner: view),
            isLoading: isLoading
        )
    }

    /// Dynamic update for a segment of an NSSegmentedControl.
    func updateIfVisible(with string: String, for control: NSSegmentedControl, segment: Int, isLoading: Bool = false) {
        updateIfVisible(
            with: string,
            targetID: TooltipTargetID(owner: control, segment: segment),
            isLoading: isLoading
        )
    }

    private func updateIfVisible(with string: String, targetID: TooltipTargetID, isLoading: Bool) {
        guard visibilityCoordinator.canUpdate(targetID) else { return }
        performUpdate(string, isLoading: isLoading)
    }
    
    private func performUpdate(_ string: String, isLoading: Bool) {
        guard alphaValue > 0 else { return }
        label.stringValue = string
        
        if isLoading {
            loadingBorderView.startAnimating()
        } else {
            loadingBorderView.stopAnimating()
        }
        
        recalculatePosition()
    }
    
    private func performShow(_ string: String, in window: NSWindow, targetRect: NSRect, margin: CGFloat, forcedWidth: CGFloat?, forcedX: CGFloat?, isLoading: Bool) {
        label.stringValue = string
        currentMargin = margin
        currentForcedWidth = forcedWidth
        currentForcedX = forcedX
        
        if isLoading {
            loadingBorderView.startAnimating()
        } else {
            loadingBorderView.stopAnimating()
        }
        
        recalculatePosition(in: window, targetRect: targetRect)
        alphaValue = 1
        orderFront(nil)
    }
    
    private func recalculatePosition(in window: NSWindow? = nil, targetRect: NSRect? = nil) {
        let activeWindow: NSWindow
        let activeRect: NSRect
        
        if let window = window, let targetRect = targetRect {
            activeWindow = window
            activeRect = targetRect
        } else {
            switch currentTarget {
            case .view(_, let anchor):
                guard let window = anchor.window else { return }
                activeWindow = window
                activeRect = anchor.convert(anchor.bounds, to: nil)
            case .segment(let control, let segment):
                guard let window = control.window,
                      let rect = rectForSegment(segment, in: control) else { return }
                activeWindow = window
                activeRect = control.convert(rect, to: nil)
            case nil:
                return
            }
        }
        
        let margin = currentMargin
        let forcedWidth = currentForcedWidth
        let forcedX = currentForcedX
        
        // Calculate size needed
        let width: CGFloat
        if let forced = forcedWidth {
            width = forced
        } else {
            // Auto-size: measure label + optional badge
            let maxLabelWidth: CGFloat = 300
            label.preferredMaxLayoutWidth = maxLabelWidth
            let labelNaturalSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxLabelWidth, height: .greatestFiniteMagnitude))

            if !shortcutBadge.isHidden {
                width = min(
                    Self.horizontalPadding + labelNaturalSize.width + Self.shortcutSpacing
                        + shortcutBadgeWidth + Self.horizontalPadding,
                    400
                )
            } else {
                width = min(Self.horizontalPadding + labelNaturalSize.width + Self.horizontalPadding, 400)
            }
        }

        let shortcutWidth = shortcutBadge.isHidden ? 0 : shortcutBadgeWidth + Self.shortcutSpacing
        let labelWidth = width - (Self.horizontalPadding * 2) - shortcutWidth
        
        // Ensure multiline wrapping respects strict width
        label.preferredMaxLayoutWidth = max(labelWidth, 40)
        
        let labelSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(labelWidth, 40), height: .greatestFiniteMagnitude))
        let contentHeight = shortcutBadge.isHidden ? labelSize.height : max(labelSize.height, Self.shortcutHeight)
        let totalHeight = contentHeight + 12 // 6 per side vertical
        let totalSize = NSSize(width: width, height: totalHeight)
        
        let windowFrame = activeWindow.frame
        let screenOrigin = windowFrame.origin
        
        let targetInScreen = NSRect(
            x: screenOrigin.x + activeRect.minX,
            y: screenOrigin.y + activeRect.minY,
            width: activeRect.width,
            height: activeRect.height
        )
        
        let xPos = forcedX != nil ? (screenOrigin.x + forcedX!) : targetInScreen.minX
        
        let tooltipFrame = NSRect(
            x: xPos,
            y: targetInScreen.minY - totalSize.height - margin,
            width: totalSize.width,
            height: totalSize.height
        )
        
        setFrame(tooltipFrame, display: true)
    }
    
    func hide(for owner: NSView) {
        let ownerID = ObjectIdentifier(owner)
        guard case .scheduled(let requestID) = visibilityCoordinator.requestHide(for: ownerID) else {
            return
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            self?.completeScheduledHide(requestID: requestID)
        }
    }
    
    /// Hide the tooltip immediately and invalidate any delayed work.
    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil
        visibilityCoordinator.hideImmediately()
        currentTarget = nil
        loadingBorderView.stopAnimating()
        alphaValue = 0
        orderOut(nil)
    }
    
    /// Show tooltip on the right of the given alignment view, matching its height
    func showOnRight(of alignmentView: NSView, text: String, for owner: NSView, width: CGFloat = 300) {
        guard let window = alignmentView.window else { return }
        let target = Target.view(owner: owner, anchor: alignmentView)

        prepareToShow(target)
        setShortcut(nil)
        label.stringValue = text
        loadingBorderView.stopAnimating()

        let rectInWindow = alignmentView.convert(alignmentView.bounds, to: nil)
        
        let containerRectInWindow: NSRect
        if let parent = alignmentView.superview {
            containerRectInWindow = parent.convert(parent.bounds, to: nil)
        } else {
            containerRectInWindow = rectInWindow
        }
        
        let windowFrame = window.frame
        let screenOrigin = windowFrame.origin
        
        let height = rectInWindow.height
        let xPos = screenOrigin.x + containerRectInWindow.maxX + 8
        let yPos = screenOrigin.y + rectInWindow.minY
        
        let tooltipFrame = NSRect(
            x: xPos,
            y: yPos,
            width: width,
            height: height
        )
        
        label.preferredMaxLayoutWidth = width - 16
        
        setFrame(tooltipFrame, display: true)
        alphaValue = 1
        orderFront(nil)
    }

    private func prepareToShow(_ target: Target) {
        hideTask?.cancel()
        hideTask = nil
        visibilityCoordinator.show(target.id)
        currentTarget = target
    }

    private func completeScheduledHide(requestID: UInt64) {
        guard visibilityCoordinator.completeHide(requestID: requestID) else { return }
        hideTask = nil
        currentTarget = nil
        loadingBorderView.stopAnimating()
        alphaValue = 0
        orderOut(nil)
    }
    
    private func rectForSegment(_ segment: Int, in control: NSSegmentedControl) -> NSRect? {
        guard segment >= 0 && segment < control.segmentCount else { return nil }
        
        let bounds = control.bounds
        if let segmentedCell = control.cell as? NSSegmentedCell {
            let selector = Selector(("rectForSegment:inFrame:"))
            if segmentedCell.responds(to: selector),
               let imp = segmentedCell.method(for: selector) {
                typealias RectForSegment = @convention(c) (AnyObject, Selector, Int, NSRect) -> NSRect
                let fn = unsafeBitCast(imp, to: RectForSegment.self)
                return fn(segmentedCell, selector, segment, bounds)
            }
        }
        
        // Manual Fallback
        let count = control.segmentCount
        var totalWidth: CGFloat = 0
        for i in 0..<count {
            totalWidth += control.width(forSegment: i)
        }
        
        let availableWidth = bounds.width
        let padding = count > 0 ? (availableWidth - totalWidth) / CGFloat(count) : 0
        
        var currentX: CGFloat = 0
        for i in 0..<segment {
            currentX += control.width(forSegment: i) + padding
        }
        
        return NSRect(
            x: currentX,
            y: 0,
            width: control.width(forSegment: segment) + padding,
            height: bounds.height
        )
    }
}
