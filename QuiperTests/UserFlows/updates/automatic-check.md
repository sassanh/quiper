# Automatic Update Check

**Goal**: Verify app automatically checks for updates in background.

1.  **Precondition**: "Automatically check for updates" is enabled in Settings.
2.  **Action**: App launches or runs for sufficient duration (12 hours).
3.  **Expected Result**:
    -   App queries GitHub API.
    -   If new version found: Prompts user with update dialog.
    -   Last checked timestamp is updated in Settings.
