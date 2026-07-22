# Application Settings & Backups

This page covers application-wide preferences under **Settings (`⌘ ,`)** including runtime behavior, configuration backups, updates management, and the danger zone.

---

## Behavior Settings

These controls dictate how Quiper handles session cycling and engine switching during navigation:

### Automatically Switch Engines
*   **Description:** Determines behavior when you close the last open session slot of a service engine.
*   **Enabled:** When the last session of the active engine is closed, Quiper automatically switches focus to the nearest service engine that has active sessions open in memory.
*   **Disabled:** Focus remains on the empty active engine, prompting you to create a new session slot manually or switch engines.

### Auto-Create Session on Engine Activation
*   **Description:** Controls what happens when you navigate to an engine that has no active session slots open in memory.
*   **Enabled:** Quiper automatically creates a new session slot (Slot 1) immediately, launching the web view.
*   **Disabled:** Quiper displays the **Empty State screen**, presenting a summary of your active service engines, session counts, and keyboard shortcuts. No web view is initialized until you manually trigger session creation.

---

## Prompt History Settings

Quiper can maintain a local history of your sent prompts on a per-session basis, allowing you to quickly review, search, copy, or restore past inputs.

### Record Prompt History
*   **Description:** Globally enables or disables prompt recording for all engines and session slots.
*   **Prompt Recording Glow:** Shows a blue glow around the active prompt composer while recording is enabled. The glow is on by default and can be hidden without disabling prompt history.
*   **Triggers:** You can customize what specific actions trigger prompt recording:
    *   **On Submit / Enter:** Records the prompt when you hit Enter to submit it to the AI.
    *   **On Cmd+Enter:** Records the prompt when you submit via Command + Enter.
    *   **On Clear / Overwrite:** Records the prior prompt when it is cleared (via `Cmd+X` or `Backspace` on empty) or overwritten (typing/pasting after `Cmd+A` select-all).

---

## Configuration backups (Import/Export)

You can backup or migrate your entire Quiper setup (including all configured service engines, custom CSS layout injects, custom action scripts, and global hotkeys) into a single, encrypted `.quiper` file.

### Export Config
*   Click **Export** to select a target directory and save your configurations.
*   The output `.quiper` file is a serialized JSON file containing your engine variables and scripts.

### Import Config
*   Click **Import** to select and load an existing `.quiper` file.
*   > [!CAUTION]
    > Importing a configuration file completely overwrites your current engine list, CSS injects, and custom actions. It is recommended to export a backup of your existing setup before importing.

---

## Danger Zone

Global deletion controls for troubleshooting or completely resetting Quiper:

### Clear All Web Data
*   **Action:** Deletes all cookies, local databases, IndexedDB storage, and web caches for **every** configured engine.
*   **Use Case:** Clears corrupted login states or frees up disk space globally. All engines will behave as if loaded from a fresh browser profile.

### Erase All Engines
*   **Action:** Removes every configured service engine and deletes its associated custom CSS and JavaScript action scripts.
*   **Use Case:** Wipes the app clean to re-initialize your engine list from scratch.

### Erase All Actions
*   **Action:** Deletes every custom action definition and wipes all action scripts across all engines.

---

## Updates & Release Channels

Quiper handles updates natively, allowing you to check for releases directly from GitHub and choose how aggressively you receive new builds.

### Automated Checks & Downloads
*   **Automatically check for updates:** Periodically polls GitHub releases in the background. If a new version is found, a native notification is triggered.
*   **Automatically download updates:** Fetches the update package (DMG) in the background as soon as it is detected, making installation instant when you choose to restart the application.

### Update Channels
Quiper uses an **inclusive channel picker** slider. Moving the slider right unlocks more experimental versions:

1.  **Stable:** Official production-ready builds. Safe, thoroughly tested, and recommended for daily workflows.
2.  **Beta:** Stable builds + pre-releases (Beta builds). Ideal for users wanting early access to upcoming features.
3.  **Nightly:** Stable + Beta + Nightlies. Bleeding-edge builds compiled directly from development branches. Contains untested changes and potential bugs.
