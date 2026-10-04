import XCTest
import AppKit
@testable import Quiper

/// Key status is decided by the explicit focus stages — the overlay's show
/// restore and the session-switch focus policy — never by a popup merely
/// becoming visible. The show path must recover the exact window that was
/// key before the hide (popup A), keep the overlay key when the overlay held
/// focus, and fall back cleanly when the previous key window is gone.
@MainActor
final class PopupKeyRestoreTests: XCTestCase {

    /// The shared stage: an overlay on session 0 of Alpha with two popups
    /// open — `firstPopup` is the older one, `secondPopup` the newest.
    @MainActor
    private struct Stage {
        let controller: MainWindowController
        let manager: WebViewManager
        let services: [Service]
        let firstPopup: NSWindow
        let secondPopup: NSWindow

        func cleanup() {
            secondPopup.close()
            firstPopup.close()
            manager.removeWebView(for: services[0], sessionIndex: 0)
            controller.window?.orderOut(nil)
        }
    }

    private func openStage() async throws -> Stage {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        Settings.shared.services = services
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        // The focus gate must not be short-circuited by windows other tests
        // left on screen: both force `isOverlayInteractable` to false by design.
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)

        controller.show()
        let manager = try XCTUnwrap(controller.webViewManager, "The overlay's manager must exist")
        let webView = try XCTUnwrap(controller.activeWebView, "The overlay's tab must exist")

        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        let firstPopup = try XCTUnwrap(
            NSApp.windows.first(where: { manager.isPopupWindow($0) }),
            "A managed popup window must open"
        )
        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        let secondPopup = try XCTUnwrap(
            NSApp.windows.first(where: { manager.isPopupWindow($0) && $0 !== firstPopup }),
            "A second managed popup window must open"
        )
        // Consume the show path's first deferred restore now: in the app it
        // lands a runloop turn after show(), before any user interaction.
        // Scenarios below start from a settled stage, not a pending restore.
        await settleFocusStages()
        return Stage(
            controller: controller,
            manager: manager,
            services: services,
            firstPopup: firstPopup,
            secondPopup: secondPopup
        )
    }

    /// Lets the show path's deferred focus stages run: show() applies its
    /// key restore on the next runloop turn, after the input-focus warm-up.
    private func settleFocusStages() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    private func makeKeyOrFail(_ window: NSWindow?, reason: String) throws {
        let window = try XCTUnwrap(window, "The \(reason) must exist")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.isKeyWindow else {
            throw XCTSkip("The test host refused key status: \(reason)")
        }
    }

    private func withSettingsRestored(_ body: () async throws -> Void) async throws {
        let originalOnboarding = Settings.shared.hasCompletedGhostOnboarding
        let originalServices = Settings.shared.services
        Settings.shared.hasCompletedGhostOnboarding = true
        defer {
            Settings.shared.hasCompletedGhostOnboarding = originalOnboarding
            Settings.shared.services = originalServices
        }
        try await body()
    }

    func testShowRestoresThePopupThatWasKeyBeforeTheHide() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            // The older popup is key — "popup A" — while a newer popup exists.
            try makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.hide()
            stage.controller.show()
            await settleFocusStages()

            XCTAssertTrue(
                stage.firstPopup.isKeyWindow,
                "Re-showing must restore the popup that was key before the hide, not the newest popup"
            )
        }
    }

    func testShowKeepsTheOverlayKeyWhenTheOverlayWasKeyBeforeTheHide() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            try makeKeyOrFail(stage.controller.window, reason: "the overlay")

            stage.controller.hide()
            stage.controller.show()
            await settleFocusStages()

            XCTAssertEqual(
                stage.controller.window?.isKeyWindow, true,
                "Re-showing must keep the overlay key instead of handing focus to the newest popup"
            )
        }
    }

    func testShowFallsBackToTheOverlayWhenTheKeyPopupIsGone() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            try makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.hide()
            stage.firstPopup.close()
            stage.controller.show()
            await settleFocusStages()

            XCTAssertEqual(
                stage.controller.window?.isKeyWindow, true,
                "A key popup that closed while hidden must fall back to the overlay"
            )
        }
    }

    func testShowingAPopupNeverTakesKeyStatusOnItsOwn() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            try makeKeyOrFail(stage.controller.window, reason: "the overlay")

            // Order the session's popups out, then let the visibility sync
            // show them again — exactly what a show or session switch runs.
            stage.manager.hideAllSessionPopups()
            stage.manager.syncPopupVisibility(
                forActiveTab: TabIdentifier(serviceID: stage.services[0].id, sessionIndex: 0)
            )

            XCTAssertTrue(stage.firstPopup.isVisible, "The sync must show the session's popup")
            XCTAssertTrue(stage.secondPopup.isVisible, "The sync must show the session's popup")
            XCTAssertEqual(
                stage.controller.window?.isKeyWindow, true,
                "Showing a popup must not move key status; only the focus stages may"
            )
        }
    }

    func testSwitchingBackRestoresTheSessionsOwnKeyPopup() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            // The older popup is the session's active one before switching away.
            try makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.switchSession(to: 1)
            stage.controller.switchSession(to: 0)
            await settleFocusStages()

            XCTAssertTrue(
                stage.firstPopup.isKeyWindow,
                "Switching back must restore the popup this session last had key, not the newest popup"
            )
        }
    }
}
