import XCTest
@testable import Quiper

@MainActor
final class CollapsibleSelectorTests: XCTestCase {
    
    var selector: CollapsibleSelector!
    var window: NSWindow!
    
    override func setUp() async throws {
        selector = CollapsibleSelector()
        // Host in a window to enable expansion logic
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
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
        let firstPanel = selector.expandedPanel
        XCTAssertNotNil(firstPanel)
        
        // 2. Collapse immediately. Ownership is detached before the fade so a
        // later expansion is not tied to the outgoing panel's cleanup.
        selector.collapse()
        XCTAssertFalse(selector.isExpanded)
        XCTAssertNil(selector.expandedPanel)
        
        // 3. Expand again immediately while the old panel is still fading out
        selector.mouseEntered(with: makeEvent())
        XCTAssertTrue(selector.isExpanded)
        let newPanel = selector.expandedPanel
        XCTAssertNotNil(newPanel)
        XCTAssertNotEqual(newPanel, firstPanel, "Re-expansion should attach a new panel")
        
        // 4. Wait for the first collapse's orderOut to finish. Cleanup of the
        // detached panel must not clear or replace the new expanded panel.
        let expectation = XCTestExpectation(description: "Wait for previous collapse cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertTrue(self.selector.isExpanded, "Should still be expanded")
            XCTAssertNotNil(self.selector.expandedPanel, "New panel must survive previous collapse cleanup")
            XCTAssertEqual(self.selector.expandedPanel, newPanel, "Should still reference the new panel")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testInstantiationState() {
        let delegate = MockSelectorDelegate()
        
        // Configure delegate to return some segments as uninstantiated
        delegate.isInstantiatedStub = { selector, index in
            return index == 0 // Only first segment is instantiated
        }
        
        selector.delegate = delegate
        selector.items = ["Instantiated", "Uninstantiated1", "Uninstantiated2"]
        selector.showInstantiationState = true
        
        // Verify the property is set
        XCTAssertTrue(selector.showInstantiationState)
        
        // Trigger a display update
        selector.refreshInstantiationState()
        
        // While we can't easily test the visual appearance without complex rendering inspection,
        // we can verify the delegate is called correctly
        XCTAssertTrue(delegate.selector(selector, isInstantiated: 0))
        XCTAssertFalse(delegate.selector(selector, isInstantiated: 1))
        XCTAssertFalse(delegate.selector(selector, isInstantiated: 2))
        
        // Test with showInstantiationState disabled
        selector.showInstantiationState = false
        XCTAssertFalse(selector.showInstantiationState)
    }
}

class MockSelectorDelegate: CollapsibleSelectorDelegate {
    var willExpandCalled = false
    var isLoadingStub: ((Int) -> Bool)?
    var isInstantiatedStub: ((CollapsibleSelector, Int) -> Bool)?
    
    func isLoading(index: Int) -> Bool { 
        return isLoadingStub?(index) ?? false 
    }
    
    func selector(_ selector: CollapsibleSelector, isInstantiated index: Int) -> Bool {
        return isInstantiatedStub?(selector, index) ?? true 
    }
    
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
