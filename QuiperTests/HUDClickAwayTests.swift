import XCTest
import AppKit
@testable import Quiper

@MainActor
final class HUDClickAwayTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Settings.shared.reset()
    }

    override func tearDown() {
        Settings.shared.reset()
        super.tearDown()
    }

    // MARK: - Prompt History HUD

    func testOutsideClickDismissesPromptHistoryHUD() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showPromptHistoryHUD()
        XCTAssertNotNil(controller.promptHistoryHUDView)

        controller.dismissHUDsOnOutsideClick(at: pointOutsideAllWindows(of: controller))

        XCTAssertTrue(controller.promptHistoryHUDView?.isHiding ?? false)
    }

    func testInsideClickKeepsPromptHistoryHUDOpen() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showPromptHistoryHUD()
        let hud = try XCTUnwrap(controller.promptHistoryHUDView)

        controller.dismissHUDsOnOutsideClick(
            at: center(of: try XCTUnwrap(controller.promptHistoryHUDWindow))
        )

        XCTAssertEqual(hud.isHidden, false)
        XCTAssertEqual(hud.isHiding, false)
    }

    // MARK: - Modifier (Control Center) HUD

    func testOutsideClickDismissesModifierHUD() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.toggleModifierHUD()
        XCTAssertNotNil(controller.modifierHUDView)

        controller.dismissHUDsOnOutsideClick(at: pointOutsideAllWindows(of: controller))

        XCTAssertTrue(controller.modifierHUDView?.isHiding ?? false)
    }

    func testInsideClickKeepsModifierHUDBehaviorConsistent() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.toggleModifierHUD()
        let hud = try XCTUnwrap(controller.modifierHUDView)

        controller.dismissHUDsOnOutsideClick(
            at: center(of: try XCTUnwrap(controller.modifierHUDWindow))
        )

        XCTAssertEqual(hud.isHiding, false)
    }

    // MARK: - Tab History HUD

    func testOutsideClickDismissesTabHistoryHUD() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showTabHistoryHUD()
        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, true)

        controller.dismissHUDsOnOutsideClick(at: pointOutsideAllWindows(of: controller))

        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, false)
    }

    func testInsideClickKeepsTabHistoryHUDVisible() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showTabHistoryHUD()

        controller.dismissHUDsOnOutsideClick(
            at: center(of: try XCTUnwrap(controller.tabHistoryHUDWindow))
        )

        XCTAssertEqual(controller.tabHistoryHUDWindow?.isVisible, true)
    }

    // MARK: - Location Bar HUD

    func testOutsideClickDismissesLocationBarHUD() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showLocationBarHUD()
        XCTAssertNotNil(controller.locationBarHUDView)

        controller.dismissHUDsOnOutsideClick(at: pointOutsideAllWindows(of: controller))

        XCTAssertTrue(controller.locationBarHUDView?.isHiding ?? false)
    }

    func testInsideClickKeepsLocationBarOpen() throws {
        let controller = makeController()
        defer { settleAllHUDs(controller) }

        controller.showLocationBarHUD()
        let hud = try XCTUnwrap(controller.locationBarHUDView)

        controller.dismissHUDsOnOutsideClick(
            at: center(of: try XCTUnwrap(controller.locationBarHUDWindow))
        )

        XCTAssertEqual(hud.isHidden, false)
        XCTAssertEqual(hud.isHiding, false)
    }

    func testOutsideClickWithoutOpenHUDsIsHarmless() throws {
        let controller = makeController()

        controller.dismissHUDsOnOutsideClick(at: pointOutsideAllWindows(of: controller))

        XCTAssertNil(controller.locationBarHUDWindow)
        XCTAssertNil(controller.promptHistoryHUDWindow)
        XCTAssertNil(controller.modifierHUDWindow)
        XCTAssertNil(controller.tabHistoryHUDWindow)
    }

    // MARK: - Helpers

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        return controller
    }

    /// A point guaranteed to be outside every HUD: HUD frames are clamped to
    /// the visible screen, so a point far below-left of it always misses.
    private func pointOutsideAllWindows(of controller: MainWindowController) -> NSPoint {
        let screenOrigin = (controller.window?.screen ?? NSScreen.main)?.visibleFrame.origin ?? .zero
        return NSPoint(x: screenOrigin.x - 1_000, y: screenOrigin.y - 1_000)
    }

    private func center(of window: NSWindow) -> NSPoint {
        NSPoint(x: window.frame.midX, y: window.frame.midY)
    }

    /// Finalizes animated dismissals and detaches leftover windows.
    private func settleAllHUDs(_ controller: MainWindowController) {
        controller.hideTabHistoryHUD()
        controller.hidePromptHistoryHUD()
        controller.hidePromptHistoryHUD()
        controller.hideModifierHUD()
        controller.hideModifierHUD()
        controller.hideLocationBarHUD()
        controller.hideLocationBarHUD()
        controller.window?.orderOut(nil)
    }
}
