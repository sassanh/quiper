# Troubleshooting & Diagnostics

If you run into issues with shortcuts, stuck web views, or custom scripts inside Quiper, use this guide to identify and resolve the problem.

---

## 1. Global Hotkey Fails to Open the Overlay

If pressing `⌥ Space` (or your custom global hotkey) no longer summons the overlay window:
1.  Click the **Quiper** icon in your macOS status menu bar.
2.  Select **Settings** (or press `⌘ ,` if the app window is open).
3.  Go to the **Shortcuts** tab.
4.  Click the **Global Hotkey** capture box and press your preferred hotkey combination again to re-bind it.
5.  **macOS Accessibility Permissions:** Ensure Quiper has permission to monitor global keyboard events. Go to **System Settings ➔ Privacy & Security ➔ Accessibility** and verify that **Quiper** is enabled.

---

## 2. Notifications Never Appear

If you don't receive notifications when generations complete in the background:
1.  Click the Quiper menu bar icon and select **Open Notification Settings**.
2.  This opens macOS **System Settings ➔ Notifications**.
3.  Scroll down to find **Quiper** (or **QuiperDev** in development builds).
4.  Ensure that **Allow Notifications** is toggled ON and set the alert style to **Banners** or **Alerts**.

---

## 3. Web View is Stuck, Stale, or blank

If a specific engine's layout is broken or displaying a stale page:
*   **Reload page:** Press **`⌘ R`** to refresh.
*   **Hard Reload:** Press **`⌘ ⌥ R`** to reload the view, bypassing the local cache.
*   **Re-instantiate Web View:** Right-click the active session tab and select **Reinstantiate Web View** to reload the target URL fresh.
*   **Wipe Web Data:** Click the Quiper menu bar icon and select **Clear All Web Data**. This will clear all WKWebView cache, localStorage, and session cookies across all unencrypted engines without resetting your settings configuration.

---

## 4. Custom Action Fails (Error Beep)

If triggering a Custom Action results in a system beep:
1.  Open the active engine view.
2.  Press **`⌘ ⌥ I`** to open the **Web Inspector**.
3.  Click the **Console** tab in the inspector window.
4.  Trigger the Custom Action again.
5.  Look for error messages. Quiper catches script errors and logs them to the web console (e.g. `[Quiper] Custom action script failed (error): ...`).
6.  Ensure that target CSS elements have not changed on the provider's website. If they did, update your selector paths in Settings.

---

## 5. Full Reset of Settings & Data

If your settings file becomes corrupted or you want to start completely fresh:
1.  Quit Quiper completely (Click Menu Bar Icon ➔ **Quit**).
2.  Open **Finder** and press **`⌘ ⇧ G`** (Go to Folder).
3.  Enter the target path:
    *   **Stable Build:** `~/Library/Application Support/app.sassanh.quiper.Quiper`
    *   **Debug/Development Build:** `~/Library/Application Support/app.sassanh.quiper.QuiperDev`
4.  Locate `settings.json` and delete it (or move it to your Desktop as a backup).
5.  **To reset encrypted volumes:** Delete the `EncryptedStores` folder in the same directory.
6.  Relaunch Quiper. It will generate a default configuration on start.

---

## 6. Compilation Errors (Build from Source)

If you get build errors inside Xcode or when running `./build-app.sh`:
*   Ensure you have installed the Xcode Command Line Tools. Run:
    ```bash
    xcode-select --install
    ```
*   Ensure your command line tools are pointed to the active Xcode version (requires Xcode 16.0+ for Swift 6.0 targets):
    ```bash
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
    ```
