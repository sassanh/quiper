# Unify Shortcut Button Styling

## Goal

Unify the visual design and behavior of all shortcut recording buttons across the application. Currently there are inconsistencies:
- Some buttons are blue (`.borderedProminent`), some are gray badges
- Some have separate "Reset"/"Clear" buttons outside, some have embedded circle reset buttons
- Different styling approaches in different views

## User Review Required

> [!IMPORTANT]
> **Design Decision**: I propose using the gray badge design with embedded reset button (currently in `ActionsSettingsView`) as the unified standard because:
> - More compact and clean
> - Embedded reset button appears only when needed
> - Consistent with modern macOS design patterns
> - Already used for the majority of shortcuts in the app
>
> Alternative would be to use blue buttons with separate reset/clear buttons (current Global/Service shortcut style).

## Proposed Changes

### [NEW] [ShortcutButton.swift](file:///Users/sassanharadji/tmp/macos-ai-overlay/Sources/Quiper/ShortcutButton.swift)

Create a new reusable component file containing:
- `ShortcutButton`: Main component for displaying/recording shortcuts
- `ShortcutButtonStyle`: Style configuration (similar to existing `ShortcutBadge` but with improved naming)

This component will:
- Display current shortcut in monospaced font or placeholder text
- Show embedded reset button (circle with arrow) when shortcut is set
- Handle tap to start recording
- Handle reset action
- Support optional/disabled state

---

### [MODIFY] [SettingsView.swift](file:///Users/sassanharadji/tmp/macos-ai-overlay/Sources/Quiper/SettingsView.swift)

#### Global Shortcut (GeneralSettingsView)
Replace current blue button + separate reset button with unified `ShortcutButton`:
- Lines ~64-75: Replace HStack with Button pattern
- Use `ShortcutButton` component
- Remove separate "Reset to ⌥Space" button
- Reset action embedded in the button

#### Service Launch Shortcut (ServiceDetailView) 
Replace current blue button + separate clear button with unified `ShortcutButton`:
- Lines ~583-595: Replace HStack with Button pattern  
- Use `ShortcutButton` component
- Remove separate "Clear" button
- Clear action embedded in the button (appears as reset icon)

---

### [MODIFY] [ActionsSettingsView.swift](file:///Users/sassanharadji/tmp/macos-ai-overlay/Sources/Quiper/ActionsSettingsView.swift)

#### Move Components to ShortcutButton.swift
- Move `ShortcutBadge` (lines 337-376) → `ShortcutButton.swift` (renamed/refactored)
- Move `LabeledBadge` (lines 378-400) → `ShortcutButton.swift` (made public)
- Keep `AppShortcutRow` and `DigitModifierRow` in this file (they use the new components)

#### Update References
- Update all references to use new component names from `ShortcutButton.swift`

## Verification Plan

### Manual Verification
Ask the user to test:
1. **Global Shortcut** (General tab): Click badge, record shortcut, verify embedded reset button works
2. **Service Launch Shortcut** (Engines tab → pick a service): Click badge, record shortcut, verify embedded reset/clear button works  
3. **Custom Action Shortcuts** (Shortcuts tab): Verify existing behavior still works
4. **App Shortcuts** (Shortcuts tab): Verify existing behavior still works
5. **Modifier Shortcuts** (Shortcuts tab): Verify existing behavior still works
6. Visual consistency: All shortcut buttons should now look identical (gray badges with embedded reset when set)
