# External Navigation (External Links)

**Goal**: Verify links to different domains open in the default browser.

1.  **Precondition**: "LocalTest" service is active.
2.  **Action**: User clicks an **External Link** (`<a href="https://example.com">`) on the dummy page.
3.  **Expected Result**:
    -   WebView navigation is cancelled (URL remains `http://localhost:8000`).
    -   System default browser opens `https://example.com`.
