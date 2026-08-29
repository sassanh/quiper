import XCTest
import AppKit
@testable import Quiper

@MainActor
final class TabRingQuickTapTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Settings.shared.reset()
        // Clean up leaked windows from prior tests and the host app; hasModalWindow
        // scans NSApp.windows and would otherwise be polluted by 150+ live windows in CI.
        NSApp.windows.forEach { $0.orderOut(nil) }
    }

    override func tearDown() {
        NSApp.windows.forEach { $0.orderOut(nil) }
        Settings.shared.reset()
        super.tearDown()
    }

    // MARK: - Forward ring (⌘`)

    func testQuickTapWithCommandAlreadyReleasedCompletesGesture() {
        let controller = makeController()
        defer { settle(controller) }
        seedTabRing(controller)

        // Simulates the async Carbon callback executing after ⌘ was released.
        controller.handleGraveKeyDown(currentModifiers: [])

        XCTAssertFalse(controller.isCyclingHistory, "Gesture must not stay active when ⌘ was already released")
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false, "Ring HUD must be dismissed")
        XCTAssertEqual(controller.activeSessionIndex, 1, "Pending switch must be committed")
        XCTAssertNil(controller.highlightedTab)
    }

    func testHeldCommandKeepsCyclingUntilFlagsChange() {
        let controller = makeController()
        defer { settle(controller) }
        seedTabRing(controller)

        controller.handleGraveKeyDown(currentModifiers: [.command])

        XCTAssertTrue(controller.isCyclingHistory)
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, true)

        controller.handleFlagsChanged(event: makeFlagsEvent(modifiers: []))

        XCTAssertFalse(controller.isCyclingHistory)
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false)
    }

    // MARK: - Backward ring (⌘⇧`)

    func testBackwardQuickTapWithCommandAlreadyReleasedCompletesGesture() {
        let controller = makeController()
        defer { settle(controller) }
        seedTabRing(controller)

        controller.handleGraveBackwardKeyDown(currentModifiers: [])

        XCTAssertFalse(controller.isCyclingHistory, "Gesture must not stay active when ⌘ was already released")
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false, "Ring HUD must be dismissed")
        XCTAssertEqual(controller.activeSessionIndex, 2, "Pending backward switch must be committed")
    }

    // MARK: - Key-status loss

    func testLosingKeyStatusMidCycleCommitsAndDismissesRing() {
        // When another window steals key status mid-gesture (e.g. a system
        // input popup), the events that normally end the cycle may never be
        // delivered — resigning key must commit and dismiss immediately.
        let controller = makeController()
        defer { settle(controller) }
        seedTabRing(controller)
        controller.skipModalCheck = true

        controller.handleGraveKeyDown(currentModifiers: [.command])
        XCTAssertTrue(controller.isCyclingHistory)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))

        XCTAssertFalse(controller.isCyclingHistory, "Resigning key must end the cycle")
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false, "Ring HUD must be dismissed")
        XCTAssertEqual(controller.activeSessionIndex, 1, "Pending switch must be committed")
    }

    func testCycleEndsEvenWhileAModalWindowIsKey() {
        // Locks the ordering inside handleFlagsChanged: ending the cycle on
        // ⌘ release must outrank the hasModalWindow gate, which is true
        // whenever transient system input UI holds key status.
        let controller = makeController()
        defer { settle(controller) }
        seedTabRing(controller)

        let impostor = ForeignBlockingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        impostor.orderFront(nil)
        defer { impostor.orderOut(nil) }

        controller.handleGraveKeyDown(currentModifiers: [.command])
        XCTAssertTrue(controller.hasModalWindow, "Precondition: the foreign window gates shortcuts")
        XCTAssertTrue(controller.isCyclingHistory)

        controller.handleFlagsChanged(event: makeFlagsEvent(modifiers: []))

        XCTAssertFalse(controller.isCyclingHistory, "⌘ release must end the cycle despite modal gating")
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false, "Ring HUD must be dismissed")
    }

    /// A key-capable window that does not match the transient-system-input
    /// pattern — i.e. an unknown window that must keep blocking shortcuts.
    /// Key status is pinned so the test never depends on host activation.
    @MainActor
    private final class ForeignBlockingWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var isKeyWindow: Bool { true }
    }

    // MARK: - Helpers

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        // Ensure a clean window state before creating the controller, mirroring
        // ModalWindowDetectionTests which orders out any existing visible window
        // leaked by prior tests or the host app (156+ windows in CI).
        NSApp.windows
            .filter { $0.isVisible }
            .forEach { $0.orderOut(nil) }

        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        return controller
    }

    /// Two past tabs so the ring has more than two entries and takes the
    /// visible-HUD path instead of the direct two-tab switch shortcut.
    private func seedTabRing(_ controller: MainWindowController) {
        let serviceID = controller.services[0].id
        controller.tabHistory = [
            TabIdentifier(serviceID: serviceID, sessionIndex: 1),
            TabIdentifier(serviceID: serviceID, sessionIndex: 2)
        ]
    }

    private func makeFlagsEvent(modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0
        )!
    }

    private func settle(_ controller: MainWindowController) {
        controller.cancelHistoryCycling()
        controller.window?.orderOut(nil)
    }
}
