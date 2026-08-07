# Setting Up Gemini

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working Gemini inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, Gemini works.** It covers the full path, from installing Quiper (if you don't have it) to creating a Google account (if you don't have one) to signing in inside the overlay.

> [!NOTE]
> Google ships its own Gemini app for Mac (Apple Silicon, macOS 15+), a first-party native client with OS-level features like voice, screen sharing, and local file access. It's a great option if you only need Gemini. This guide is for running Gemini inside Quiper, where it shares an overlay with your other engines — see [Comparing the two options](/blog/gemini-native-macos#comparing-the-two-options) on the blog to decide which fits you.

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Create a Google account (only if you don't have one)](#3-create-a-google-account-only-if-you-dont-have-one)
- [4. Open Gemini in Quiper](#4-open-gemini-in-quiper)
- [5. Sign in to Google inside Quiper](#5-sign-in-to-google-inside-quiper)
- [6. Verify Gemini works](#6-verify-gemini-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see Gemini | [Step 4: Open Gemini in Quiper](#4-open-gemini-in-quiper) |
| Don't have a Google account | [Step 3: Create a Google account](#3-create-a-google-account-only-if-you-dont-have-one) |
| Already signed in to Gemini | Skip ahead to [Verify Gemini works](#6-verify-gemini-works) |

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
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when a Gemini generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting). If you also use Google's Gemini app for Mac, rebind one of the two apps — both default to `⌥ Space`.
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Create a Google account (only if you don't have one)

Gemini runs on your Google account. If you already use Gmail, YouTube, or any Google service, skip this step.

1.  Open the [Google account sign-up page](https://accounts.google.com/signup) in your browser.
2.  Follow the flow: enter your first and last name, choose a username and password, and add a phone number for verification.
3.  Agree to Google's terms to finish creating the account.

You can also create an account later from inside Quiper — the sign-in screen (next step) offers a **Create account** link.

---

## 4. Open Gemini in Quiper

Gemini ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Press **`⌥ Space`** to open the overlay.
2.  Click the **Gemini** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to Gemini.)
3.  A session tab opens and Quiper automatically places the keyboard cursor inside Gemini's prompt field, ready to type.

> [!NOTE]
> **Don't see a Gemini tab?** On a fresh install all default engines are preloaded, but if Gemini was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, set the name to `Gemini` and the URL to `https://gemini.google.com?referrer=https://github.io/sassanh/quiper`, then save. See [Managing Engines](../engines) for the focus selector and custom CSS defaults.

---

## 5. Sign in to Google inside Quiper

You sign in directly to Google from inside the overlay — Quiper never sees or stores your Google password.

1.  With the Gemini tab open, click **Sign in** (or **Continue with Google**).
2.  Quiper keeps the `accounts.google.com` login flow **inside** the overlay via a built-in routing rule, so you won't be bounced out to a browser.
3.  Enter the email address and password for your Google account.
4.  If you have **2-Step Verification** enabled, complete it here too — you can use a prompt, authenticator app, or backup code. If you're on a device where you're already signed in to Chrome or Safari, Google may offer a one-tap confirmation instead.
5.  Complete any remaining Google steps — account chooser, security check, or recovery confirmation — and you'll land on the Gemini chat page.

Once signed in, the Gemini chat interface loads inside the overlay and stays signed in across sessions.

---

## 6. Verify Gemini works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the Gemini tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means Gemini is fully working in Quiper.

### Optional refinements after sign-in

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate Gemini threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → Gemini → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock Gemini's local data behind Touch ID under **Settings → Engines → Gemini → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| `⌥ Space` opens Google's Gemini app instead (or fights with it) | Both apps default to the same shortcut. Rebind Quiper under **Settings → Shortcuts**, or change the hotkey in the Gemini Mac app. |
| Google sign-in bounces to Safari | The `accounts.google.com` **Internal** routing rule is missing or reordered. Add it back in **Settings → Engines → Gemini → Routing**. |
| No Gemini tab in the selector | Re-add the engine manually (see [Step 4](#4-open-gemini-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → Gemini → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
