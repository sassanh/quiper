# Setting Up ChatGPT

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working ChatGPT inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, ChatGPT works.** It covers the full path, from installing Quiper (if you don't have it) to creating an OpenAI account (if you don't have one) to signing in inside the overlay.

> [!NOTE]
> OpenAI ships its own ChatGPT app for macOS alongside the web app at [chatgpt.com](https://chatgpt.com). It's a fine option if you only need ChatGPT. This guide is for running `chatgpt.com` inside Quiper, where it shares an overlay with your other engines. ChatGPT is free to start; paid plans raise usage limits on newer models.

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Create an OpenAI account (only if you don't have one)](#3-create-an-openai-account-only-if-you-dont-have-one)
- [4. Open ChatGPT in Quiper](#4-open-chatgpt-in-quiper)
- [5. Sign in to ChatGPT inside Quiper](#5-sign-in-to-chatgpt-inside-quiper)
- [6. Verify ChatGPT works](#6-verify-chatgpt-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see ChatGPT | [Step 4: Open ChatGPT in Quiper](#4-open-chatgpt-in-quiper) |
| Don't have an OpenAI account | [Step 3: Create an OpenAI account](#3-create-an-openai-account-only-if-you-dont-have-one) |
| Already signed in to ChatGPT | Skip ahead to [Verify ChatGPT works](#6-verify-chatgpt-works) |

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
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when a ChatGPT generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting). If you also use OpenAI's own ChatGPT app for Mac, it can claim `⌥ Space` too — rebind one of the two apps.
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Create an OpenAI account (only if you don't have one)

ChatGPT runs on your OpenAI account. If you already use ChatGPT on the web or in the desktop or mobile apps, skip this step.

Create your account at [chatgpt.com](https://chatgpt.com) — click **Sign up** and continue with **Google**, **Apple**, or your **email address**.

You can also create an account later from inside Quiper — the sign-in screen in the next step offers the same **Sign up** path.

---

## 4. Open ChatGPT in Quiper

ChatGPT ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Press **`⌥ Space`** to open the overlay.
2.  Click the **ChatGPT** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to ChatGPT.)
3.  A session tab opens and Quiper automatically places the keyboard cursor inside ChatGPT's prompt field, ready to type.

> [!NOTE]
> **Don't see a ChatGPT tab?** On a fresh install all default engines are preloaded, but if ChatGPT was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, choose **Blank**, set the name to `ChatGPT` and the URL to `https://chatgpt.com?referrer=https://github.io/sassanh/quiper`, then save. See [Managing Engines](../engines) for the focus selector (`#prompt-textarea, .ProseMirror[role='textbox'], textarea[name='prompt'], div[contenteditable='true'][role='textbox']`) and custom CSS defaults.

---

## 5. Sign in to ChatGPT inside Quiper

You sign in directly to OpenAI from inside the overlay — Quiper never sees or stores your password.

1.  With the ChatGPT tab open, click **Log in**.
2.  Choose your sign-in method — **Continue with Google**, **Continue with Apple**, or **email** — and complete it. Google and Apple open a consent screen: Quiper keeps the `accounts.google.com` and `appleid.apple.com` login flows **inside** the overlay via built-in routing rules, so **signing in with Google stays in the overlay** instead of bouncing you out to a browser. For email, enter your address and complete the verification OpenAI asks for — a code or link sent to your inbox, or your password.
3.  You'll land on the ChatGPT chat page with the prompt field at the bottom.

Once signed in, ChatGPT stays signed in across Quiper sessions, and your conversation history stays in sync with `chatgpt.com` on the same account.

---

## 6. Verify ChatGPT works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the ChatGPT tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means ChatGPT is fully working in Quiper.

### Optional refinements after sign-in

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate ChatGPT threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → ChatGPT → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock ChatGPT's local data behind Touch ID under **Settings → Engines → ChatGPT → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| `⌥ Space` opens OpenAI's ChatGPT app instead (or fights with it) | Rebind Quiper under **Settings → Shortcuts**, or change the hotkey in the ChatGPT app. |
| Google or Apple sign-in bounces to Safari | The `accounts.google.com` or `appleid.apple.com` **Internal** routing rule is missing or reordered. Add it back in **Settings → Engines → ChatGPT → Routing** (defaults: `^https?://([^/]*\.)?accounts\.google\.com(/\|$)` and `^https?://([^/]*\.)?appleid\.apple\.com(/\|$)` → **Internal**), or see [Keeping Sign-In Inside the Overlay](sign-in-routing.md) for right-click and ask-first alternatives. |
| No ChatGPT tab in the selector | Re-add the engine manually (see [Step 4](#4-open-chatgpt-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → ChatGPT → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| Sign-in email or code never arrives | Wait a minute and request again, and check spam — codes and links expire quickly. A login link you open in Safari signs you in there, not in the overlay's sandbox, so request a fresh one inside Quiper or use **Continue with Google/Apple**, which stay in the overlay. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
