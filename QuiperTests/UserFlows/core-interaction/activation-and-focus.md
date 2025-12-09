# Activation & Focus

**Goal**: Verify the app activates and focuses the correct input field.

1.  **Precondition**: App is running, "LocalTest" service is active.
2.  **Action**: User triggers the **Global Hotkey** (e.g., `Option + Space`).
3.  **Expected Result**:
    -   Overlay window becomes visible.
    -   "LocalTest" WebView is displayed.
    -   The element matching `#prompt-textarea` is focused (verified via `document.activeElement` check).
