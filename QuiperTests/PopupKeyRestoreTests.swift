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

    private func makeKeyOrFail(_ window: NSWindow?, reason: String) async throws {
        let window = try XCTUnwrap(window, "The \(reason) must exist")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard await waitForKeyStatus(of: window) else {
            throw XCTSkip("The test host refused key status: \(reason)")
        }
    }

    /// Waits for the window server to grant `window` key status. The
    /// grant is asynchronous: `activate` and `makeKeyAndOrderFront`
    /// return before the handover lands, and on a loaded CI runner the
    /// handover is late enough that one immediate read mistakes the
    /// delay for refusal. A host that grants nothing within the
    /// deadline still reads as refusal.
    private func waitForKeyStatus(of window: NSWindow) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if window.isKeyWindow { return true }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return window.isKeyWindow
    }

    /// Waits until the host has granted this app key status at all. The
    /// show stages pick their focus target while that grant may still
    /// be pending: judging the choice before focus arrives would blame
    /// the restore for a grant the host never gave, so a run with no
    /// grant skips instead of failing.
    private func waitForHostKeyGrant() async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if NSApp.isActive, NSApp.keyWindow != nil { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return NSApp.isActive && NSApp.keyWindow != nil
    }

    /// Opens Settings over `overlay` the way the app does — a child of the
    /// overlay, keyed through the gate — skipping the test if the host
    /// refuses key status to it.
    private func openSettingsOver(_ overlay: NSWindow) async throws {
        let settings = AppDelegate.sharedSettingsWindow
        overlay.addChildWindow(settings, ordered: .above)
        NSApp.activate(ignoringOtherApps: true)
        KeyFocusGate.shared.focus(settings)
        guard await waitForKeyStatus(of: settings) else {
            settings.orderOut(nil)
            throw XCTSkip("The test host refused key status: Settings")
        }
    }

    private func withSettingsRestored(_ body: () async throws -> Void) async throws {
        let originalOnboarding = Settings.shared.hasCompletedGhostOnboarding
        let originalServices = Settings.shared.services
        let originalTabSurvivalPolicy = Settings.shared.tabSurvivalPolicy
        let originalTabState = Settings.shared.persistedTabState
        Settings.shared.hasCompletedGhostOnboarding = true
        Settings.shared.tabSurvivalPolicy = .always
        // The launch focus descriptor is an explicit input of every
        // scenario here: pin it to "no record" unless a test seeds one,
        // so no save another test triggered can steer the first show.
        Settings.shared.persistedTabState?.keyWindow = nil
        defer {
            Settings.shared.hasCompletedGhostOnboarding = originalOnboarding
            Settings.shared.services = originalServices
            Settings.shared.tabSurvivalPolicy = originalTabSurvivalPolicy
            Settings.shared.persistedTabState = originalTabState
        }
        try await body()
    }

    /// The quit-side stage of a relaunch scenario: tab state seeded with
    /// two saved popups for one session, then a controller whose first
    /// show restored them. Focusing a window here records the focus
    /// descriptor the save-on-focus writes; the relaunch leg builds a
    /// fresh controller from that state.
    @MainActor
    private struct QuitStage {
        let controller: MainWindowController
        let manager: WebViewManager
        let services: [Service]
        let owner: TabIdentifier
        let popups: [NSWindow]

        func cleanup() {
            for popup in popups { popup.close() }
            manager.removeWebView(for: services[0], sessionIndex: 0)
            controller.window?.orderOut(nil)
        }
    }

    private func openQuitStage() throws -> QuitStage {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        Settings.shared.services = services
        let owner = TabIdentifier(serviceID: services[0].id, sessionIndex: 0)
        var seed = PersistedTabState()
        seed.activeServiceID = services[0].id
        seed.openTabs = [services[0].id: [0: "https://alpha.test"]]
        seed.popups = [
            PersistedPopupState(
                serviceID: owner.serviceID, sessionIndex: 0,
                url: "https://popup.test/older",
                frameX: 90, frameY: 90, frameWidth: 480, frameHeight: 360
            ),
            PersistedPopupState(
                serviceID: owner.serviceID, sessionIndex: 0,
                url: "https://popup.test/newer",
                frameX: 420, frameY: 140, frameWidth: 480, frameHeight: 360
            )
        ]
        Settings.shared.persistedTabState = seed

        let controller = MainWindowController(services: services)
        // The focus gate must not be short-circuited by windows other tests
        // left on screen: both force `isOverlayInteractable` to false by design.
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)
        controller.show()
        let manager = try XCTUnwrap(controller.webViewManager, "The overlay's manager must exist")
        return QuitStage(
            controller: controller,
            manager: manager,
            services: services,
            owner: owner,
            popups: manager.focusablePopups(for: owner)
        )
    }

    /// The relaunch leg: tears the quit stage down — its save already
    /// holds the state a quit writes — then builds and shows a fresh
    /// controller from that saved state, letting the deferred focus
    /// stages settle before the caller inspects the windows.
    private func relaunch(from quit: QuitStage) async throws -> MainWindowController {
        quit.cleanup()
        let controller = MainWindowController(services: quit.services)
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)
        controller.show()
        await settleFocusStages()
        return controller
    }

    private func cleanup(_ controller: MainWindowController, owner: TabIdentifier, services: [Service]) {
        controller.webViewManager?.focusablePopups(for: owner).forEach { $0.close() }
        controller.webViewManager?.removeWebView(for: services[0], sessionIndex: 0)
        controller.window?.orderOut(nil)
    }

    func testShowRestoresThePopupThatWasKeyBeforeTheHide() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            // The older popup is key — "popup A" — while a newer popup exists.
            try await makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.hide()
            stage.controller.show()
            await settleFocusStages()

            // Only judge the restore once focus actually arrived: a host
            // still withholding key status leaves every window of ours
            // unkeyed, which says nothing about which target the restore
            // picked. A grant that landed on the wrong window fails below.
            guard await waitForHostKeyGrant() else {
                throw XCTSkip("The test host refused key status")
            }
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

            try await makeKeyOrFail(stage.controller.window, reason: "the overlay")

            stage.controller.hide()
            stage.controller.show()
            await settleFocusStages()

            // Only judge the restore once focus actually arrived: a host
            // still withholding key status leaves every window of ours
            // unkeyed, which says nothing about which target the restore
            // picked. A grant that landed on the wrong window fails below.
            guard await waitForHostKeyGrant() else {
                throw XCTSkip("The test host refused key status")
            }
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

            try await makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.hide()
            stage.firstPopup.close()
            stage.controller.show()
            await settleFocusStages()

            // Only judge the restore once focus actually arrived: a host
            // still withholding key status leaves every window of ours
            // unkeyed, which says nothing about which target the restore
            // picked. A grant that landed on the wrong window fails below.
            guard await waitForHostKeyGrant() else {
                throw XCTSkip("The test host refused key status")
            }
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

            try await makeKeyOrFail(stage.controller.window, reason: "the overlay")

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

    func testFirstShowWithoutHistoryFocusesTheFrontmostPopup() async throws {
        try await withSettingsRestored {
            // The relaunch state: show() runs with no key history — nothing
            // held key before it — and the session's popups are on screen by
            // the time the deferred restore decides, exactly as launch
            // restoration leaves them.
            let stage = try await openStage()
            defer { stage.cleanup() }

            // Only judge the restore once focus actually arrived: a host
            // still withholding key status leaves every window of ours
            // unkeyed, which says nothing about which target the restore
            // picked. A grant that landed on the wrong window fails below.
            guard await waitForHostKeyGrant() else {
                throw XCTSkip("The test host refused key status")
            }
            XCTAssertTrue(
                stage.secondPopup.isKeyWindow,
                "The first show with no focus history must hand focus to the popup in front, not the overlay behind it"
            )
        }
    }

    func testSwitchingBackRestoresTheSessionsOwnKeyPopup() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            // The older popup is the session's active one before switching away.
            try await makeKeyOrFail(stage.firstPopup, reason: "the popup")

            stage.controller.switchSession(to: 1)
            stage.controller.switchSession(to: 0)
            await settleFocusStages()

            XCTAssertTrue(
                stage.firstPopup.isKeyWindow,
                "Switching back must restore the popup this session last had key, not the newest popup"
            )
        }
    }

    func testQuitWithTheOverlayFocusedReopensOnTheOverlay() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            XCTAssertEqual(quit.popups.count, 2, "The quit stage must restore both saved popups")

            // The user quits with the overlay focused while popups sit in
            // front of it — the case a frontmost-popup fallback would get
            // wrong.
            try await makeKeyOrFail(quit.controller.window, reason: "the overlay")
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .overlay,
                "Focusing the overlay must persist that choice for the next launch"
            )

            let relaunched = try await relaunch(from: quit)
            defer { cleanup(relaunched, owner: quit.owner, services: quit.services) }

            let restoredPopups = relaunched.webViewManager?.focusablePopups(for: quit.owner) ?? []
            XCTAssertEqual(restoredPopups.count, 2, "Both saved popups must come back")
            XCTAssertEqual(
                relaunched.window?.isKeyWindow, true,
                "Relaunch must key the overlay that held focus at quit, not a popup in front of it"
            )
            XCTAssertFalse(
                restoredPopups.contains(where: { $0.isKeyWindow }),
                "The popups in front must stay dim: focus belonged to the overlay at quit"
            )
        }
    }

    func testQuitWithTheOlderPopupFocusedReopensOnThatPopup() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            XCTAssertEqual(quit.popups.count, 2, "The quit stage must restore both saved popups")

            // The older popup is key at quit while a newer one sits in
            // front — the case a frontmost-popup fallback would get wrong.
            let older = try XCTUnwrap(quit.popups.first, "The older popup must exist")
            try await makeKeyOrFail(older, reason: "the popup")
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 0),
                "Focusing the popup must persist its owner and position among its siblings"
            )

            let relaunched = try await relaunch(from: quit)
            defer { cleanup(relaunched, owner: quit.owner, services: quit.services) }

            let restoredPopups = try XCTUnwrap(
                relaunched.webViewManager?.focusablePopups(for: quit.owner),
                "The relaunched overlay's manager must exist"
            )
            XCTAssertEqual(restoredPopups.count, 2, "Both saved popups must come back")
            let restoredOlder = try XCTUnwrap(restoredPopups.first, "The older popup must come back")
            let restoredInFront = try XCTUnwrap(restoredPopups.last, "The newer popup must come back")
            XCTAssertTrue(
                restoredOlder.isKeyWindow,
                "Relaunch must key the popup that held focus at quit — the older one, not the popup in front"
            )
            XCTAssertFalse(
                restoredInFront.isKeyWindow,
                "The popup in front must not steal the focus the older popup held at quit"
            )
        }
    }

    func testSavingFocusRecordsTheFocusedPopupsPositionAmongItsSiblings() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            XCTAssertEqual(quit.popups.count, 2, "The quit stage must restore both saved popups")

            // A popup behind no other — the one in front — must still
            // record its own rank, so the descriptor names one popup of
            // the session instead of collapsing onto the oldest. (Relaunch
            // focus for this record lands on the popup in front either
            // way, so the record itself is what this pins down.)
            let newer = try XCTUnwrap(quit.popups.last, "The newer popup must exist")
            try await makeKeyOrFail(newer, reason: "the newer popup")

            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 1),
                "The record must name which of the session's popups held focus, not just the session"
            )
        }
    }

    func testSavingFocusOnAPopupThatIsNotSavedLeavesNoRecord() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }

            // Seed a save target: with no saved state at all, the focus
            // save's early return would leave the record nil without ever
            // reaching the popup-exclusion path this pins down.
            Settings.shared.persistedTabState = PersistedTabState()

            // about:blank popups never reach the saved popup array, so
            // there is nothing to point a record at — the same path a
            // secure engine's popup takes by staying out of plaintext
            // state. With no record, relaunch falls back to the popup in
            // front instead of guessing.
            try await makeKeyOrFail(stage.firstPopup, reason: "the popup")

            XCTAssertNil(
                Settings.shared.persistedTabState?.keyWindow,
                "A popup excluded from the save must leave no focus record"
            )
        }
    }

    // MARK: - Settings as an interruption

    func testOpeningSettingsLeavesTheFocusRecordOnThePopup() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            let older = try XCTUnwrap(quit.popups.first, "The older popup must exist")
            try await makeKeyOrFail(older, reason: "the popup")
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 0),
                "The popup's own focus must be the record before Settings opens"
            )

            try await openSettingsOver(try XCTUnwrap(quit.controller.window, "The overlay must exist"))
            defer { KeyFocusGate.shared.orderOut(AppDelegate.sharedSettingsWindow) }

            XCTAssertTrue(
                AppDelegate.sharedSettingsWindow.isKeyWindow,
                "Settings must hold key status for the scenario to mean anything"
            )
            XCTAssertTrue(
                KeyFocusGate.shared.lastKeyWindow === older,
                "Opening Settings must not replace the recorded focus window: an interruption is not a choice"
            )
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 0),
                "Opening Settings must not re-aim the persisted descriptor away from the popup"
            )
        }
    }

    func testClosingSettingsHandsKeyBackToThePopupItInterrupted() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            let older = try XCTUnwrap(quit.popups.first, "The older popup must exist")
            try await makeKeyOrFail(older, reason: "the popup")
            try await openSettingsOver(try XCTUnwrap(quit.controller.window, "The overlay must exist"))
            defer { KeyFocusGate.shared.orderOut(AppDelegate.sharedSettingsWindow) }

            // The declaration App.swift's close handler makes while
            // Settings still holds key status.
            KeyFocusGate.shared.windowWillClose(AppDelegate.sharedSettingsWindow)

            XCTAssertFalse(
                AppDelegate.sharedSettingsWindow.isKeyWindow,
                "Closing Settings must give up key status"
            )
            XCTAssertTrue(
                older.isKeyWindow,
                "Closing Settings must hand key status back to the popup it interrupted, not to the overlay"
            )
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 0),
                "The hand-back must keep the persisted descriptor on the popup"
            )
        }
    }

    func testDismissingSettingsHandsKeyBackToThePopupItInterrupted() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            let older = try XCTUnwrap(quit.popups.first, "The older popup must exist")
            try await makeKeyOrFail(older, reason: "the popup")
            try await openSettingsOver(try XCTUnwrap(quit.controller.window, "The overlay must exist"))

            // The toggle path: one order-out that decides the successor
            // while Settings is still visible and still key.
            KeyFocusGate.shared.orderOut(AppDelegate.sharedSettingsWindow)

            XCTAssertFalse(
                AppDelegate.sharedSettingsWindow.isVisible,
                "The order-out must take Settings off the screen"
            )
            XCTAssertTrue(
                older.isKeyWindow,
                "Dismissing Settings must hand key status back to the popup it interrupted, with no bounce back to the departing window"
            )
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .popup(owner: quit.owner, occurrence: 0),
                "The hand-back must keep the persisted descriptor on the popup"
            )
        }
    }

    func testDismissingSettingsOverTheOverlayKeepsTheOverlayKey() async throws {
        try await withSettingsRestored {
            let stage = try await openStage()
            defer { stage.cleanup() }
            // A save target, so the overlay's own choice has somewhere to persist.
            Settings.shared.persistedTabState = PersistedTabState()
            let overlay = try XCTUnwrap(stage.controller.window, "The overlay must exist")
            try await makeKeyOrFail(overlay, reason: "the overlay")
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .overlay,
                "Focusing the overlay must persist that choice before Settings opens"
            )

            try await openSettingsOver(overlay)
            KeyFocusGate.shared.orderOut(AppDelegate.sharedSettingsWindow)

            XCTAssertFalse(
                AppDelegate.sharedSettingsWindow.isVisible,
                "The order-out must take Settings off the screen"
            )
            XCTAssertEqual(
                overlay.isKeyWindow, true,
                "Dismissing Settings over the overlay must re-key the overlay, exactly as before"
            )
            XCTAssertEqual(
                Settings.shared.persistedTabState?.keyWindow, .overlay,
                "The overlay's record must survive the interruption unchanged"
            )
        }
    }

    // MARK: - Owner-position record across restore passes

    func testALaterRestorePassMustNotDropTheLaunchPassPositionRecords() async throws {
        try await withSettingsRestored {
            let quit = try openQuitStage()
            defer { quit.cleanup() }
            XCTAssertEqual(quit.popups.count, 2, "The quit stage must restore both saved popups")
            let manager = quit.manager

            let launchNewer = try XCTUnwrap(
                manager.restoredPopupWindow(owner: quit.owner, occurrence: 1),
                "The launch restore must record the newer popup's owner position"
            )

            // The engine-unlock pass carries only its own popups. Its
            // record must merge into the launch pass's — a wholesale
            // write would drop the positions the launch descriptor has
            // not resolved yet.
            manager.restorePopups([
                PersistedPopupState(
                    serviceID: quit.owner.serviceID, sessionIndex: 0,
                    url: "https://popup.test/unlock-pass",
                    frameX: 90, frameY: 400, frameWidth: 480, frameHeight: 360
                )
            ])

            XCTAssertTrue(
                manager.restoredPopupWindow(owner: quit.owner, occurrence: 1) === launchNewer,
                "A later restore pass must keep the launch pass's owner-position records"
            )
            XCTAssertNotNil(
                manager.restoredPopupWindow(owner: quit.owner, occurrence: 0),
                "The later pass's own record must resolve"
            )
        }
    }
}
