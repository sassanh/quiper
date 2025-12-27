import XCTest
@testable import Quiper
import SwiftUI

@MainActor
final class WindowHierarchyTests: XCTestCase {
    
    func testHierarchyAndAppearanceSwitch() async throws {
        // Setup
        let controller = MainWindowController(services: [])
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 800, height: 600), display: false)
        controller.window?.makeKeyAndOrderFront(nil)
        
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
        
        XCTAssertNil(effectView?.superview, "Effect view should be removed from hierarchy in solid color mode")
        XCTAssertEqual(container.layer?.backgroundColor, NSColor.red.cgColor, "Container layer should have red background")
        // XCTAssertEqual(controller.window?.backgroundColor, .clear, "Window background should be clear") // Assuming implementation details
        
        // 3. Test Blur Mode
        Settings.shared.windowAppearance.light.mode = .macOSEffects
        Settings.shared.windowAppearance.light.material = .hudWindow
        
        NotificationCenter.default.post(name: .windowAppearanceChanged, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertFalse(effectView?.isHidden ?? true, "Effect view should be visible in blur mode")
        XCTAssertEqual(container.layer?.backgroundColor, NSColor.clear.cgColor, "Container layer should be clear in blur mode")
        XCTAssertEqual(effectView?.material, .hudWindow, "Effect view should have correct material")
    }
}
