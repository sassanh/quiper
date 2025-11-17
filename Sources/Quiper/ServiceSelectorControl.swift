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

        guard isDragging, let destination = segmentIndex(at: location) else { return }
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
        let boundsWidth = bounds.width
        guard boundsWidth > 0 else { return nil }
        let clampedX = max(0, min(boundsWidth, point.x))

        if let segmentedCell = cell as? NSSegmentedCell {
            var leadingEdge: CGFloat = 0
            for index in 0..<count {
                var segmentWidth = segmentedCell.width(forSegment: index)
                if segmentWidth <= 0 {
                    let remainingSegments = CGFloat(count - index)
                    segmentWidth = max((boundsWidth - leadingEdge) / remainingSegments, 1)
                }
                let trailingEdge = min(boundsWidth, leadingEdge + segmentWidth)
                if clampedX >= leadingEdge && clampedX <= trailingEdge {
                    return index
                }
                leadingEdge = trailingEdge
            }
            return nil
        } else {
            let segmentWidth = boundsWidth / CGFloat(count)
            let rawIndex = Int(clampedX / segmentWidth)
            return max(0, min(count - 1, rawIndex))
        }
    }
}
