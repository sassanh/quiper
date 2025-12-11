# Shortcut Conflict Detection

**Goal**: Verify that the application correctly detects and rejects shortcut assignments that conflict with existing shortcuts (Custom Actions, Global Hotkeys, System defaults).

1.  **Precondition**: 
    - Settings window is open.
    - App running with `--no-default-actions`.
2.  **Action (Setup)**:
    - Set Global Launch Shortcut (e.g. `Cmd+Shift+L`).
    - Create Custom Action A and assign valid shortcut `Cmd+Shift+K`.
    - Create Custom Action B (Target for testing).
3.  **Action (Test Conflicts)**:
    - Try to assign `Cmd+Shift+K` (Conflict with Action A).
    - Try to assign `Cmd+Shift+L` (Conflict with Global Launch).
    - Try to assign System Reserved keys (e.g. `Cmd+Opt+Escape`, `Cmd+Q`, `Cmd+W`).
    - Try to assign App Reserved keys (e.g. `Cmd+1`, `Cmd+Shift+Right`).
4.  **Expected Result**:
    - "ShortcutRecorderMessage" displays a conflict warning.
    - Recorder remains open (Assignment Rejected).
5.  **Action (Valid)**:
    - Assign a valid non-conflicting shortcut (e.g. `Cmd+I`).
6.  **Expected Result**:
    - Recorder closes.
    - UI updates with new shortcut.
7.  **Action (Idempotency)**:
    - Try to re-assign the SAME shortcut `Cmd+I` to the SAME action.
8.  **Expected Result**:
    - Recorder closes (Accepted as same-assignment).
