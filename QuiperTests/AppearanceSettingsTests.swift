import Testing
import Foundation
import AppKit
@testable import Quiper

@MainActor
struct AppearanceSettingsTests {
    
    // MARK: - AppColorScheme Tests
    
    @Test func appColorScheme_RawValues() {
        #expect(AppColorScheme.system.rawValue == "System")
        #expect(AppColorScheme.light.rawValue == "Light")
        #expect(AppColorScheme.dark.rawValue == "Dark")
    }
    
    @Test func appColorScheme_nsAppearance() {
        #expect(AppColorScheme.system.nsAppearance == nil)
        #expect(AppColorScheme.light.nsAppearance?.name == .aqua)
        #expect(AppColorScheme.dark.nsAppearance?.name == .darkAqua)
    }
    
    @Test func appColorScheme_Codable() throws {
        for scheme in AppColorScheme.allCases {
            let data = try JSONEncoder().encode(scheme)
            let decoded = try JSONDecoder().decode(AppColorScheme.self, from: data)
            #expect(decoded == scheme)
        }
    }
    
    // MARK: - ThemeAppearanceSettings Tests
    
    @Test func themeAppearanceSettings_DefaultLight() {
        let settings = ThemeAppearanceSettings.defaultLight
        #expect(settings.mode == .solidColor)
        #expect(settings.material == .underWindowBackground)
        #expect(settings.backgroundColor.alpha == 0.60)
    }
    
    @Test func themeAppearanceSettings_DefaultDark() {
        let settings = ThemeAppearanceSettings.defaultDark
        #expect(settings.mode == .solidColor)
        #expect(settings.material == .underWindowBackground)
        #expect(settings.backgroundColor.alpha == 0.60)
    }
    
    @Test func themeAppearanceSettings_Codable() throws {
        let settings = ThemeAppearanceSettings(
            mode: .macOSEffects,
            material: .sidebar,
            backgroundColor: CodableColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8)
        )
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ThemeAppearanceSettings.self, from: data)
        
        #expect(decoded.mode == .macOSEffects)
        #expect(decoded.material == .sidebar)
        #expect(decoded.backgroundColor.red == 0.5)
        #expect(decoded.backgroundColor.alpha == 0.8)
    }
    
    // MARK: - WindowAppearanceSettings Tests
    
    @Test func windowAppearanceSettings_Default() {
        let settings = WindowAppearanceSettings.default
        #expect(settings.light == .defaultLight)
        #expect(settings.dark == .defaultDark)
    }
    
    @Test func windowAppearanceSettings_Codable() throws {
        var settings = WindowAppearanceSettings()
        settings.light.mode = .macOSEffects
        settings.light.material = .popover
        settings.dark.mode = .solidColor
        settings.dark.backgroundColor = CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9)
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WindowAppearanceSettings.self, from: data)
        
        #expect(decoded.light.mode == .macOSEffects)
        #expect(decoded.light.material == .popover)
        #expect(decoded.dark.mode == .solidColor)
        #expect(decoded.dark.backgroundColor.alpha == 0.9)
    }
    
    @Test func windowAppearanceSettings_LegacyMigration() throws {
        // Simulate legacy format (flat structure without light/dark)
        let legacyJSON = """
        {
            "mode": "Blur Effect",
            "material": "Sidebar",
            "backgroundColor": {"red": 0.2, "green": 0.3, "blue": 0.4, "alpha": 0.6}
        }
        """
        
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WindowAppearanceSettings.self, from: data)
        
        // Legacy settings should migrate to dark theme
        #expect(decoded.dark.mode == .macOSEffects)
        #expect(decoded.dark.material == .sidebar)
        #expect(decoded.dark.backgroundColor.alpha == 0.6)
        
        // Light theme should use defaults
        #expect(decoded.light.mode == .solidColor)
        #expect(decoded.light.material == .underWindowBackground)
    }
    
    // MARK: - WindowMaterial Tests
    
    @Test func windowMaterial_nsMaterialMapping() {
        #expect(WindowMaterial.underWindowBackground.nsMaterial == .underWindowBackground)
        #expect(WindowMaterial.sidebar.nsMaterial == .sidebar)
        #expect(WindowMaterial.hudWindow.nsMaterial == .hudWindow)
        #expect(WindowMaterial.popover.nsMaterial == .popover)
        #expect(WindowMaterial.menu.nsMaterial == .menu)
        #expect(WindowMaterial.headerView.nsMaterial == .headerView)
        #expect(WindowMaterial.contentBackground.nsMaterial == .contentBackground)
    }
    
    // MARK: - Settings Persistence Tests
    
    @Test func settings_ColorSchemePersistence() {
        let settings = Settings.shared
        let original = settings.colorScheme
        
        // Change and verify
        settings.colorScheme = .dark
        #expect(settings.colorScheme == .dark)
        
        settings.colorScheme = .light
        #expect(settings.colorScheme == .light)
        
        // Restore original
        settings.colorScheme = original
    }
    
    @Test func settings_WindowAppearancePersistence() {
        let settings = Settings.shared
        let original = settings.windowAppearance
        
        // Modify light theme
        settings.windowAppearance.light.mode = .macOSEffects
        settings.windowAppearance.light.material = .hudWindow
        #expect(settings.windowAppearance.light.mode == .macOSEffects)
        #expect(settings.windowAppearance.light.material == .hudWindow)
        
        // Modify dark theme
        settings.windowAppearance.dark.mode = .solidColor
        #expect(settings.windowAppearance.dark.mode == .solidColor)
        
        // Restore original
        settings.windowAppearance = original
    }
    
    @Test func settings_ResetIncludesColorScheme() {
        let settings = Settings.shared
        settings.colorScheme = .dark
        settings.windowAppearance.light.mode = .macOSEffects
        
        settings.reset()
        
        #expect(settings.colorScheme == .system)
        #expect(settings.windowAppearance == .default)
    }
    @Test func testCodableColor_InitFromNSColor() {
        // 1. Verify handling of component-based color (P3)
        // We just want to ensure it initializes and stores valid components
        let p3Color = NSColor(displayP3Red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let codableP3 = CodableColor(nsColor: p3Color)
        
        #expect(codableP3.red > 0.4 && codableP3.red < 0.6)
        #expect(codableP3.alpha == 1.0)
        
        // 2. Verify handling of dynamic/catalog colors (windowBackgroundColor)
        // Accessing components directly on dynamic colors often fails or returns 0 in some contexts
        // correct usage of usingColorSpace(.sRGB) ensures we get valid components.
        let dynamicColor = NSColor.windowBackgroundColor
        let codableDynamic = CodableColor(nsColor: dynamicColor)
        
        // Verify we got actual components (alpha usually 1.0 or non-zero for background)
        // Specific values depend on system appearance, but shouldn't crash and should be valid.
        #expect(codableDynamic.alpha > 0)
    }
}
