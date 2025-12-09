import XCTest
import SwiftUI
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    func testDefaultNavigationShortcutsAreValid() {
        // Verify that default navigation shortcuts are properly configured
        let defaults = AppShortcutBindings.defaults
        
        // Next session should be Cmd+Shift+→
        let nextSession = defaults.configuration(for: .nextSession)
        XCTAssertEqual(nextSession.keyCode, UInt32(kVK_RightArrow))
        XCTAssertTrue(nextSession.modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0)
        XCTAssertTrue(nextSession.modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0)
        
        // Previous session should be Cmd+Shift+←
        let prevSession = defaults.configuration(for: .previousSession)
        XCTAssertEqual(prevSession.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertTrue(prevSession.modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0)
        XCTAssertTrue(prevSession.modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0)
        
        // Next service should be Cmd+Ctrl+→
        let nextService = defaults.configuration(for: .nextService)
        XCTAssertEqual(nextService.keyCode, UInt32(kVK_RightArrow))
        XCTAssertTrue(nextService.modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0)
        XCTAssertTrue(nextService.modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0)
    }
    
    func testAlternateVimStyleShortcutsExist() {
        // Verify vim-style H/L alternates are configured
        let defaults = AppShortcutBindings.defaults
        
        let altNext = defaults.alternateConfiguration(for: .nextSession)
        XCTAssertNotNil(altNext)
        XCTAssertEqual(altNext?.keyCode, UInt32(kVK_ANSI_L))
        
        let altPrev = defaults.alternateConfiguration(for: .previousSession)
        XCTAssertNotNil(altPrev)
        XCTAssertEqual(altPrev?.keyCode, UInt32(kVK_ANSI_H))
    }
    
    func testSessionDigitModifiersHaveDefaults() {
        // Verify that session switching has default modifiers configured
        let defaults = AppShortcutBindings.defaults
        
        // Primary session digits should have Command modifier
        XCTAssertTrue(defaults.sessionDigitsModifiers & NSEvent.ModifierFlags.command.rawValue != 0)
        
        // Service digits should have Command+Control
        XCTAssertTrue(defaults.serviceDigitsPrimaryModifiers & NSEvent.ModifierFlags.command.rawValue != 0)
        XCTAssertTrue(defaults.serviceDigitsPrimaryModifiers & NSEvent.ModifierFlags.control.rawValue != 0)
    }
    
    func testCustomActionHasRequiredFields() {
        // Verify that CustomAction has the essential fields for functionality
        let action = CustomAction(name: "Test Action")
        
        XCTAssertFalse(action.name.isEmpty)
        XCTAssertNotNil(action.id)
        XCTAssertNil(action.shortcut) // New actions start without shortcuts
    }
}
