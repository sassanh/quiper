import XCTest
import AppKit
@testable import Quiper

/// Guards against the AppKit NSRangeException raised by
/// `-[NSSegmentedCell setSelectedSegment:]` for out-of-bounds indices.
/// Pasting a URL into a pinned-tab engine changes which session slots are
/// visible, so a model-fresh index can briefly exceed a stale segment count.
@MainActor
final class SegmentedControlSelectionTests: XCTestCase {

    func testOutOfBoundsSelectionIsIgnored() {
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 2
        control.selectedSegment = 1

        control.selectedSegment = 5

        XCTAssertEqual(control.selectedSegment, 1)
    }

    func testNegativeOutOfBoundsSelectionIsIgnored() {
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 2
        control.selectedSegment = 1

        control.selectedSegment = -2

        XCTAssertEqual(control.selectedSegment, 1)
    }

    func testDeselectWithNegativeOneAlwaysAllowed() {
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 2
        control.selectedSegment = 1

        control.selectedSegment = -1

        XCTAssertEqual(control.selectedSegment, -1)
    }

    func testSelectionIntoEmptyControlIsIgnored() {
        // A pinned-tab engine with no URLs backs a zero-segment control;
        // syncing a selection into it must leave the control deselected
        // instead of storing a phantom selection.
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 0

        control.selectedSegment = 0

        XCTAssertEqual(control.selectedSegment, -1)
    }

    func testInBoundsSelectionStillApplies() {
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 3

        control.selectedSegment = 2

        XCTAssertEqual(control.selectedSegment, 2)
    }

    func testCollapsibleSelectorDoesNotForwardOutOfRangeWhileExpanded() {
        let selector = CollapsibleSelector()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView?.addSubview(selector)
        selector.frame = window.contentView!.bounds
        selector.setItems(["A", "B"])
        selector.selectedSegment = 0
        selector.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        selector.expand()
        XCTAssertTrue(selector.isExpanded)
        defer {
            selector.collapse()
            window.orderOut(nil)
        }

        // Out-of-range intent must not raise and must not move the open
        // panel; the recorded intent still applies once valid.
        func expandedSelection() -> Int? {
            selector.expandedPanel?.contentView?.subviews
                .compactMap { $0 as? SegmentedControl }.first?.selectedSegment
        }
        selector.selectedSegment = 9
        XCTAssertEqual(selector.selectedSegment, 9)
        XCTAssertEqual(expandedSelection(), 0)
        selector.selectedSegment = 1
        XCTAssertEqual(selector.selectedSegment, 1)
        XCTAssertEqual(expandedSelection(), 1)
    }

    func testOpenPanelGrowsWhenItemsGrow() {
        // Switching from a 3-tab pinned engine to a 5-tab one while the
        // hold-to-expand session panel is open must resize the panel:
        // otherwise the new tabs exist past the old 3-tab width, clipped
        // and unreachable until a later collapse heals it.
        let selector = CollapsibleSelector()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 100),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView?.addSubview(selector)
        selector.frame = window.contentView!.bounds
        selector.setItems(["1", "2", "3"])
        selector.selectedSegment = 0
        selector.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        selector.expand()
        XCTAssertTrue(selector.isExpanded)
        defer {
            selector.collapse()
            window.orderOut(nil)
        }

        func expandedControl() -> SegmentedControl? {
            selector.expandedPanel?.contentView?.subviews
                .compactMap { $0 as? SegmentedControl }.first
        }
        let beforeWidth = expandedControl()?.frame.width ?? 0
        let beforePanelWidth = selector.expandedPanel?.frame.width ?? 0

        // Engine switch while open: 3 tabs become 5.
        selector.setItems(["1", "2", "3", "4", "5"])

        guard let control = expandedControl() else {
            XCTFail("Expanded panel lost its control after growing items")
            return
        }
        XCTAssertEqual(control.segmentCount, 5)
        XCTAssertGreaterThan(control.frame.width, beforeWidth)
        // The panel itself must grow with the control: without the
        // setContentSize/re-anchor lines the control widens while the
        // panel stays at its old width, clipping the new tabs.
        XCTAssertGreaterThan(selector.expandedPanel?.frame.width ?? 0, beforePanelWidth)
        XCTAssertGreaterThanOrEqual(selector.expandedPanel?.frame.width ?? 0, control.frame.width)
        for segment in 0..<control.segmentCount {
            XCTAssertTrue(
                control.bounds.contains(control.rect(forSegment: segment)),
                "Segment \(segment) must lie inside the resized panel"
            )
        }
    }

    func testOpenPanelCollapsesWhenItemsEmpty() {
        // A pinned engine with no URLs has nothing to expand to: switching
        // to it while the panel is open must close the panel rather than
        // leave a blank one at the previous engine's width.
        let selector = CollapsibleSelector()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 100),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView?.addSubview(selector)
        selector.frame = window.contentView!.bounds
        selector.setItems(["1", "2", "3"])
        selector.selectedSegment = 0
        selector.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        selector.expand()
        XCTAssertTrue(selector.isExpanded)
        defer {
            window.orderOut(nil)
        }

        selector.setItems([])

        XCTAssertFalse(selector.isExpanded)
    }
}
