# Settings Styling Standards

This document outlines the styling standards and guidelines for developers adding or modifying rows, sections, and controls in the Settings window.

---

## 1. State Observation & Re-rendering

SwiftUI does not automatically monitor changes to the `Settings.shared` singleton unless a view explicitly declares it as an observed object.

*   **Requirement:** Any custom view, view modifier, or custom row style that depends on `settingsColorStyle` or other settings parameters must declare:
    ```swift
    @ObservedObject private var settings = Settings.shared
    ```
    This ensures that when the user toggles settings options (such as Color Style), the UI instantly re-renders without requiring an application restart.

---

## 2. Dynamic Color Resolution (`settingsResolved`)

Quiper supports two color styles: **Colorful** (vibrant, accent-colored) and **Classic** (monochrome gray).

*   **Standard:** All settings accent and icon colors must be dynamically resolved using:
    ```swift
    Color.settingsResolved
    ```
    *   Under **Classic** mode, this resolves any non-red color to `.secondary` gray.
    *   Under **Colorful** mode, it preserves the original custom color (e.g., `.blue`, `.purple`, `.teal`).
*   **Danger Zone Exception:** Warning elements (warning icons, critical actions, danger header text) must remain explicitly `.red` under both styles to guarantee high warning visibility. Do not apply `settingsResolved` to Danger Zone highlights.

---

## 3. Schematic Graphics over Native Controls

For pickers and configuration settings (e.g., Dock Visibility, Toolbar Visibility, Tab Layout, Color Scheme):
*   Avoid using raw macOS native dropdowns (`Picker`) or naked segmented controls.
*   **Design Pattern:** Build custom selection card buttons that display a miniature graphical layout representation (schematic graphic) of the window/screen state.
*   Apply the `.pickerCardStyle(isSelected:accentColor:)` modifier to these preview card containers.
*   *Note:* Schematic graphics representing specific states (like the Classic style vs Colorful style selector itself) should remain fixed in their preview colors so the user knows what each mode represents.

---

## 4. Custom Checkboxes (macOS Workaround)

Standard macOS native checkbox toggles (`.toggleStyle(.checkbox)`) do not reliably support custom colors via `.tint` or `.accentColor` and often glitch, rendering with solid black backgrounds.

*   **Standard:** Use SF Symbol-based custom toggles for all checkboxes in settings:
    ```swift
    Toggle("Label", isOn: $value)
        .toggleStyle(.coloredCheckbox(color))
    ```
    This renders a clean, customizable checkmark box matching the specified accent color (or secondary gray in Classic mode).

---

## 5. Action Button Legibility

Ensure primary action buttons remain readable and do not blend into low-contrast background colors:
*   Prominent buttons (such as "Check for Updates" or destructive buttons in the Danger Zone) must preserve their prominent color tints (e.g., blue or red) under both Classic and Colorful styles to ensure high contrast, readability, and clickability.

---

## 6. List Labeled Control Rows (Shortcuts tab)

For Settings **List** rows that show a title + caption on the left and a control (switch, shortcut button, badge + switch) on the right:

*   **Standard:** Use `SettingsLabeledControlRow` from `SettingsComponents.swift`. Do **not** hand-roll `HStack` + fixed label widths.
*   Use `labelWidth: .standard` (default) for a single trailing control; use `.compact` when the trailing side has primary + alternate controls.
*   Label column widths live only on `SettingsLabeledControlRow.LabelWidth`—change them there, not at call sites.
