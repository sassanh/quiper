# Launch Shortcuts Lifecycle

**Goal**: Verify global hotkeys for launching specific engines can be assigned, correctly executed to switch engines, and successfully cleared.

1.  **Precondition**: 
    - Settings window is open on "Shortcuts" tab.
    - Custom Engine 1-4 are available.
2.  **Action**: 
    - User expands engine row and clicks "Record Shortcut".
    - User types a unique key combination (e.g. `Cmd+Opt+Shift+A`).
3.  **Action (Verify)**:
    - User closes the Settings window.
    - User types the assigned global hotkey combination.
4.  **Expected Result**:
    - The app activates (if in background).
    - The active engine switches to the assigned Engine (verified via UI).
5.  **Action (Clear)**:
    - User re-opens Settings > Shortcuts.
    - User clicks the "Clear" (x) button.
6.  **Action (Verify Cleared)**:
    - User closes the Settings window.
    - User types the previously assigned key combinations.
7.  **Expected Result**:
    - Shortcut is removed.
    - Executing the key combination no longer switches the engine (State remains unchanged).
