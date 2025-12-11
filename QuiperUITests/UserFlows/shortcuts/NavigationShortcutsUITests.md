# Navigation Shortcuts Lifecycle

**Goal**: Verify internal navigation shortcuts (Session Next/Prev, Engine Next/Prev, Digits) work correctly for both Primary and Secondary assignments.

1.  **Precondition**: 
    - Settings window is open on "Shortcuts" tab.
    - Multiple engines and sessions are simulated.
2.  **Action (Assign)**: 
    - User assigns custom shortcuts to all navigation slots (Next/Prev Session, Next/Prev Engine, Digits).
3.  **Expected Result**:
    - Shortcuts are recorded.
    - Executing shortcuts modifies the active Session/Engine state as verified by the UI labels (`ServiceSelector`, `SessionSelector`).
4.  **Action (Clear)**:
    - User clears all custom shortcuts.
5.  **Expected Result**:
    - Custom shortcuts no longer trigger navigation.
6.  **Action (Reset)**:
    - User resets shortcuts to defaults.
7.  **Expected Result**:
    - Default keybindings (e.g. `Cmd+1`, `Cmd+Shift+Right`) correctly trigger navigation.
