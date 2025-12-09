# Session Switching (Multi-WebView)

**Goal**: Verify multiple sessions (tabs) per service are maintained independently.

1.  **Precondition**: "LocalTest" service is active, Session 1 is visible.
2.  **Action**: User types "Session 1 Data" into the input.
3.  **Action**: User switches to **Session 2** (e.g., `Cmd + 2`).
4.  **Expected Result**:
    -   WebView for Session 2 is displayed (initially empty/default state).
    -   Input field is focused.
5.  **Action**: User switches back to **Session 1** (e.g., `Cmd + 1`).
6.  **Expected Result**:
    -   WebView for Session 1 is displayed.
    -   Input field still contains "Session 1 Data" (state preserved).
