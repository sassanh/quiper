import XCTest
@testable import Quiper

@MainActor
final class CollapsibleSelectorTests: XCTestCase {
    
    var selector: CollapsibleSelector!
    var window: NSWindow!
    
    override func setUp() async throws {
        selector = CollapsibleSelector()
        // Host in a window to enable expansion logic
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.contentView?.addSubview(selector)
        selector.frame = window.contentView!.bounds
    }
    
    override func tearDown() async throws {
        selector = nil
        window = nil
    }
    
    func testInitializationDefaults() {
        XCTAssertFalse(selector.isExpanded)
        XCTAssertEqual(selector.selectedSegment, 0)
        XCTAssertTrue(selector.items.isEmpty)
        XCTAssertNil(selector.expandedPanel)
    }
    
    func testSettingItemsUpdatesState() {
        let items = ["One", "Two", "Three"]
        selector.items = items
        
        // Internal state check
        XCTAssertEqual(selector.items, items)
        
        // Verify intrinsic size changed (implied by content width update)
        let size = selector.intrinsicContentSize
        XCTAssertGreaterThan(size.width, 0)
    }
    
    func testSelectionUpdates() {
        selector.items = ["A", "B", "C"]
        selector.selectedSegment = 1
        
        XCTAssertEqual(selector.selectedSegment, 1)
        
        // Verify collapsed control reflects label "B"
        // We can't easily inspect the private collapsedControl directly without Mirror or exposing it,
        // but we can trust the public property `currentWidth` logic which relies on the selected label.
        // Or we can use Mirror to verify the internal control's label if strictly needed,
        // but functional verification is better.
        
        // Let's verify via the intended side-effect: intrinsic size for "B" should be different than "A" usually,
        // but here they might be similar.
        // Instead, let's verify selectedSegment persistence.
    }
    
    func testExpandAndCollapse() {
        selector.items = ["A", "B"]
        
        // Ensure layout and visibility for addChildWindow to work
        selector.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        
        let event = NSEvent.enterExitEvent(with: .mouseEntered,
                                           location: .zero,
                                           modifierFlags: [],
                                           timestamp: 0,
                                           windowNumber: window.windowNumber,
                                           context: nil,
                                           eventNumber: 0,
                                           trackingNumber: 0,
                                           userData: nil)!
        
        selector.mouseEntered(with: event)
        
        // Check expansion state
        XCTAssertTrue(selector.isExpanded, "Should be expanded after mouseEntered")
        XCTAssertNotNil(selector.expandedPanel, "Expanded panel should be created")
        
        // Verify expanded control properties
        if let panel = selector.expandedPanel {
             XCTAssertTrue(panel.isVisible)
        }
        
        // Test Collapse
        selector.collapse()
        
        // Wait for collapse animation and cleanup
        let expectation = XCTestExpectation(description: "Collapse animation completes")
        
        XCTAssertFalse(selector.isExpanded, "Should be marked collapsed immediately")
        
        // The panel cleanup happens async after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.selector.expandedPanel == nil {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDelegateCallbacks() {
        let delegate = MockSelectorDelegate()
        selector.delegate = delegate
        selector.items = ["A"]
        
        // Trigger expand
        let event = NSEvent.enterExitEvent(with: .mouseEntered,
                                            location: .zero,
                                            modifierFlags: [],
                                            timestamp: 0,
                                            windowNumber: window.windowNumber,
                                            context: nil,
                                            eventNumber: 0,
                                            trackingNumber: 0,
                                            userData: nil)!
        selector.mouseEntered(with: event)
        
        XCTAssertTrue(delegate.willExpandCalled)
    }
    
    func testRapidExpandCollapse() {
        selector.items = ["A", "B"]
        // Initial setup
        selector.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        
        // Simulate rapid toggle
        // 1. Expand
        selector.mouseEntered(with: makeEvent()) // expands
        XCTAssertTrue(selector.isExpanded)
        XCTAssertNotNil(selector.expandedPanel)
        
        // 2. Collapse (immediately)
        selector.collapse() // sets isExpanded=false, starts animation
        XCTAssertFalse(selector.isExpanded)
        // Panel still exists (fading)
        XCTAssertNotNil(selector.expandedPanel)
        
        // 3. Expand again (immediately, while first collapse animation is running)
        selector.mouseEntered(with: makeEvent())
        XCTAssertTrue(selector.isExpanded)
        let newPanel = selector.expandedPanel
        XCTAssertNotNil(newPanel)
        
        // 4. Wait for the FIRST collapse completion to fire
        // The first collapse completion will try to clean up.
        // If buggy, it will set expandedPanel = nil even though we just created a new one.
        
        let expectation = XCTestExpectation(description: "Wait for animation params")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Check state
            XCTAssertTrue(self.selector.isExpanded, "Should still be expanded")
            XCTAssertNotNil(self.selector.expandedPanel, "Panel reference should not be nilled out by previous collapse")
            XCTAssertEqual(self.selector.expandedPanel, newPanel, "Should still reference the new panel")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

class MockSelectorDelegate: CollapsibleSelectorDelegate {
    var willExpandCalled = false
    
    func isLoading(index: Int) -> Bool { false }
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int) {}
    func selectorWillExpand(_ selector: CollapsibleSelector) {
        willExpandCalled = true
    }
}

extension CollapsibleSelectorTests {
    func makeEvent() -> NSEvent {
        return NSEvent.enterExitEvent(with: .mouseEntered,
                                      location: .zero,
                                      modifierFlags: [],
                                      timestamp: 0,
                                      windowNumber: 0,
                                      context: nil,
                                      eventNumber: 0,
                                      trackingNumber: 0,
                                      userData: nil)!
    }
}
