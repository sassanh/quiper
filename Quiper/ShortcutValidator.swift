import AppKit
import Carbon

enum ShortcutValidator {
    @MainActor
    static func allows(configuration: HotkeyManager.Configuration) -> Bool {
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags)
        let primary = modifiers.intersection([.command, .option, .control, .shift])
        let keyCode = UInt16(configuration.keyCode)

        if primary.isEmpty {
            return isFunctionKey(keyCode)
        }

        return reservedActionName(modifiers: primary, keyCode: keyCode) == nil
    }
    
    static func hasRequiredModifiers(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        let primary = modifiers.intersection([.command, .option, .control, .shift])
        if primary.isEmpty {
            return isFunctionKey(keyCode)
        }
        return true
    }

    @MainActor
    static func reservedActionName(modifiers rawModifiers: NSEvent.ModifierFlags, keyCode: UInt16, excludingActionId: UUID? = nil) -> String? {
        let modifiers = rawModifiers.intersection([.command, .option, .control, .shift])
        let config = HotkeyManager.Configuration(keyCode: UInt32(keyCode), modifierFlags: modifiers.rawValue)
        let settings = Settings.shared
        let bindings = settings.appShortcutBindings
        
        // 1. Dynamic System Shortcuts
        if config == settings.hotkeyConfiguration { return "Global Shortcut" }
        
        if let service = settings.services.first(where: { $0.activationShortcut == config }) {
            return "Activate \(service.name)"
        }
        
        // App Shortcuts
        if !bindings.nextSession.isDisabled, bindings.nextSession == config { return "Next Session" }
        if !bindings.previousSession.isDisabled, bindings.previousSession == config { return "Previous Session" }
        if !bindings.nextService.isDisabled, bindings.nextService == config { return "Next Engine" }
        if !bindings.previousService.isDisabled, bindings.previousService == config { return "Previous Engine" }
        if let alt = bindings.alternateNextSession, !alt.isDisabled, alt == config { return "Next Session (Alternate)" }
        if let alt = bindings.alternatePreviousSession, !alt.isDisabled, alt == config { return "Previous Session (Alternate)" }
        if let alt = bindings.alternateNextService, !alt.isDisabled, alt == config { return "Next Engine (Alternate)" }
        if let alt = bindings.alternatePreviousService, !alt.isDisabled, alt == config { return "Previous Engine (Alternate)" }
        
        // 2. Hardcoded System Shortcuts
        let hasCommand = modifiers.contains(.command)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)
        let hasShift = modifiers.contains(.shift)

        // Only proceed if at least Command is present
        guard hasCommand else {
             return nil
        }
        
        if keyCode == UInt16(kVK_ANSI_Comma) && !hasOption && !hasControl && !hasShift { // Settings (Cmd+,)
            return "Settings"
        }
        
        if keyCode == UInt16(kVK_ANSI_I) && hasOption && !hasControl && !hasShift { // Inspector (Cmd+Opt+I)
            return "Inspector"
        }
        
        if keyCode == UInt16(kVK_ANSI_Slash) && hasShift && !hasOption && !hasControl { // Shortcut Help (Cmd+Shift+/)
            return "Shortcut Help"
        }
        
        if keyCode == UInt16(kVK_ANSI_M) && hasOption && !hasControl && !hasShift { // Minimize Overlay (Cmd+Opt+M)
            return "Minimize Overlay"
        }
        
        if keyCode == UInt16(kVK_ANSI_Q) {
            if hasControl && hasCommand && hasShift && !hasOption { return "Quit" }
        }
        
        if (keyCode == UInt16(kVK_ANSI_Equal) || keyCode == UInt16(kVK_ANSI_KeypadPlus)) && !hasOption && !hasControl { // Zoom In (Cmd+=)
            return "Zoom In"
        }
        
        if (keyCode == UInt16(kVK_ANSI_Minus) || keyCode == UInt16(kVK_ANSI_KeypadMinus)) && !hasOption && !hasControl && !hasShift { // Zoom Out (Cmd+-)
            return "Zoom Out"
        }
        
        if (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)) && !hasOption && !hasControl && !hasShift { // Reset Zoom (Cmd+Delete)
             return "Reset Zoom"
        }
        
        // 3. Custom Actions
        if let conflict = settings.customActions.first(where: {
            guard let shortcut = $0.shortcut else { return false }
            if let excludedId = excludingActionId, $0.id == excludedId { return false }
            return shortcut == config
        }) {
             return "Used by \"\(conflict.name)\""
        }
        
        // 4. App Shortcuts
        if !bindings.nextSession.isDisabled, bindings.nextSession == config { return "Next Session" }
        if !bindings.previousSession.isDisabled, bindings.previousSession == config { return "Previous Session" }
        if !bindings.nextService.isDisabled, bindings.nextService == config { return "Next Engine" }
        if !bindings.previousService.isDisabled, bindings.previousService == config { return "Previous Engine" }
        if let alt = bindings.alternateNextSession, !alt.isDisabled, alt == config { return "Next Session (Alternate)" }
        if let alt = bindings.alternatePreviousSession, !alt.isDisabled, alt == config { return "Previous Session (Alternate)" }
        if let alt = bindings.alternateNextService, !alt.isDisabled, alt == config { return "Next Engine (Alternate)" }
        if let alt = bindings.alternatePreviousService, !alt.isDisabled, alt == config { return "Previous Engine (Alternate)" }
        
        // Session/Engine Digit Shortcuts
        if isDigitKey(keyCode) {
             let primaryModifiers = modifiers
             let sessionMods = NSEvent.ModifierFlags(rawValue: bindings.sessionDigitsModifiers)
             let sessionAltMods = bindings.sessionDigitsAlternateModifiers.map { NSEvent.ModifierFlags(rawValue: $0) }
             let servicePrimaryMods = NSEvent.ModifierFlags(rawValue: bindings.serviceDigitsPrimaryModifiers)
             let serviceSecondaryMods = bindings.serviceDigitsSecondaryModifiers.map { NSEvent.ModifierFlags(rawValue: $0) }
             
             let digit = digitValue(for: keyCode)
             if primaryModifiers == sessionMods { return "Go to Session \(digit)" }
             if let altMods = sessionAltMods, primaryModifiers == altMods { return "Go to Session \(digit) (Alternate)" }
             if primaryModifiers == servicePrimaryMods { return "Go to Engine \(digit)" }
             if let secMods = serviceSecondaryMods, primaryModifiers == secMods { return "Go to Engine \(digit) (Secondary)" }
        }
        

        
        return nil
    }
    
    private static func digitValue(for keyCode: UInt16) -> Int {
        if topRowDigits.contains(keyCode) {
            switch Int(keyCode) {
            case kVK_ANSI_0: return 0
            case kVK_ANSI_1: return 1
            case kVK_ANSI_2: return 2
            case kVK_ANSI_3: return 3
            case kVK_ANSI_4: return 4
            case kVK_ANSI_5: return 5
            case kVK_ANSI_6: return 6
            case kVK_ANSI_7: return 7
            case kVK_ANSI_8: return 8
            case kVK_ANSI_9: return 9
            default: return 0
            }
        }
        if keypadDigits.contains(keyCode) {
            switch Int(keyCode) {
            case kVK_ANSI_Keypad0: return 0
            case kVK_ANSI_Keypad1: return 1
            case kVK_ANSI_Keypad2: return 2
            case kVK_ANSI_Keypad3: return 3
            case kVK_ANSI_Keypad4: return 4
            case kVK_ANSI_Keypad5: return 5
            case kVK_ANSI_Keypad6: return 6
            case kVK_ANSI_Keypad7: return 7
            case kVK_ANSI_Keypad8: return 8
            case kVK_ANSI_Keypad9: return 9
            default: return 0
            }
        }
        return 0
    }

    static func isDigitKey(_ keyCode: UInt16) -> Bool {
        return topRowDigits.contains(keyCode) || keypadDigits.contains(keyCode)
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys.contains(keyCode)
    }

    private static let topRowDigits: Set<UInt16> = [
        UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
    ]

    private static let keypadDigits: Set<UInt16> = [
        UInt16(kVK_ANSI_Keypad0), UInt16(kVK_ANSI_Keypad1), UInt16(kVK_ANSI_Keypad2), UInt16(kVK_ANSI_Keypad3),
        UInt16(kVK_ANSI_Keypad4), UInt16(kVK_ANSI_Keypad5), UInt16(kVK_ANSI_Keypad6), UInt16(kVK_ANSI_Keypad7),
        UInt16(kVK_ANSI_Keypad8), UInt16(kVK_ANSI_Keypad9)
    ]

    private static let functionKeys: Set<UInt16> = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4), UInt16(kVK_F5),
        UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8), UInt16(kVK_F9), UInt16(kVK_F10),
        UInt16(kVK_F11), UInt16(kVK_F12), UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15),
        UInt16(kVK_F16), UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20)
    ]
}
