# Update Flow

**Goal**: Verify the automatic software update lifecycle, from prompt appearance to installation completion, using a mock update source.

1.  **Precondition**: 
    - App launched with `--enable-automatic-updates` and `--mock-update-available`.
2.  **Action**:
    - User launches the app and activates it (if hidden).
3.  **Expected Result**:
    - "Software Update" prompt appears automatically (`UpdatePromptMainView`).
4.  **Action**:
    - User clicks "Download Update".
5.  **Expected Result**:
    - UI changes to "Downloading update...".
    - Eventually shows "Install Update" button.
6.  **Action**:
    - User clicks "Install Update".
7.  **Expected Result**:
    - UI changes to "Installing update...".
    - Eventually shows "Relaunch Now" button, indicating success.
