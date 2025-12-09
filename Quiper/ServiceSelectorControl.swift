import AppKit

final class ServiceSelectorControl: NSSegmentedControl {
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var dragBeganHandler: ((Int) -> Void)?
    var dragChangedHandler: ((Int) -> Void)?
    var dragEndedHandler: (() -> Void)?

    private var dragSourceIndex: Int?
    private var currentDragDestination: Int?
    private var mouseDownLocation: NSPoint = .zero
    private var isDragging = false
    private let dragThreshold: CGFloat = Constants.SERVICE_REORDER_DRAG_THRESHOLD

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        mouseDownLocation = location
        dragSourceIndex = segmentIndex(at: location)
        currentDragDestination = dragSourceIndex
        if let index = dragSourceIndex {
            mouseDownSegmentHandler?(index)
        }
        trackPointer()
    }

    private func trackPointer() {
        guard let window = window else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        let timeout = Date.distantFuture.timeIntervalSinceReferenceDate
        window.trackEvents(matching: mask, timeout: timeout, mode: .eventTracking) { [weak self] event, stop in
            guard let self, let event else {
                stop.pointee = true
                return
            }
            let location = self.convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDragged:
                self.handleDrag(at: location)
            case .leftMouseUp:
                self.finishInteraction(at: location)
                stop.pointee = true
            default:
                break
            }
        }
    }

    private func handleDrag(at location: NSPoint) {
        guard let sourceIndex = dragSourceIndex else { return }
        if !isDragging {
            let dx = location.x - mouseDownLocation.x
            let dy = location.y - mouseDownLocation.y
            if hypot(dx, dy) >= dragThreshold {
                isDragging = true
                dragBeganHandler?(sourceIndex)
            }
        }

        guard isDragging else { return }

        let rects = segmentRects()
        let stickyIndex = currentDragDestination ?? sourceIndex
        guard !rects.isEmpty else { return }

        let destination = destinationIndex(at: location, rects: rects, stickyIndex: stickyIndex)
        if destination != currentDragDestination {
            currentDragDestination = destination
            dragChangedHandler?(destination)
        }
    }

    private func finishInteraction(at location: NSPoint) {
        if isDragging {
            dragEndedHandler?()
        } else if let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
        resetDragState()
    }

    private func resetDragState() {
        isDragging = false
        dragSourceIndex = nil
        currentDragDestination = nil
        mouseDownLocation = .zero
    }

    private func segmentIndex(at point: NSPoint) -> Int? {
        let count = segmentCount
        guard count > 0 else { return nil }
        guard let segmentedCell = cell as? NSSegmentedCell else {
            preconditionFailure("ServiceSelectorControl: missing segmented cell for hit testing")
        }

        var nearestIndex: Int = 0
        var nearestDistance: CGFloat = .greatestFiniteMagnitude

        let selector = Selector(("rectForSegment:inFrame:"))
        if segmentedCell.responds(to: selector),
           let imp = segmentedCell.method(for: selector) {
            typealias RectForSegment = @convention(c) (AnyObject, Selector, Int, NSRect) -> NSRect
            let fn = unsafeBitCast(imp, to: RectForSegment.self)
            for index in 0..<count {
                let rect = fn(segmentedCell, selector, index, bounds)
                if rect.contains(point) {
                    return index
                }
                let distance = abs(rect.midX - point.x)
                if distance < nearestDistance {
                    nearestDistance = distance
                    nearestIndex = index
                }
            }
        }

        let layoutRect = segmentedCell.drawingRect(forBounds: bounds)
        let clampedX = max(layoutRect.minX, min(layoutRect.maxX, point.x))

        var widths: [CGFloat] = []
        widths.reserveCapacity(count)
        for index in 0..<count {
            var w = segmentedCell.width(forSegment: index)
            if w <= 0 {
                w = max(layoutRect.width / CGFloat(count), 1)
            }
            widths.append(w)
        }

        let totalWidth = widths.reduce(0, +)
        let paddingPerSegment = (layoutRect.width - totalWidth) / CGFloat(max(count, 1))

        var leading: CGFloat = layoutRect.minX
        for (index, width) in widths.enumerated() {
            let trailing = leading + width + paddingPerSegment
            if clampedX < trailing || index == count - 1 {
                return index
            }
            leading = trailing
        }

        // Fall back to the closest segment we saw when using rectForSegment.
        return nearestIndex
    }

    private func segmentRects() -> [NSRect] {
        let count = segmentCount
        guard count > 0, let segmentedCell = cell as? NSSegmentedCell else { return [] }

        var rects: [NSRect] = []
        rects.reserveCapacity(count)

        let selector = Selector(("rectForSegment:inFrame:"))
        if segmentedCell.responds(to: selector),
           let imp = segmentedCell.method(for: selector) {
            typealias RectForSegment = @convention(c) (AnyObject, Selector, Int, NSRect) -> NSRect
            let fn = unsafeBitCast(imp, to: RectForSegment.self)
            for index in 0..<count {
                rects.append(fn(segmentedCell, selector, index, bounds))
            }
            return rects
        }

        // Fallback to manual calculation
        let layoutRect = segmentedCell.drawingRect(forBounds: bounds)
        var widths: [CGFloat] = []
        widths.reserveCapacity(count)
        for index in 0..<count {
            var w = segmentedCell.width(forSegment: index)
            if w <= 0 {
                w = max(layoutRect.width / CGFloat(count), 1)
            }
            widths.append(w)
        }
        let totalWidth = widths.reduce(0, +)
        let paddingPerSegment = (layoutRect.width - totalWidth) / CGFloat(max(count, 1))
        var leading: CGFloat = layoutRect.minX
        for width in widths {
            let trailing = leading + width + paddingPerSegment
            rects.append(NSRect(x: leading, y: layoutRect.minY, width: trailing - leading, height: layoutRect.height))
            leading = trailing
        }
        return rects
    }

    private func destinationIndex(at point: NSPoint, rects: [NSRect], stickyIndex: Int) -> Int {
        let clampedSticky = max(0, min(stickyIndex, rects.count - 1))
        if rects.isEmpty { return clampedSticky }

        // Use midpoints and a neutral dead zone at each boundary to prevent flip-flop.
        var midpoints: [CGFloat] = rects.map { $0.midX }
        // Ensure increasing order in case rects are misordered.
        midpoints.sort()

        let deadZone: CGFloat = 10.0

        // Edges
        if point.x <= midpoints.first! {
            return 0
        }
        if point.x >= midpoints.last! {
            return rects.count - 1
        }

        for i in 0..<(midpoints.count - 1) {
            let left = midpoints[i]
            let right = midpoints[i + 1]
            let boundary = (left + right) / 2
            let lower = boundary - deadZone
            let upper = boundary + deadZone

            if point.x < lower {
                return i
            }
            if point.x > upper {
                continue
            }
            // Inside dead zone around boundary: stick with current destination.
            return clampedSticky
        }

        return clampedSticky
    }
}
