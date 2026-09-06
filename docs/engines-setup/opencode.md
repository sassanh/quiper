# Setting Up OpenCode

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working OpenCode inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, OpenCode works.** It covers the full path, from installing Quiper (if you don't have it) to installing OpenCode and starting its local web server (if you haven't) to opening it inside the overlay.

> [!NOTE]
> OpenCode is an open-source AI coding agent that runs on your own machine ([opencode.ai](https://opencode.ai)). Quiper embeds its local web interface. OpenCode needs a configured model provider to answer, and its server must be running for the engine tab to load. This guide runs `http://127.0.0.1:4096` inside Quiper, where OpenCode shares an overlay with your other engines.

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Install OpenCode and start its server (only if you haven't)](#3-install-opencode-and-start-its-server-only-if-you-havent)
- [4. Open OpenCode in Quiper](#4-open-opencode-in-quiper)
- [5. Verify OpenCode works](#5-verify-opencode-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see OpenCode | [Step 4: Open OpenCode in Quiper](#4-open-opencode-in-quiper) |
| Haven't installed OpenCode | [Step 3: Install OpenCode and start its server](#3-install-opencode-and-start-its-server-only-if-you-havent) |
| OpenCode tab shows a connection error | Start the server ([Step 3](#3-install-opencode-and-start-its-server-only-if-you-havent)), then reload with `⌘ R` |

---

## 1. Install Quiper

**Requirements:** macOS 14.0 (Sonoma) or newer. No other hardware requirements.

1.  Download the latest disk image from the [releases page](https://github.com/sassanh/quiper/releases/latest) (`Quiper.dmg`).
2.  Double-click the downloaded `.dmg` to mount it.
3.  Drag **Quiper.app** into your **Applications** folder.
4.  (Optional but recommended) Verify the download came from this repository's CI:
    ```bash
    gh attestation verify Quiper.dmg --repo sassanh/quiper
    ```
5.  Double-click **Quiper.app** in Applications to launch it. If macOS warns about an app from an unidentified developer, open **System Settings → Privacy & Security** and click **Open Anyway**.

> [!TIP]
> Built Quiper from source or running the Debug build? The setup steps below are identical.

---

## 2. Launch Quiper

1.  Launch Quiper. It runs as a **menu-bar application** — you'll see its icon in the top-right menu bar. By default a Dock icon appears only while the overlay is open; set Dock visibility to Always or Never under **Settings (`⌘ ⇧ ,`) → Appearance**.
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when an OpenCode generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting).
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Install OpenCode and start its server (only if you haven't)

Quiper embeds OpenCode's local web interface, so the OpenCode server must be installed and running on your Mac. If your server is already running, skip ahead to [Step 4](#4-open-opencode-in-quiper).

1.  Install OpenCode with the install script (see [opencode.ai/docs](https://opencode.ai/docs/#install)):
    ```bash
    curl -fsSL https://opencode.ai/install | bash
    ```
    Alternatives: `npm install -g opencode-ai`, or on macOS `brew install anomalyco/tap/opencode`.
2.  OpenCode needs a configured model provider before it can answer. Run `opencode2` (v2) or `opencode` (v1) once in a terminal and use `/connect` to sign in and add a provider (see [opencode.ai/docs](https://opencode.ai/docs/#configure)). If you already use OpenCode in the terminal, skip this.
3.  In a terminal, change to the project directory you want OpenCode to work in and start the server on the port Quiper expects:
    ```bash
    cd /path/to/project
    opencode2 serve --port 4096  # OpenCode v2
    opencode web --port 4096     # OpenCode v1
    ```
    Quiper's template points at the fixed `http://127.0.0.1:4096` — v2 uses that port by default, while v1 picks a random port unless you pass `--port 4096`.
4.  Leave that terminal running. Quiper loads the engine from this server, so quitting the terminal (or sleeping the Mac) disconnects the OpenCode tab until you start it again.

> [!TIP]
> To protect the server with a password, prefix either start command with `OPENCODE_SERVER_PASSWORD=secret` (see [opencode.ai/docs/web](https://opencode.ai/docs/web/#authentication)). The user name defaults to `opencode` (override it with `OPENCODE_SERVER_USERNAME`). When you open the tab, Quiper shows a native sign-in sheet: enter your credentials, tick **Remember this password** to reuse them automatically, and click **Sign In** — one sign-in unlocks every OpenCode tab.

---

## 4. Open OpenCode in Quiper

OpenCode ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Make sure the server from [Step 3](#3-install-opencode-and-start-its-server-only-if-you-havent) is running.
2.  Press **`⌥ Space`** to open the overlay.
3.  Click the **OpenCode** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to OpenCode.)
4.  A session tab opens and Quiper automatically places the keyboard cursor inside OpenCode's prompt field, ready to type.

> [!NOTE]
> **Don't see an OpenCode tab?** On a fresh install all default engines are preloaded, but if OpenCode was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, set the name to `OpenCode` and the URL to `http://127.0.0.1:4096`, then save. See [Managing Engines](../engines) for the focus selector (`div[data-component='prompt-input'][contenteditable='true'], div[role='textbox'][contenteditable='true'], textarea, div[contenteditable='true']`) and custom CSS defaults.

---

## 5. Verify OpenCode works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the OpenCode tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means OpenCode is fully working in Quiper.

### Optional refinements

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate OpenCode threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → OpenCode → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock OpenCode's local data behind Touch ID under **Settings → Engines → OpenCode → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| OpenCode tab shows a connection error or blank page | The server isn't running. In a terminal, `cd` to your project and run `opencode2 serve --port 4096` (v2) or `opencode web --port 4096` (v1), then reload the tab with `⌘ R`. |
| The server says the port is in use | Another server already occupies 4096 — either stop it, or point the engine at its port in **Settings → Engines → OpenCode** (URL). |
| Sign-in sheet keeps reappearing | Wrong user name or password. The user name defaults to `opencode`; check `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` in the terminal you launched the server from. |
| Agent doesn't reply / asks for provider setup | No model provider is configured. Run `opencode2` (v2) or `opencode` (v1) in a terminal and use `/connect` to add one (see [opencode.ai/docs](https://opencode.ai/docs/#configure)), then reload the tab. |
| No OpenCode tab in the selector | Re-add the engine manually (see [Step 4](#4-open-opencode-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → OpenCode → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
