# Setting Up Grok

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working Grok inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, Grok works.** It covers the full path, from installing Quiper (if you don't have it) to creating an xAI account (if you don't have one) to signing in inside the overlay.

> [!NOTE]
> xAI ships Grok on the web at [grok.com](https://grok.com) and in the [iOS](https://apps.apple.com/app/apple-store/id6670324846) and [Android](https://play.google.com/store/apps/details?id=ai.x.grok) apps (see [x.ai/grok](https://x.ai/grok): "Available on Web, iOS and Android"). As of August 2026 there is no standalone consumer Grok app for macOS — the Mac app job listing and "native X and Grok apps for macOS are in development" reports refer to unreleased work, and the existing "Grok Bot" desktop app for macOS/Windows is a separate agentic product that requires an eligible plan (SuperGrok Plus, SuperGrok Heavy, etc.) and is not the chat assistant this guide sets up (see [docs.x.ai/grok-bot/get-started](https://docs.x.ai/grok-bot/get-started)). This guide is for running `grok.com` inside Quiper, where it shares an overlay with your other engines. Grok is free to start; paid SuperGrok plans raise limits and unlock more models and features (see [docs.x.ai/grok/overview](https://docs.x.ai/grok/overview) and [x.ai/pricing](https://x.ai/pricing)).

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Create an xAI account (only if you don't have one)](#3-create-an-xai-account-only-if-you-dont-have-one)
- [4. Open Grok in Quiper](#4-open-grok-in-quiper)
- [5. Sign in to Grok inside Quiper](#5-sign-in-to-grok-inside-quiper)
- [6. Verify Grok works](#6-verify-grok-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see Grok | [Step 4: Open Grok in Quiper](#4-open-grok-in-quiper) |
| Don't have an xAI/Grok account | [Step 3: Create an xAI account](#3-create-an-xai-account-only-if-you-dont-have-one) |
| Already signed in to Grok | Skip ahead to [Verify Grok works](#6-verify-grok-works) |

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
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when a Grok generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting).
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Create an xAI account (only if you don't have one)

Grok runs on your xAI account. If you already use Grok on the web or in the mobile apps, skip this step.

Grok's sign-in page offers four methods — **Continue with X**, **Continue with Google**, **Continue with Apple**, and **Continue with email** — all on the same xAI account system at `accounts.x.ai` (see [accounts.x.ai/sign-in?redirect=grok-com](https://accounts.x.ai/sign-in?redirect=grok-com): "Login with Google / Login with 𝕏 / Login with Apple / Login with email"). You only need one of them; you do not need an X Premium subscription and you do not need to have an X account if you prefer Google, Apple, or email. You can also link an X account later at `grok.com → Settings → Account → Connect your X Account`.

1.  Open [grok.com](https://grok.com) in your browser, or open the account sign-up directly at [accounts.x.ai/sign-up?redirect=grok-com](https://accounts.x.ai/sign-up?redirect=grok-com).
2.  Click **Sign up** and choose your preferred method: **X**, **Google**, **Apple**, or **email**. For email, enter your address and follow the verification code flow.
3.  Complete the confirmation step for that provider (X authorization, Google/Apple OAuth, or email code) and agree to xAI's terms to finish creating the account.
4.  If you signed up with email, you can later add X/Google/Apple as additional sign-in methods at [accounts.x.ai](https://accounts.x.ai).

You can also create an account later from inside Quiper — the sign-in screen in the next step offers the same **Sign up** link.

---

## 4. Open Grok in Quiper

Grok ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Press **`⌥ Space`** to open the overlay.
2.  Click the **Grok** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to Grok.)
3.  A session tab opens and Quiper automatically places the keyboard cursor inside Grok's prompt field, ready to type.

> [!NOTE]
> **Don't see a Grok tab?** On a fresh install all default engines are preloaded, but if Grok was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, set the name to `Grok` and the URL to `https://grok.com?referrer=https://github.io/sassanh/quiper`, then save. See [Managing Engines](../engines) for the focus selector (`textarea[aria-label='Ask Grok anything'], textarea, div[contenteditable='true']`) and custom CSS defaults.

---

## 5. Sign in to Grok inside Quiper

You sign in directly to xAI from inside the overlay — Quiper never sees or stores your password.

1.  With the Grok tab open, click **Sign in**.
2.  Choose your sign-in method — **X**, **Google**, **Apple**, or **email** — and complete the provider's flow. Quiper keeps both the xAI account pages and the `accounts.google.com` and `x.com` login flows **inside** the overlay via built-in routing rules, so you won't be bounced out to a browser.
3.  If you chose **X**, authorize xAI to connect to your X account. If you chose **Google** or **Apple**, complete the OAuth consent screen. For **email**, enter the code sent to your inbox.
4.  Complete any remaining xAI steps — verification, profile setup, or subscription prompt (you can stay on the free tier) — and you'll land on the Grok chat page.

Once signed in, the Grok chat interface loads inside the overlay and stays signed in across sessions. Your conversations, settings, and subscription (if any) stay in sync across `grok.com` and the mobile apps on the same xAI account (see [docs.x.ai/grok/overview](https://docs.x.ai/grok/overview): "Sign in once and your conversations, settings, and subscription stay in sync across every platform").

---

## 6. Verify Grok works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the Grok tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means Grok is fully working in Quiper.

### Optional refinements after sign-in

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate Grok threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → Grok → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock Grok's local data behind Touch ID under **Settings → Engines → Grok → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| X or Google sign-in bounces to Safari | The `x.com` or `accounts.google.com` **Internal** routing rule is missing or reordered. Add it back in **Settings → Engines → Grok → Routing** (defaults: `^https?://([^/]*\.)?x\.com(/\|$)` and `^https?://([^/]*\.)?accounts\.google\.com(/\|$)` → **Internal**). |
| No Grok tab in the selector | Re-add the engine manually (see [Step 4](#4-open-grok-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → Grok → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |
| Sign-in loops or shows the wrong account | You signed in with a different provider than the one that owns the subscription (Apple vs. Google vs. X vs. email create separate identities). Sign out in the overlay and sign in again with the original provider, or link providers at [accounts.x.ai](https://accounts.x.ai). See [docs.x.ai/grok/faq](https://docs.x.ai/grok/faq) (weekly usage, billing, and account linking). |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
