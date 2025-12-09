## Focus After Load & Reload

**Goal:** After initial page load or any reload (manual ⌘R or programmatic), the active service’s focus selector is applied so the input becomes first responder.

**Preconditions**
- Quiper running.
- At least one service configured with a valid `focus_selector`.

**Flow**
1) Open Quiper; ensure the main window is visible.
2) Select a service that has a `focus_selector` pointing to a text input.
3) Wait for the page to finish loading.
4) Verify the cursor/focus is in the expected input (typing should appear there).
5) Press ⌘R to reload the page.
6) After reload completes, verify focus returns to the same input.

**Expected**
- Focus is placed in the target input after the initial load.
- Focus is restored after a reload without extra clicks.

**Notes**
- Applies regardless of how the page reload is triggered (toolbar reload, shortcut, or web process restart).
