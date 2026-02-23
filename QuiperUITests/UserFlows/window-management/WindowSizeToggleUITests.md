# Window Size Toggle

**Goal**: Verify that Cmd+M toggles between compact and previous window modes, restoring the prior frame correctly.

1.  **Precondition**:
    - App launched. Main window ("Quiper Overlay") is visible and focused.
2.  **Action (Toggle to compact)**:
    - User presses **Cmd+M**.
3.  **Expected Result**:
    - Window resizes to ~550×400.
    - Window repositions to the top-right corner of the screen.
4.  **Action (Toggle back)**:
    - User presses **Cmd+M** again.
5.  **Expected Result**:
    - Window restores to its previous size and position (width > 700).
6.  **Action (Multiple toggles)**:
    - User presses **Cmd+M** multiple times in sequence.
7.  **Expected Result**:
    - Each pair of toggles (compact → restored) leaves the window in its original frame.
    - No drift in position or size across repeated cycles.
8.  **Action (Toggle from moved position)**:
    - User drags the window to a new position, then presses **Cmd+M**.
9.  **Expected Result**:
    - Window toggles to compact mode regardless of where it was positioned.
    - Toggling back restores the dragged-to frame, not the original one.

