import UIKit

/// Detects a double-tap on the page and, when the second tap is held down,
/// tracks the finger so the navigation ring can follow it.
///
/// The recognizer never activates (its state stays `.possible`), so it coexists
/// with WKWebView's own gesture recognizers and never cancels touches delivered
/// to the page. Callers hook into the six callbacks to drive the ring UI.
final class DoubleTapGestureRecognizer: UIGestureRecognizer {
    var onSecondTapDown: ((CGPoint) -> Void)?
    var onHoldBegan: (() -> Void)?
    var onHoldUpdate: ((CGPoint) -> Void)?
    var onQuickEnd: ((CGPoint) -> Void)?
    var onHoldEnd: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    var onFirstTapEnded: ((CGPoint) -> Void)?

    private static let doubleTapWindow: TimeInterval = 0.35
    private static let holdDelay: TimeInterval = 0.28
    private static let tapSlop: CGFloat = 18
    private static let doubleTapDistance: CGFloat = 40

    private var firstTapTime: TimeInterval?
    private var firstTapLocation = CGPoint.zero
    private var firstTapTouch: UITouch?
    private var secondTapTouch: UITouch?
    private var isSecondTapDown = false
    private var holdFired = false
    private var secondTapDownLocation = CGPoint.zero
    private var holdTask: Task<Void, Never>?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, touches.count == 1 else {
            cancelTracking()
            return
        }
        let location = touch.location(in: view)
        if isArmedForSecondTap(now: touch.timestamp),
           distance(from: firstTapLocation, to: location) <= Self.doubleTapDistance {
            isSecondTapDown = true
            secondTapTouch = touch
            secondTapDownLocation = location
            onSecondTapDown?(location)
            scheduleHold()
        } else {
            firstTapTouch = touch
            firstTapLocation = location
            firstTapTime = nil
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: view)
        if isSecondTapDown, secondTapTouch == touch {
            if holdFired {
                onHoldUpdate?(location)
            } else if distance(from: secondTapDownLocation, to: location) > Self.tapSlop {
                cancelTracking()
            }
        } else if firstTapTouch == touch {
            if distance(from: firstTapLocation, to: location) > Self.tapSlop {
                firstTapTouch = nil
                firstTapTime = nil
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        if isSecondTapDown, secondTapTouch == touch {
            let location = touch.location(in: view)
            if holdFired {
                onHoldEnd?(location)
            } else {
                onQuickEnd?(location)
            }
            resetTracking()
        } else if firstTapTouch == touch {
            firstTapTouch = nil
            firstTapTime = touch.timestamp
            onFirstTapEnded?(firstTapLocation)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        if isSecondTapDown, secondTapTouch == touch {
            cancelTracking()
        } else if firstTapTouch == touch {
            firstTapTouch = nil
            firstTapTime = nil
        }
    }

    private func isArmedForSecondTap(now: TimeInterval) -> Bool {
        guard let firstTapTime else { return false }
        return now - firstTapTime <= Self.doubleTapWindow
    }

    private func scheduleHold() {
        holdTask?.cancel()
        holdFired = false
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.holdDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.isSecondTapDown else { return }
            self.holdFired = true
            self.onHoldBegan?()
        }
    }

    private func cancelTracking() {
        holdTask?.cancel()
        holdTask = nil
        let wasHolding = isSecondTapDown
        isSecondTapDown = false
        secondTapTouch = nil
        holdFired = false
        firstTapTouch = nil
        firstTapTime = nil
        if wasHolding {
            onCancel?()
        }
    }

    private func resetTracking() {
        holdTask?.cancel()
        holdTask = nil
        isSecondTapDown = false
        secondTapTouch = nil
        holdFired = false
        firstTapTouch = nil
        firstTapTime = nil
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
