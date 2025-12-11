# Custom Action Lifecycle

**Goal**: Verify that users can create custom actions, assign unique scripts per engine, execute them via global shortcuts, and handle errors gracefully.

1.  **Precondition**: 
    - App launched with `--test-custom-engines` and `--no-default-actions`.
2.  **Action (Create)**:
    - User creates a "Blank Action" in Settings > Shortcuts.
    - User assigns a global shortcut (`Cmd+Opt+Shift+K`).
3.  **Action (Scripting)**:
    - User navigates to Settings > Engines.
    - User selects Engine 1 and sets a valid script (`document.body.innerHTML = 'SUCCESS'`).
    - User selects Engine 2 and sets an error script (`throw new Error('FAIL')`).
4.  **Action (Execute Valid)**:
    - User activates Engine 1.
    - User triggers the shortcut.
5.  **Expected Result**:
    - The active page updates (`SUCCESS` text appears).
6.  **Action (Execute Error)**:
    - User activates Engine 2.
    - User triggers the shortcut.
7.  **Expected Result**:
    - The action fails silenty (no crash).
    - A "Beep" notification is posted internally (verified via DistributedNotificationCenter).
