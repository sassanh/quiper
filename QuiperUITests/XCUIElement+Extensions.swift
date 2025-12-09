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
}
