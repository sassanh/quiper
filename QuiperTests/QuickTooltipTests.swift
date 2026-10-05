import XCTest
import AppKit
@testable import Quiper

/// QuickTooltip owns tooltip visibility; this pins its rule for the
/// anchor's window going away: closing it takes the tooltip with it,
/// and no other window's close may.
@MainActor
final class QuickTooltipTests: XCTestCase {

    private var liveWindows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        QuickTooltip.shared.hideImmediately()
    }

    override func tearDown() {
        QuickTooltip.shared.hideImmediately()
        liveWindows.removeAll()
        super.tearDown()
    }

    private func makeHostWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // AppKit's default releases the window on close while this test
        // still holds it in liveWindows — the same double-release the app's
        // own windows opt out of.
        window.isReleasedWhenClosed = false
        liveWindows.append(window)
        return window
    }

    /// A tooltip can only be exited by hovering out of its anchor; once
    /// the anchor's window closes, nothing will ever deliver that exit —
    /// the tooltip must hide with the window instead of dangling over
    /// empty space until an unrelated hover replaces it.
    func testClosingTheAnchorsWindowHidesTheTooltip() {
        let window = makeHostWindow()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        window.contentView?.addSubview(anchor)

        QuickTooltip.shared.show("Close Window", for: anchor)
        XCTAssertEqual(
            QuickTooltip.shared.alphaValue, 1,
            "The tooltip must be up before its window closes"
        )

        window.close()

        XCTAssertEqual(
            QuickTooltip.shared.alphaValue, 0,
            "Closing the anchor's window must take its tooltip down"
        )
        XCTAssertFalse(
            QuickTooltip.shared.isVisible,
            "A closed window's tooltip must be off screen, not merely faded"
        )
    }

    /// Another window closing is nobody's business here: the tooltip
    /// stays with its own anchor.
    func testAnUnrelatedWindowsCloseLeavesTheTooltipUp() {
        let anchorWindow = makeHostWindow()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        anchorWindow.contentView?.addSubview(anchor)
        let bystander = makeHostWindow()

        QuickTooltip.shared.show("Close Window", for: anchor)
        bystander.close()

        XCTAssertEqual(
            QuickTooltip.shared.alphaValue, 1,
            "An unrelated window's close must not hide this tooltip"
        )
    }
}
