# In-App Navigation (Internal Links)

**Goal**: Verify links to the same domain open within the overlay.

1.  **Precondition**: "LocalTest" service is active.
2.  **Action**: User clicks an **Internal Link** (`<a href="/subpage">`) on the dummy page.
3.  **Expected Result**:
    -   WebView navigates to `http://localhost:8000/subpage`.
    -   App does **not** open the external default browser.
    -   Overlay remains visible.
