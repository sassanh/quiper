import XCTest

extension XCUIElement {
    func forceTap() {
        if !self.isHittable {
            let scrollView = XCUIApplication().scrollViews.firstMatch
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            
            for _ in 0...5 { 
                if self.isHittable { break }
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Moves the pointer to the exact center of the element's frame.
    ///
    /// `hover()` resolves a point near the frame's top edge instead of its
    /// center, leaving a margin of about one point before the pointer falls
    /// off the element. This lands the pointer dead center, the same point
    /// clicks use.
    func hoverAtCenter() {
        self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
    }
}
