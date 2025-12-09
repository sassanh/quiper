# Service Switching

**Goal**: Verify switching between services updates the view and focus.

1.  **Precondition**: App is visible, "LocalTest" service is active.
2.  **Action**: User triggers **Next Service** shortcut (e.g., `Cmd + Ctrl + Right`).
3.  **Expected Result**:
    -   Overlay switches to the next service (e.g., "Service B").
    -   Service B's URL is loaded.
    -   Service B's input field is focused.
4.  **Action**: User triggers **Previous Service** shortcut.
5.  **Expected Result**:
    -   Overlay switches back to "LocalTest".
    -   "LocalTest" input field is focused.
