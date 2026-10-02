import XCTest
@testable import Quiper
import SwiftUI

@MainActor
final class WindowHierarchyTests: XCTestCase {
    
    func testHierarchyAndAppearanceSwitch() async throws {
        // Setup
        let controller = MainWindowController(services: [])
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 800, height: 600), display: false)
        controller.window?.orderFront(nil)
        defer { controller.window?.orderOut(nil) }
        
        // Ensure we start in macOS Effects mode to verify initial hierarchy contains effect view
        Settings.shared.windowAppearance.light.mode = .macOSEffects
        Settings.shared.windowAppearance.dark.mode = .macOSEffects
        NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // 1. Verify Hierarchy
        guard let container = controller.window?.contentView else {
            XCTFail("Window should have a content view")
            return
        }
        
        XCTAssertFalse(container is NSVisualEffectView, "Content view should be a plain NSView container, not NSVisualEffectView")
        XCTAssertTrue(container.wantsLayer, "Container should be layer-backed")
        
        // Find effect view
        let effectView = container.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView
        XCTAssertNotNil(effectView, "Container should have an NSVisualEffectView subview")
        
        // 2. Test Solid Color Mode
        let redColor = CodableColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        Settings.shared.windowAppearance.light.mode = .solidColor
        Settings.shared.windowAppearance.light.backgroundColor = redColor
        Settings.shared.windowAppearance.dark.mode = .solidColor
        Settings.shared.windowAppearance.dark.backgroundColor = redColor
        Settings.shared.colorScheme = .light

        NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000) // Wait for update
        
        XCTAssertTrue(effectView?.isHidden ?? false, "Effect view should be hidden in solid color mode")
        
        // In two-window architecture, the solid color is on the blurWindow's layer
        let blurWindow = controller.blurWindow
        XCTAssertNotNil(blurWindow, "blurWindow should exist")
        XCTAssertEqual(blurWindow?.contentView?.layer?.backgroundColor, NSColor.red.cgColor, "blurWindow content layer should have red background")
        
        // 3. Test Blur Mode
        Settings.shared.windowAppearance.light.mode = .macOSEffects
        Settings.shared.windowAppearance.light.material = .hudWindow
        
        NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertFalse(effectView?.isHidden ?? true, "Effect view should be visible in blur mode")
        // Container background is managed via applyWindowAppearance which sets win.backgroundColor = .clear
        // and container.layer?.backgroundColor = nil (or remains nil from setup)
        XCTAssertEqual(effectView?.material, .hudWindow, "Effect view should have correct material")
    }

    func testOverlayLevelChangesLiveWithoutTakingFocusOrDetachingChildren() throws {
        let settings = Settings.shared
        settings.wipeAllData()
        _ = settings.loadSettings()
        settings.keepOverlayOnTop = true
        let service = Service(name: "Level Test", url: "about:blank", focus_selector: "")
        let controller = MainWindowController(services: [service])
        let window = try XCTUnwrap(controller.window)
        defer {
            controller.hideTabHistoryHUD()
            controller.webViewManager?.hideAllSessionPopups()
            for child in window.childWindows ?? [] {
                if controller.webViewManager.isPopupWindow(child) {
                    child.close()
                }
                child.orderOut(nil)
            }
            // Popup cleanup schedules a focus handback; order out after that callback.
            DispatchQueue.main.async { window.orderOut(nil) }
            window.orderOut(nil)
            settings.wipeAllData()
        }
        controller.switchSession(to: 0)
        window.orderFront(nil)
        controller.applyWindowAppearance()
        controller.showTabHistoryHUD()
        let blur = try XCTUnwrap(controller.blurWindow)
        let hud = try XCTUnwrap(controller.tabHistoryHUDWindow)
        XCTAssertTrue(hud.isVisible)

        // Restoration creates the production popup without JavaScript timing or remote traffic.
        controller.webViewManager.restorePopups([
            PersistedPopupState(
                serviceID: service.id, sessionIndex: 0,
                url: "https://127.0.0.1:1/level-test",
                frameX: 100, frameY: 100, frameWidth: 300, frameHeight: 300
            )
        ])
        let popup = try XCTUnwrap(window.childWindows?.first {
            controller.webViewManager.isPopupWindow($0)
        })
        let originalKeyWindow = NSApp.keyWindow
        let originalActive = NSApp.isActive

        for (keepOnTop, level) in [(false, NSWindow.Level.normal), (true, .floating), (false, .normal)] {
            settings.keepOverlayOnTop = keepOnTop

            XCTAssertEqual(window.level, level)
            XCTAssertEqual(blur.level, level)
            XCTAssertEqual(hud.level, level)
            XCTAssertEqual(popup.level, level)
            XCTAssertTrue(blur.parent === window)
            XCTAssertTrue(hud.parent === window)
            XCTAssertTrue(popup.parent === window)
            XCTAssertTrue(window.isVisible)
            XCTAssertTrue(hud.isVisible)
            XCTAssertTrue(NSApp.keyWindow === originalKeyWindow)
            XCTAssertEqual(NSApp.isActive, originalActive)
        }
    }
}
