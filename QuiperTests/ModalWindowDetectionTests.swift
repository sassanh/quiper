import XCTest
import AppKit
@testable import Quiper

@MainActor
final class ModalWindowDetectionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Settings.shared.reset()
    }

    override func tearDown() {
        Settings.shared.reset()
        super.tearDown()
    }

    /// Mimics the macOS-beta Siri/accent popup host that lives inside the
    /// app's window list and holds key status spontaneously. Key status is
    /// pinned so the test never depends on host activation.
    @MainActor
    private final class MockCampoLightweightUIHostWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var isKeyWindow: Bool { true }
    }

    /// An unknown key window — must keep counting as modal.
    @MainActor
    private final class ForeignBlockingWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    func testForeignKeyWindowCountsAsModal() {
        let controller = makeController()
        let impostor = ForeignBlockingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        impostor.title = "Foreign"
        impostor.orderFront(nil)
        defer {
            impostor.orderOut(nil)
            controller.window?.orderOut(nil)
        }

        XCTAssertTrue(controller.hasModalWindow, "An unknown key window must still disable shortcuts")
    }

    func testTransientSystemInputWindowDoesNotBlockShortcuts() {
        let controller = makeController()
        let siriPopup = MockCampoLightweightUIHostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        siriPopup.orderFront(nil)
        defer {
            siriPopup.orderOut(nil)
            controller.window?.orderOut(nil)
        }

        XCTAssertFalse(controller.hasModalWindow, "The transient Siri/input host must not disable shortcuts")
    }

    func testFloatingHUDPanelsDoNotCountAsModal() {
        let controller = makeController()
        controller.showPromptHistoryHUD()
        defer {
            controller.hidePromptHistoryHUD()
            controller.hidePromptHistoryHUD()
            controller.window?.orderOut(nil)
        }
        guard let hudWindow = controller.promptHistoryHUDWindow else {
            return XCTFail("Prompt history HUD window missing")
        }
        hudWindow.makeKey()

        XCTAssertFalse(controller.hasModalWindow, "Interactive HUD panels are not modals")
    }

    // MARK: - Helpers

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)

        // The test host app launches its own real overlay at startup; that
        // window would otherwise leak into hasModalWindow's scan.
        NSApp.windows
            .filter { $0 is OverlayWindow && $0 !== controller.window }
            .forEach { $0.orderOut(nil) }

        return controller
    }
}
