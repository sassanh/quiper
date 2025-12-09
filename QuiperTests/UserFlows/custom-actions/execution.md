# Custom Actions Execution

**Goal**: Verify custom JavaScript actions (e.g., "New Session") execute correctly.

1.  **Precondition**: "LocalTest" service is active.
2.  **Action**: User triggers **New Session** custom action (e.g., `Cmd + N`).
3.  **System**: App injects the configured JS for "New Session" into the WebView.
    -   *Script*: `document.getElementById('new-chat-btn').click();`
4.  **Expected Result**:
    -   The "New Chat" button on the dummy site is clicked.
    -   The dummy site updates its status text to "New Chat Started".
    -   The test verifies this DOM change.
