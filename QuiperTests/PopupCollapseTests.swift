import XCTest
import AppKit
import WebKit
import Carbon
@testable import Quiper

/// The popup's minimize behavior: ⌘M and the toolbar's −/+ toggle collapse
/// the window to its toolbar strip alone, the strip's top edge never moves
/// while the width narrows about its center, and a minimized popup still
/// remembers itself as a real window — horizontally resizable, and
/// answerable as the head of its popup tree through the toggle's hold menu.
@MainActor
final class PopupCollapseTests: XCTestCase {

    // WebViewManager holds its container weakly; the test must retain it.
    private var liveContainers: [NSView] = []
    private var liveWindows: [NSWindow] = []

    private func makeService() -> Service {
        Service(name: "Collapse Engine", url: "https://example.com", focus_selector: "input")
    }

    private func makeHostWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        liveWindows.append(window)
        return window
    }

    private func makeSession(with service: Service, in window: NSWindow) -> WebViewManager {
        let originalServices = Settings.shared.services
        addTeardownBlock {
            Settings.shared.services = originalServices
        }
        Settings.shared.services = [service]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        liveContainers.append(container)
        window.contentView = container
        let manager = WebViewManager(containerView: container)
        manager.updateServices([service])
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: false
        )
        return manager
    }

    @MainActor
    private struct PopupFixture {
        let service: Service
        let hostWindow: NSWindow
        let manager: WebViewManager
        let popup: PopupWindow
        let toolbar: PopupToolbarView

        func tearDown() {
            manager.removeWebView(for: service, sessionIndex: 0)
            popup.close()
            hostWindow.close()
        }
    }

    private func makePopupFixture(file: StaticString = #filePath, line: UInt = #line) -> PopupFixture? {
        // The shared strip width is live app state that an interactive
        // resize rewrites; start every collapse fixture from the
        // documented default so tests stay independent of run order.
        PopupWindow.collapsedWidth = Constants.WINDOW_MIN_WIDTH
        let service = makeService()
        let hostWindow = makeHostWindow()
        let manager = makeSession(with: service, in: hostWindow)
        guard let session = manager.webviewsByID.first?.value.first?.value else {
            XCTFail("The session webview must exist", file: file, line: line)
            return nil
        }
        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: session)
        guard let popupWindow = NSApp.windows.first(where: { manager.isPopupWindow($0) }),
              let popup = popupWindow as? PopupWindow,
              let toolbar = popupWindow.contentView?.subviews.compactMap({ $0 as? PopupToolbarView }).first
        else {
            XCTFail("A popup with a toolbar must exist", file: file, line: line)
            return nil
        }
        return PopupFixture(
            service: service,
            hostWindow: hostWindow,
            manager: manager,
            popup: popup,
            toolbar: toolbar
        )
    }

    /// The toolbar's frame in screen coordinates — the position the user
    /// actually watches while the window minimizes.
    private func toolbarScreenFrame(_ toolbar: NSView, in window: NSWindow) -> NSRect {
        window.convertToScreen(toolbar.convert(toolbar.bounds, to: nil))
    }

    func testMinimizingShrinksToTheToolbarWithTheTopEdgeAnchored() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let originalFrame = popup.frame

        popup.setCollapsed(true, animated: false)

        XCTAssertTrue(popup.isCollapsed, "The window reports itself minimized to the toolbar")
        XCTAssertEqual(
            popup.frame.height,
            Constants.DRAGGABLE_AREA_HEIGHT,
            accuracy: 0.5,
            "Minimized leaves exactly the toolbar strip"
        )
        XCTAssertEqual(
            popup.frame.maxY,
            originalFrame.maxY,
            accuracy: 0.5,
            "The top edge is anchored, which is what keeps the toolbar from moving"
        )
        XCTAssertEqual(
            popup.frame.width,
            PopupWindow.collapsedWidth,
            accuracy: 0.5,
            "The strip takes the width every minimized window shares"
        )
        XCTAssertEqual(
            popup.frame.midX,
            originalFrame.midX,
            accuracy: 0.5,
            "It narrows about its center, so the strip never jumps sideways"
        )
        XCTAssertTrue(
            popup.styleMask.contains(.resizable),
            "Horizontal resizing stays possible while minimized"
        )
        XCTAssertEqual(
            popup.minSize.height,
            Constants.DRAGGABLE_AREA_HEIGHT,
            accuracy: 0.5,
            "A drag cannot push the strip below the toolbar"
        )
        XCTAssertEqual(
            popup.maxSize.height,
            Constants.DRAGGABLE_AREA_HEIGHT,
            accuracy: 0.5,
            "The ceiling agrees with the floor, so a drag cannot grow the height either"
        )
    }

    func testToolbarKeepsItsScreenPositionWhileThePopupMinimizes() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let toolbar = fixture.toolbar
        let before = toolbarScreenFrame(toolbar, in: popup)

        popup.setCollapsed(true, animated: false)
        let after = toolbarScreenFrame(toolbar, in: popup)

        XCTAssertEqual(after.origin.y, before.origin.y, accuracy: 0.5, "The toolbar never drops")
        XCTAssertEqual(after.maxY, before.maxY, accuracy: 0.5, "The toolbar never rises")
        XCTAssertEqual(after.midX, before.midX, accuracy: 0.5, "The strip narrows about its center: the toolbar never slides sideways")
        XCTAssertEqual(after.size.height, before.size.height, accuracy: 0.5, "The toolbar keeps its height")
    }

    func testExpandingRestoresTheHeightAndTheOrdinaryConstraints() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let originalFrame = popup.frame
        let originalMaxSize = popup.maxSize
        popup.setCollapsed(true, animated: false)

        popup.setCollapsed(false, animated: false)

        XCTAssertFalse(popup.isCollapsed, "The window reports itself restored")
        XCTAssertEqual(popup.frame.height, originalFrame.height, accuracy: 0.5, "The full page area returns")
        XCTAssertEqual(popup.frame.maxY, originalFrame.maxY, accuracy: 0.5, "Expansion is anchored the same way")
        XCTAssertEqual(
            popup.minSize.height,
            Constants.WINDOW_MIN_HEIGHT,
            accuracy: 0.5,
            "The ordinary minimum comes back with the expand"
        )
        XCTAssertEqual(
            popup.maxSize.height,
            originalMaxSize.height,
            accuracy: 0.5,
            "The ceiling the collapse captured goes back unchanged, so vertical resizing is free again"
        )
    }

    func testMinimizingTwiceIsANoOp() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        popup.setCollapsed(true, animated: false)
        let minimizedFrame = popup.frame

        popup.setCollapsed(true, animated: false)

        XCTAssertEqual(popup.frame, minimizedFrame, "Repeating the same state changes nothing")
    }

    func testAMinimizedPopupStillResizesHorizontally() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        popup.setCollapsed(true, animated: false)
        let pinnedHeight = popup.frame.height

        var wider = popup.frame
        wider.size.width += 240
        popup.setFrame(wider, display: false)

        XCTAssertEqual(
            popup.frame.width,
            wider.width,
            accuracy: 0.5,
            "The strip keeps the width range: horizontal resizing works while minimized"
        )
        XCTAssertEqual(
            popup.frame.height,
            pinnedHeight,
            accuracy: 0.5,
            "The height remains exactly the toolbar strip"
        )
        XCTAssertEqual(
            popup.maxSize.height,
            Constants.DRAGGABLE_AREA_HEIGHT,
            accuracy: 0.5,
            "The pinned bounds travel with the resized strip"
        )
    }

    func testTheHoldMenuCoversThisWindowAndItsNestedPopups() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let toolbar = fixture.toolbar
        let nested = PopupWindow(
            contentRect: NSRect(x: 160, y: 160, width: 420, height: 320),
            parentWindow: popup
        )
        defer { nested.close() }

        XCTAssertNotNil(
            toolbar.collapseButton.onLongPress,
            "Holding the minimize toggle opens the tree menu, like back/forward hold to list history"
        )

        let menu = toolbar.makeCollapseMenu()
        XCTAssertEqual(
            menu.items.map(\.title),
            ["Collapse All Children", "Expand All Children"],
            "The menu offers exactly the two tree actions"
        )
        XCTAssertNotNil(menu.items[0].image, "Collapse All Children carries an icon")
        XCTAssertNotNil(menu.items[1].image, "Expand All Children carries an icon")

        _ = NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0])
        XCTAssertTrue(popup.isCollapsed, "Collapse All Children minimizes the window it was opened on")
        XCTAssertTrue(nested.isCollapsed, "...and the popup nested under it")

        _ = NSApp.sendAction(menu.items[1].action!, to: menu.items[1].target, from: menu.items[1])
        XCTAssertFalse(popup.isCollapsed, "Expand All Children brings that window back")
        XCTAssertFalse(nested.isCollapsed, "The nested popup comes back with it")
    }

    func testMinimizeToggleSitsLeftOfCloseAndDrivesTheSameState() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let toolbar = fixture.toolbar

        toolbar.frame = NSRect(x: 0, y: 0, width: 480, height: 36)
        toolbar.layout()

        XCTAssertEqual(
            toolbar.collapseButton.frame.maxX,
            toolbar.closeButton.frame.minX - 4,
            accuracy: 0.5,
            "The minimize toggle sits immediately left of close"
        )
        XCTAssertLessThan(
            toolbar.refreshStopButton.frame.maxX,
            toolbar.collapseButton.frame.minX,
            "Refresh/stop stays left of the minimize toggle"
        )
        XCTAssertEqual(
            WindowCollapseButton.expandedSymbolName,
            "minus",
            "An expanded window offers −: clicking it minimizes"
        )
        XCTAssertEqual(
            WindowCollapseButton.collapsedSymbolName,
            "plus",
            "A minimized window offers +: clicking it restores"
        )
        XCTAssertNotEqual(
            WindowCollapseButton.expandedSymbolName,
            WindowCollapseButton.collapsedSymbolName,
            "The two states can never draw the same glyph"
        )

        toolbar.collapseButton.performClick(nil)
        XCTAssertTrue(popup.isCollapsed, "The toggle runs the same collapse the shortcut does")
        XCTAssertTrue(
            toolbar.collapseButton.isCollapsed,
            "The glyph flips with the window, from the same state"
        )
        XCTAssertEqual(
            toolbar.collapseButton.tooltipText,
            WindowCollapseButton.collapsedDescription,
            "The tooltip names the action the + now offers"
        )

        toolbar.collapseButton.performClick(nil)
        XCTAssertFalse(popup.isCollapsed, "Clicking again restores the window")
        XCTAssertEqual(
            toolbar.collapseButton.tooltipText,
            WindowCollapseButton.expandedDescription,
            "The tooltip follows the window back"
        )
    }

    func testAMinimizedPopupStillPersistsAsARealWindow() {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let originalFrame = popup.frame
        popup.setCollapsed(true, animated: false)

        let persisted = popup.persistedFrame

        XCTAssertEqual(
            persisted.height,
            originalFrame.height,
            accuracy: 0.5,
            "Relaunch restores the expanded height, never the toolbar strip"
        )
        XCTAssertEqual(
            persisted.maxY,
            originalFrame.maxY,
            accuracy: 0.5,
            "The stored rectangle is the one the window returns to"
        )
        XCTAssertEqual(persisted.width, originalFrame.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            persisted.height,
            200,
            "Above the restore validator's floor, so the position survives a relaunch"
        )
    }

    func testTheAnimatedTransitionSettlesOnTheSameFrames() async throws {
        guard let fixture = makePopupFixture() else { return }
        defer { fixture.tearDown() }
        let popup = fixture.popup
        let originalFrame = popup.frame
        let originalToolbarFrame = toolbarScreenFrame(fixture.toolbar, in: popup)

        popup.toggleCollapsed()
        // Mid-transition the strip must already hold its place. Sampling
        // lands either inside the animation or just after it — in both
        // cases the toolbar sits exactly where it started.
        try await Task.sleep(nanoseconds: 100_000_000)
        let midFlight = toolbarScreenFrame(fixture.toolbar, in: popup)
        XCTAssertEqual(
            midFlight.origin.y,
            originalToolbarFrame.origin.y,
            accuracy: 1,
            "The toolbar never moves while the window minimizes"
        )
        XCTAssertEqual(midFlight.midX, originalToolbarFrame.midX, accuracy: 1, "The center anchor holds through the animation too")
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(popup.isCollapsed)
        XCTAssertEqual(popup.frame.height, Constants.DRAGGABLE_AREA_HEIGHT, accuracy: 1, "The animation lands on the strip")
        XCTAssertEqual(popup.frame.maxY, originalFrame.maxY, accuracy: 1, "The top edge held through the animation")

        popup.toggleCollapsed()
        try await Task.sleep(nanoseconds: 100_000_000)
        let expanding = toolbarScreenFrame(fixture.toolbar, in: popup)
        XCTAssertEqual(
            expanding.origin.y,
            originalToolbarFrame.origin.y,
            accuracy: 1,
            "Expansion keeps the strip in place too"
        )
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(popup.isCollapsed)
        XCTAssertEqual(popup.frame.height, originalFrame.height, accuracy: 1, "The animation lands on the saved height")
        XCTAssertEqual(popup.frame.maxY, originalFrame.maxY, accuracy: 1, "Expansion kept the top edge too")
        XCTAssertEqual(
            popup.minSize.height,
            Constants.WINDOW_MIN_HEIGHT,
            accuracy: 0.5,
            "The completed expand hands the ordinary minimum back"
        )
    }

    func testCommandMinimizesTheFocusedPopupAndLeavesTheOverlayAlone() async throws {
        let originalServices = Settings.shared.services
        let originalBindings = Settings.shared.appShortcutBindings
        let originalFocusLoss = Settings.shared.focusLossEffectEnabled
        let originalOnboarding = Settings.shared.hasCompletedGhostOnboarding
        Settings.shared.focusLossEffectEnabled = false
        Settings.shared.hasCompletedGhostOnboarding = true
        Settings.shared.appShortcutBindings = .defaults
        defer {
            Settings.shared.services = originalServices
            Settings.shared.appShortcutBindings = originalBindings
            Settings.shared.focusLossEffectEnabled = originalFocusLoss
            Settings.shared.hasCompletedGhostOnboarding = originalOnboarding
        }

        let services = [Service(name: "Collapse Alpha", url: "https://alpha.test", focus_selector: "body")]
        Settings.shared.services = services
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        defer { controller.window?.orderOut(nil) }

        // Other tests' leftover windows must not short-circuit the focus gate.
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)

        controller.show()
        guard let manager = controller.webViewManager,
              let webView = controller.activeWebView else {
            XCTFail("The overlay's manager and tab must exist")
            return
        }

        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        guard let popupWindow = NSApp.windows.first(where: { manager.isPopupWindow($0) }),
              let popup = popupWindow as? PopupWindow else {
            XCTFail("A managed popup window must open")
            return
        }
        defer { manager.removeWebView(for: services[0], sessionIndex: 0) }
        defer { popupWindow.close() }

        NSApp.activate(ignoringOtherApps: true)
        popupWindow.makeKeyAndOrderFront(nil)
        guard popupWindow.isKeyWindow, controller.window?.isKeyWindow == false else {
            throw XCTSkip("The test host refused key status to the popup")
        }

        let overlayFrame = controller.window?.frame

        let handled = controller.handleCommandShortcut(event: commandKeyEvent())
        XCTAssertTrue(handled, "⌘M is always consumed while the overlay is up")
        XCTAssertTrue(popup.isCollapsed, "⌘M minimizes the popup that holds focus")
        XCTAssertEqual(
            controller.window?.frame,
            overlayFrame,
            "The overlay the user is not working in never moves"
        )

        let handledAgain = controller.handleCommandShortcut(event: commandKeyEvent())
        XCTAssertTrue(handledAgain)
        XCTAssertFalse(popup.isCollapsed, "Pressing ⌘M again restores that same popup")
        XCTAssertEqual(controller.window?.frame, overlayFrame, "Restoring also leaves the overlay alone")
    }

    private func commandKeyEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "m",
            charactersIgnoringModifiers: "m",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_M)
        )!
    }
}
