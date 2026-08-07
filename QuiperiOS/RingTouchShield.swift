import UIKit

/// A transparent view that sits on top of the web view and, for the brief
/// window after a single tap, swallows a second tap landing near the first.
///
/// The shield returns itself from `hitTest` while armed, so the second tap of a
/// double-tap is never delivered to the page's content view: it cannot start a
/// text selection, scroll, or click while the navigation ring is open. Gesture
/// recognizers attached to the web view (an ancestor of the shield) still
/// receive the touch, so the ring recognizer keeps working.
final class RingTouchShield: UIView {
    private static let slop: CGFloat = 40
    private static let armWindow: TimeInterval = 0.35

    private var anchor: CGPoint?
    private var isArmed = false
    private var disarmTask: Task<Void, Never>?

    /// Arms the shield around `point` (in the host view's coordinates) for the
    /// double-tap window; a touch down near that point is swallowed.
    func arm(at point: CGPoint) {
        anchor = point
        isArmed = true
        disarmTask?.cancel()
        disarmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.armWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.disarm()
        }
    }

    func disarm() {
        disarmTask?.cancel()
        disarmTask = nil
        isArmed = false
        anchor = nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isArmed, let anchor else { return nil }
        guard hypot(point.x - anchor.x, point.y - anchor.y) <= Self.slop else { return nil }
        return self
    }
}
