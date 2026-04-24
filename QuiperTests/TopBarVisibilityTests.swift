import XCTest
import AppKit
@testable import Quiper

@MainActor
final class TopBarVisibilityTests: XCTestCase {

    // MARK: - Helpers

    private func getPrivateProperty<T>(_ object: Any, _ name: String) -> T? {
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if child.label == name {
                return child.value as? T
            }
        }
        return nil
    }

    private func makeFlagsEvent(modifiers: NSEvent.ModifierFlags, windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0
        )!
    }

    override func setUp() {
        super.setUp()
        Settings.shared.reset()
    }

    override func tearDown() {
        super.tearDown()
        Settings.shared.reset()
    }

    // MARK: - Settings

    func testTopBarVisibility_DefaultIsVisible() {
        XCTAssertEqual(Settings.shared.topBarVisibility, .visible)
    }

    func testTopBarVisibility_CanBeSetToHidden() {
        Settings.shared.topBarVisibility = .hidden
        XCTAssertEqual(Settings.shared.topBarVisibility, .hidden)
        Settings.shared.topBarVisibility = .visible
        XCTAssertEqual(Settings.shared.topBarVisibility, .visible)
    }

    func testTopBarVisibility_ResetRestoresDefault() {
        Settings.shared.topBarVisibility = .hidden
        Settings.shared.reset()
        XCTAssertEqual(Settings.shared.topBarVisibility, .visible)
    }

    func testShowHiddenBarOnModifiers_DefaultIsTrue() {
        XCTAssertTrue(Settings.shared.showHiddenBarOnModifiers)
    }

    func testShowHiddenBarOnModifiers_CanBeDisabled() {
        Settings.shared.showHiddenBarOnModifiers = false
        XCTAssertFalse(Settings.shared.showHiddenBarOnModifiers)
    }

    func testShowHiddenBarOnModifiers_ResetRestoresDefault() {
        Settings.shared.showHiddenBarOnModifiers = false
        Settings.shared.reset()
        XCTAssertTrue(Settings.shared.showHiddenBarOnModifiers)
    }

    // MARK: - DragArea alpha in visible mode

    func testDragArea_IsFullyVisibleByDefault() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        // topBarVisibility defaults to .visible — alpha should be 1.0
        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertNotNil(dragArea)
        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01)
    }

    func testDragArea_IsHiddenWhenModeSetToHidden() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)

        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertNotNil(dragArea)
        XCTAssertEqual(dragArea?.alphaValue ?? 1, 0.0, accuracy: 0.01)
    }

    func testDragArea_BecomesVisibleAgainWhenModeRestoredToVisible() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)

        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        Settings.shared.topBarVisibility = .visible
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01)
    }

    // MARK: - Modifier keys reveal header

    func testHeaderRevealedOnSessionModifier_WhenHiddenMode() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        controller.skipSafeAreaCheck = true
        controller.skipModalCheck = true

        Settings.shared.topBarVisibility = .hidden
        Settings.shared.showHiddenBarOnModifiers = true
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 1, 0.0, accuracy: 0.01, "Header should be hidden before modifiers")

        // Default session modifier is .command
        let event = makeFlagsEvent(modifiers: [.command], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: event)

        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01, "Header should be visible while session modifier held")
    }

    func testHeaderHiddenOnModifierRelease_WhenHiddenMode() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        controller.skipSafeAreaCheck = true
        controller.skipModalCheck = true

        Settings.shared.topBarVisibility = .hidden
        Settings.shared.showHiddenBarOnModifiers = true
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let pressEvent = makeFlagsEvent(modifiers: [.command], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: pressEvent)

        let releaseEvent = makeFlagsEvent(modifiers: [], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: releaseEvent)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 1, 0.0, accuracy: 0.01, "Header should hide when modifier released")
    }

    func testHeaderRevealedOnServiceModifier_WhenHiddenMode() {
        let services = [
            Service(name: "A", url: "https://a.com", focus_selector: ""),
            Service(name: "B", url: "https://b.com", focus_selector: "")
        ]
        let controller = MainWindowController(services: services)
        controller.skipSafeAreaCheck = true
        controller.skipModalCheck = true

        Settings.shared.topBarVisibility = .hidden
        Settings.shared.showHiddenBarOnModifiers = true
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 1, 0.0, accuracy: 0.01)

        // Default service primary modifier is Cmd+Ctrl
        let event = makeFlagsEvent(modifiers: [.command, .control], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: event)

        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01, "Header should be visible while service modifier held")
    }

    func testModifierDoesNotRevealHeader_WhenShowOnModifiersDisabled() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        controller.skipSafeAreaCheck = true
        controller.skipModalCheck = true

        Settings.shared.topBarVisibility = .hidden
        Settings.shared.showHiddenBarOnModifiers = false
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        let event = makeFlagsEvent(modifiers: [.command], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: event)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 1, 0.0, accuracy: 0.01, "Header should stay hidden when showOnModifiers is off")
    }

    func testModifierDoesNotRevealHeader_WhenVisibleMode() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)
        controller.skipSafeAreaCheck = true
        controller.skipModalCheck = true

        // Mode is visible (default)
        XCTAssertEqual(Settings.shared.topBarVisibility, .visible)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        let alphaBeforeModifier = dragArea?.alphaValue ?? 0

        let event = makeFlagsEvent(modifiers: [.command], windowNumber: controller.window?.windowNumber ?? 0)
        controller.handleFlagsChanged(event: event)

        // Alpha should remain 1 (unchanged)
        XCTAssertEqual(dragArea?.alphaValue ?? 0, alphaBeforeModifier, accuracy: 0.01)
    }

    // MARK: - showHeaderTemporarily

    func testShowHeaderTemporarily_DoesNothingInVisibleMode() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)

        // Visible mode — calling showHeaderTemporarily should be a no-op (guard bails early)
        controller.showHeaderTemporarily()

        let isForced: Bool = getPrivateProperty(controller, "isHeaderForcedVisibleForAction") ?? false
        XCTAssertFalse(isForced, "showHeaderTemporarily should do nothing in visible mode")
    }

    func testShowHeaderTemporarily_ShowsHeaderInHiddenMode() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)

        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        controller.showHeaderTemporarily()

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01, "Header should appear after showHeaderTemporarily")
    }

    func testSelectService_TriggersHeaderReveal() {
        let services = [
            Service(name: "A", url: "https://a.com", focus_selector: ""),
            Service(name: "B", url: "https://b.com", focus_selector: "")
        ]
        let controller = MainWindowController(services: services)

        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        // Select different service — should trigger showHeaderTemporarily
        controller.selectService(at: 1)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01, "Header should be visible after service switch")
    }

    func testSwitchSession_TriggersHeaderReveal() {
        let services = [Service(name: "Test", url: "https://test.com", focus_selector: "")]
        let controller = MainWindowController(services: services)

        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)

        controller.switchSession(to: 2)

        let dragArea: DraggableView? = getPrivateProperty(controller, "dragArea")
        XCTAssertEqual(dragArea?.alphaValue ?? 0, 1.0, accuracy: 0.01, "Header should be visible after session switch")
    }

    // MARK: - DraggableView hitTest

    func testDraggableViewHitTest_ReturnsNilWhenTransparent() {
        let view = DraggableView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.alphaValue = 0.0
        let result = view.hitTest(NSPoint(x: 100, y: 20))
        XCTAssertNil(result, "Hit test should return nil when view is transparent")
    }

    func testDraggableViewHitTest_ReturnsViewWhenVisible() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let view = DraggableView(frame: container.bounds)
        container.addSubview(view)
        view.alphaValue = 1.0
        let result = view.hitTest(NSPoint(x: 100, y: 20))
        XCTAssertNotNil(result, "Hit test should return a view when visible")
    }
}
