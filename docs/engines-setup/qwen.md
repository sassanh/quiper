# Setting Up Qwen

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working Qwen inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, Qwen works.** It covers the full path, from installing Quiper (if you don't have it) to creating a Qwen account (if you don't have one) to signing in inside the overlay.

> [!NOTE]
> Qwen ships Qwen Studio on the web at [chat.qwen.ai](https://chat.qwen.ai) with mobile apps for iOS and Android and desktop downloads (see [qwen.ai](https://qwen.ai): "Ask Qwen, Know More" — "It's free to use, open to all" — and [Download Qwen](https://qwen.ai/download) for mobile and desktop builds). The consumer chat is free to use; building on Qwen through the developer API is billed separately through Alibaba Cloud Model Studio. This guide is for running `chat.qwen.ai` inside Quiper, where it shares an overlay with your other engines.

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Create a Qwen account (only if you don't have one)](#3-create-a-qwen-account-only-if-you-dont-have-one)
- [4. Open Qwen in Quiper](#4-open-qwen-in-quiper)
- [5. Sign in to Qwen inside Quiper](#5-sign-in-to-qwen-inside-quiper)
- [6. Verify Qwen works](#6-verify-qwen-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see Qwen | [Step 4: Open Qwen in Quiper](#4-open-qwen-in-quiper) |
| Don't have a Qwen account | [Step 3: Create a Qwen account](#3-create-a-qwen-account-only-if-you-dont-have-one) |
| Already signed in to Qwen | Skip ahead to [Verify Qwen works](#6-verify-qwen-works) |

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
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when a Qwen generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting).
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Create a Qwen account (only if you don't have one)

Qwen runs on your Qwen account at `chat.qwen.ai`. If you already use Qwen on the web or in the mobile app, skip this step.

1.  Open [chat.qwen.ai](https://chat.qwen.ai) in your browser.
2.  Click **Log in** / **Sign up** and follow the prompts to create your account. The exact verification steps (email or phone code, or a third-party sign-in) vary by region.
3.  Accept Qwen's Terms and Privacy Policy when asked. You will land in a fresh chat session.

You can also create an account later from inside Quiper — the sign-in screen in the next step offers the same **Sign up** path.

> [!TIP]
> Pick one sign-in method and stick with it across devices. Signing in with different methods can create separate accounts with separate histories.

---

## 4. Open Qwen in Quiper

Qwen ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Press **`⌥ Space`** to open the overlay.
2.  Click the **Qwen** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to Qwen.)
3.  A session tab opens and Quiper automatically places the keyboard cursor inside Qwen's prompt field, ready to type.

> [!NOTE]
> **Don't see a Qwen tab?** On a fresh install all default engines are preloaded, but if Qwen was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, set the name to `Qwen` and the URL to `https://chat.qwen.ai?referrer=https://github.io/sassanh/quiper`, then save. See [Managing Engines](../engines) for the focus selector (`.message-input-textarea, textarea[placeholder='How can I help you today?'], textarea`) and custom CSS defaults.

---

## 5. Sign in to Qwen inside Quiper

You sign in directly to Qwen from inside the overlay — Quiper never sees or stores your password.

1.  With the Qwen tab open, click **Log in** (top-left avatar area if you are signed out).
2.  Choose your sign-in method on the Qwen sign-in screen and complete the provider's flow. Quiper keeps the `accounts.google.com` and `github.com` OAuth flows **inside** the overlay via built-in routing rules, so you won't be bounced out to a browser.
3.  Complete any verification step Qwen asks for (code sent to your email or phone, where applicable).
4.  You will land on the Qwen chat page with the prompt box at the bottom. Your chat history syncs across `chat.qwen.ai` and the mobile and desktop apps on the same account.

Once signed in, Qwen stays signed in across Quiper sessions.

---

## 6. Verify Qwen works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the Qwen tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means Qwen is fully working in Quiper.

### Optional refinements after sign-in

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate Qwen threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → Qwen → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock Qwen's local data behind Touch ID under **Settings → Engines → Qwen → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| Google or GitHub sign-in bounces to Safari | The `accounts.google.com` or `github.com` **Internal** routing rule is missing or reordered. Add it back in **Settings → Engines → Qwen → Routing** (defaults: `^https?://([^/]*\.)?accounts\.google\.com(/\|$)` and `^https?://([^/]*\.)?github\.com(/\|$)` → **Internal**). |
| No Qwen tab in the selector | Re-add the engine manually (see [Step 4](#4-open-qwen-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → Qwen → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| No verification code email/SMS | Wait 60 seconds, request again, check spam; some disposable-email domains are blocked — try a primary mailbox. |
| "Already registered" or two histories | You created two accounts with different methods. Sign in with the original method everywhere. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
