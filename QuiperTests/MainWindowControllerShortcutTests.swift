import XCTest
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class MainWindowControllerShortcutTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Ensure tests are not affected by any persisted shortcut customizations.
        await MainActor.run {
            Settings.shared.wipeAllData()
            _ = Settings.shared.loadSettings()
            Settings.shared.appShortcutBindings = .defaults
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            Settings.shared.wipeAllData()
        }
        try await super.tearDown()
    }

    func testCommandArrowAdvancesSession() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .shift]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 1)
    }

    func testCommandArrowWrapsSessionLeft() {
        let controller = makeController()
        controller.switchSession(to: 0)

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_LeftArrow), modifiers: [.command, .shift]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 9)
    }

    func testCommandControlArrowChangesService() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeServiceID, controller.services[1].id)
    }

    func testCommandOptionArrowIsIgnored() {
        let controller = makeController()
        controller.switchSession(to: 3)

        let handled = controller.handleCommandShortcut(event: arrowEvent(keyCode: UInt16(kVK_RightArrow), modifiers: [.command, .option]))

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.activeSessionIndex, 3)
    }

    func testDigitShortcutSelectsSession() {
        let controller = makeController()
        controller.switchSession(to: 0)

        let handled = controller.handleCommandShortcut(event: digitEvent(number: 3, modifiers: [.command]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 2)
    }

    func testDigitShortcutShowsFindBarOnlyForOwningSession() async throws {
        let controller = makeController()
        controller.switchSession(to: 0)
        let window = try XCTUnwrap(controller.window)
        await activateAndMakeKey(window)
        defer {
            controller.findBarViewControllers.values.forEach { $0.hide() }
            window.orderOut(nil)
        }

        let firstFindBar = controller.findBarViewController!
        firstFindBar.show()
        XCTAssertTrue(firstFindBar.isVisible)
        XCTAssertTrue(firstFindBar.hasInputFocus)

        let handled = controller.handleCommandShortcut(event: digitEvent(number: 2, modifiers: [.command]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeSessionIndex, 1)
        XCTAssertFalse(controller.findBarViewController === firstFindBar)
        XCTAssertEqual(firstFindBar.view.superview?.isHidden, true)
        XCTAssertFalse(controller.findBarViewController.isVisible)

        let returnHandled = controller.handleCommandShortcut(event: digitEvent(number: 1, modifiers: [.command]))

        XCTAssertTrue(returnHandled)
        XCTAssertEqual(controller.activeSessionIndex, 0)
        XCTAssertTrue(controller.findBarViewController === firstFindBar)
        XCTAssertEqual(firstFindBar.view.superview?.isHidden, false)
        XCTAssertTrue(firstFindBar.isVisible)
        XCTAssertTrue(firstFindBar.hasInputFocus)
    }

    func testReturningToSessionDoesNotFocusFindBarWhenItWasUnfocused() async throws {
        let controller = makeController()
        controller.switchSession(to: 0)
        let window = try XCTUnwrap(controller.window)
        await activateAndMakeKey(window)
        defer {
            controller.findBarViewControllers.values.forEach { $0.hide() }
            window.orderOut(nil)
        }

        let firstFindBar = controller.findBarViewController!
        firstFindBar.show()
        window.makeFirstResponder(controller.activeWebView)
        XCTAssertTrue(firstFindBar.isVisible)
        XCTAssertFalse(firstFindBar.hasInputFocus)

        _ = controller.handleCommandShortcut(event: digitEvent(number: 2, modifiers: [.command]))
        _ = controller.handleCommandShortcut(event: digitEvent(number: 1, modifiers: [.command]))

        XCTAssertEqual(controller.activeSessionIndex, 0)
        XCTAssertTrue(controller.findBarViewController === firstFindBar)
        XCTAssertTrue(firstFindBar.isVisible)
        XCTAssertFalse(firstFindBar.hasInputFocus)
    }

    func testSwitchingBetweenSessionsWithOpenFindBarsUsesTabOwnedViews() {
        let controller = makeController()
        controller.switchSession(to: 0)
        controller.window?.makeKeyAndOrderFront(nil)
        defer {
            controller.findBarViewControllers.values.forEach { $0.hide() }
            controller.window?.orderOut(nil)
        }

        let firstFindBar = controller.findBarViewController!
        firstFindBar.show()
        _ = controller.handleCommandShortcut(event: digitEvent(number: 2, modifiers: [.command]))
        let secondFindBar = controller.findBarViewController!
        secondFindBar.show()

        _ = controller.handleCommandShortcut(event: digitEvent(number: 1, modifiers: [.command]))

        XCTAssertEqual(controller.activeSessionIndex, 0)
        XCTAssertTrue(controller.findBarViewController === firstFindBar)
        XCTAssertFalse(firstFindBar === secondFindBar)
        XCTAssertTrue(firstFindBar.isVisible)
        XCTAssertTrue(secondFindBar.isVisible)
        XCTAssertEqual(firstFindBar.view.superview?.isHidden, false)
        XCTAssertEqual(secondFindBar.view.superview?.isHidden, true)
    }

    func testDigitShortcutSelectsService() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(event: digitEvent(number: 2, modifiers: [.command, .control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.activeServiceID, controller.services[1].id)
    }

    func testClearedShortcutDoesNotCaptureTyping() {
        let controller = makeController()
        
        // Simulate clearing the Next Session shortcut (keyCode 0, modifierFlags 0)
        Settings.shared.appShortcutBindings.nextSession = HotkeyManager.Configuration(keyCode: 0, modifierFlags: 0)
        
        // Simulate typing the 'a' key (keyCode 0, no modifiers)
        let aEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)
        )!
        
        let handled = controller.handleCommandShortcut(event: aEvent)
        
        XCTAssertFalse(handled, "Typing 'a' should not be captured when a shortcut is cleared")
    }

    // MARK: - Helpers

    private func activateAndMakeKey(_ window: NSWindow) async {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        let keyWindowExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.isKeyWindow },
            object: nil
        )
        await fulfillment(of: [keyWindowExpectation], timeout: 2.0)
    }

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        return controller
    }

    private func arrowEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func digitEvent(number: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let digitKeyCode: UInt16
        switch number {
        case 1: digitKeyCode = UInt16(kVK_ANSI_1)
        case 2: digitKeyCode = UInt16(kVK_ANSI_2)
        case 3: digitKeyCode = UInt16(kVK_ANSI_3)
        case 4: digitKeyCode = UInt16(kVK_ANSI_4)
        case 5: digitKeyCode = UInt16(kVK_ANSI_5)
        case 6: digitKeyCode = UInt16(kVK_ANSI_6)
        case 7: digitKeyCode = UInt16(kVK_ANSI_7)
        case 8: digitKeyCode = UInt16(kVK_ANSI_8)
        case 9: digitKeyCode = UInt16(kVK_ANSI_9)
        case 0: digitKeyCode = UInt16(kVK_ANSI_0)
        default: fatalError("Unsupported digit \(number)")
        }

        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\(number)",
            charactersIgnoringModifiers: "\(number)",
            isARepeat: false,
            keyCode: digitKeyCode
        )!
    }
}
