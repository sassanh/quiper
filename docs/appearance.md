# Appearance Settings

Quiper allows you to customize the application’s visual style to match your desktop workspace theme. You can configure native window translucency (vibrancy), styling materials, and outer border outlines. 

> [!NOTE]
> Per-engine stylesheet customization (Custom CSS overrides) is configured on a per-engine basis. For details on customizing web layouts, see the [Managing Engines](engines.md#custom-css-injection) guide.

---

## Native Theme & Styling Settings

To customize Quiper's native frame and panel styling, open **Settings (`⌘ ⇧ ,`)** and navigate to the **Appearance** tab. 
You can customize styling properties for the **Light Theme** and **Dark Theme** independently, allowing the layout to adapt gracefully when your system changes modes.

## Selector Display

The engine and session selectors can be configured independently:

*   **Expanded:** Always displays every selector segment.
*   **Compact:** Displays the active segment and expands the selector when needed.
*   **Auto:** Uses the available window width to choose between Expanded and Compact.

Upgrading from an older version preserves the previous shared selector display choice for both selectors.

## Window Behavior

**Keep overlay on top** is enabled by default. Turn it off to let other applications cover Quiper like a normal window. Changing it takes effect immediately for the overlay, its blur backdrop, selector HUDs, and session popups without changing focus.

With this option off, the overlay shortcut shows the overlay when hidden and brings it forward while another application is frontmost; pressing it again while any Quiper window is focused — the overlay, a session popup, a HUD, Settings, or the update prompt — hides it. Settings and the update prompt attach to the overlay as child windows, so they switch to the same stacking while open. With it on, the existing show/hide shortcut behavior is unchanged. Web-page fullscreen handling, **Show on all spaces**, and the separate focus-loss settings are unchanged.

The preference survives relaunch and configuration export/import. Older configurations without it retain the default topmost behavior. iOS has no corresponding window setting, but preserves the preference when saving or exporting an imported configuration.


### 1. Color Scheme
Choose how Quiper behaves in light or dark modes:
*   **System (Default):** Dynamically matches your macOS System preferences.
*   **Light:** Keeps the app window and all loaded AI web views in light mode.
*   **Dark:** Keeps the app window and all loaded AI web views in dark mode.

### 2. Window Background Modes
Choose how the overlay window background behaves:
*   **macOS Effects (Vibrancy):** Enables native transparency effects. The window background is rendered using macOS's visual effects views, allowing your desktop wallpaper and background apps to blur through the overlay.
*   **Solid Color:** Disables translucency and fills the window background with a flat, solid hex color of your choosing.

### 3. Window Vibrancy Materials
When **macOS Effects** is active, you can select the native macOS material class used to render the vibrancy. These adjust how color and light pass through the background:

*   **Under Window Background:** Matches the material used behind standard windows. Highly opaque, heavily tinted.
*   **HUD:** A dark, high-contrast material typically used for heads-up-display panels.
*   **Popover:** Matches the light/dark translucent popovers in standard macOS apps.
*   **Menu / Sidebar:** Translates to the native sidebar or pulldown menu background texture.
*   **Header / Content:** Matches standard app window headers and content background frames.

### 4. Transparency, Blur, & Outlines
*   **Blur Radius:** Adjusts the density of the backdrop blur. Setting a higher value creates a smoother, more diffuse blur that isolates the window content, while lower values keep background shapes identifiable.
*   **Outline Width:** Sets the thickness of the overlay window border (e.g., `1.0px` for light, `1.5px` for dark).
*   **Outline Color:** Customize the border's color and alpha opacity. By default, light mode uses a thin dark outline (`alpha: 1.0`), whereas dark mode uses a bright, translucent white outline (`alpha: 0.40`) to make the window pop off dark wallpapers.
*   **Active vs. Inactive State:** The outline color automatically softens or shifts opacity when the overlay loses focus, visually indicating that Quiper is inactive.
