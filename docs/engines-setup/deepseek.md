# Setting Up DeepSeek

[← All engines](../engines-setup)

This guide takes you from wherever you are right now to a working DeepSeek inside Quiper — no prior setup assumed. The goal is simple: **after you follow these steps, DeepSeek works.** It covers the full path, from installing Quiper (if you don't have it) to creating a DeepSeek account (if you don't have one) to signing in inside the overlay.

> [!NOTE]
> DeepSeek ships on the web at [chat.deepseek.com](https://chat.deepseek.com) and in the [iOS App Store](https://apps.apple.com/app/deepseek-ai-assistant/id6737597349) and [Google Play](https://play.google.com/store/apps/details?id=com.deepseek.chat) apps (see [deepseek.com](https://www.deepseek.com): "DeepSeek Web" at `chat.deepseek.com` and [Introducing DeepSeek App](https://www.deepseek.com/en/news/deepseek-app/): "Easy login: E-mail/Google Account/Apple ID" and "100% FREE — No ads, no in-app purchases"). As of September 2026 there is no standalone consumer DeepSeek app for macOS — the mobile apps plus the web chat are the official surfaces, and the separate developer console at [platform.deepseek.com](https://platform.deepseek.com) is for API keys and billing. This guide is for running `chat.deepseek.com` inside Quiper, where it shares an overlay with your other engines.

- [Starting point: what do you already have?](#starting-point-what-do-you-already-have)
- [1. Install Quiper](#1-install-quiper)
- [2. Launch Quiper](#2-launch-quiper)
- [3. Create a DeepSeek account (only if you don't have one)](#3-create-a-deepseek-account-only-if-you-dont-have-one)
- [4. Open DeepSeek in Quiper](#4-open-deepseek-in-quiper)
- [5. Sign in to DeepSeek inside Quiper](#5-sign-in-to-deepseek-inside-quiper)
- [6. Verify DeepSeek works](#6-verify-deepseek-works)
- [Troubleshooting](#troubleshooting)

---

## Starting point: what do you already have?

Pick the section that matches your situation and start there. You can skip anything marked "only if you don't have this yet."

| If you… | Start with |
| :--- | :--- |
| Haven't installed Quiper | [Step 1: Install Quiper](#1-install-quiper) |
| Installed Quiper but never launched it | [Step 2: Launch Quiper](#2-launch-quiper) |
| Launched Quiper but don't see DeepSeek | [Step 4: Open DeepSeek in Quiper](#4-open-deepseek-in-quiper) |
| Don't have a DeepSeek account | [Step 3: Create a DeepSeek account](#3-create-a-deepseek-account-only-if-you-dont-have-one) |
| Already signed in to DeepSeek | Skip ahead to [Verify DeepSeek works](#6-verify-deepseek-works) |

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
2.  When macOS asks to allow notifications, click **Allow**. Quiper needs this to show native notifications when a DeepSeek generation finishes in the background. (You can change this later under **System Settings → Notifications**.)
3.  Open the overlay by pressing **`⌥ Space`** (Option + Space). If the hotkey doesn't respond, Quiper needs Accessibility permission — see [Troubleshooting](#troubleshooting).
4.  Dismiss the overlay with **`⌥ Space`** again, **`⌘ H`**, or **`⌘ Q`**.

The overlay is now your home base: press `⌥ Space` from any app to summon it.

---

## 3. Create a DeepSeek account (only if you don't have one)

DeepSeek runs on your DeepSeek chat account at `chat.deepseek.com`. If you already use DeepSeek on the web or in the mobile app, skip this step. The chat account is separate from the developer account at `platform.deepseek.com` (API keys and billing, see [api-docs.deepseek.com](https://api-docs.deepseek.com)); you only need the chat account for this guide.

DeepSeek's web sign-up offers **Email** and **Mobile (phone + SMS)** tabs, plus **Continue with Google** on the web; the mobile apps add **Sign in with Apple** (see [deepseek.com/en/news/deepseek-app](https://www.deepseek.com/en/news/deepseek-app/) and [deepseekai.guide](https://deepseekai.guide/guides/deepseek-sign-up/): Email/Mobile with verification code, Google on web, Apple in app). You only need one method.

1.  Open [chat.deepseek.com](https://chat.deepseek.com) in your browser (or `chat.deepseek.com/sign_up` directly).
2.  Click **Sign up** in the top-right. Choose the **Email** or **Mobile** tab, or click **Continue with Google** to skip verification.
3.  For **Email**: enter your email, choose a password of at least eight characters, tick the terms box, and enter the verification code that arrives by email (codes expire after about 10 minutes; check spam, then request a new one after 60 seconds). For **Mobile**: enter your phone number and the SMS code where available in your region. For **Google**: complete the OAuth chooser.
4.  Set a display name when prompted and accept DeepSeek's Terms and Privacy Policy. You will land in a fresh chat session.

You can also create an account later from inside Quiper — the sign-in screen in the next step offers the same **Sign up** link and the same Google/Apple options.

> [!TIP]
> Pick one sign-in method and stick with it across devices. Mixing email + password and Google with the same address can create two separate accounts with separate histories.

---

## 4. Open DeepSeek in Quiper

DeepSeek ships as a built-in engine template, so on a fresh install it's already in your engine selector — no configuration needed.

1.  Press **`⌥ Space`** to open the overlay.
2.  Click the **DeepSeek** tab in the engine selector at the top. (If you've registered an engine hotkey in **Settings → Shortcuts → Engine Hotkeys**, press it to jump straight to DeepSeek.)
3.  A session tab opens and Quiper automatically places the keyboard cursor inside DeepSeek's prompt field, ready to type.

> [!NOTE]
> **Don't see a DeepSeek tab?** On a fresh install all default engines are preloaded, but if DeepSeek was removed earlier you can add it again: open **Settings (`⌘ ⇧ ,`) → Engines**, click **Add Engine**, set the name to `DeepSeek` and the URL to `https://chat.deepseek.com?referrer=https://github.io/sassanh/quiper`, then save. See [Managing Engines](../engines) for the focus selector (`textarea, div[contenteditable='true'], [role='textbox']`) and custom CSS defaults.

---

## 5. Sign in to DeepSeek inside Quiper

You sign in directly to DeepSeek from inside the overlay — Quiper never sees or stores your password.

1.  With the DeepSeek tab open, click **Log in** (top-right).
2.  Choose your sign-in method — **Email + password**, **Phone + SMS** (where offered), **Google**, or **Apple** (Apple is most reliable in the iOS app; web availability has varied). Quiper keeps the `accounts.google.com` and `appleid.apple.com` OAuth flows **inside** the overlay via built-in routing rules, so you won't be bounced out to a browser.
3.  Complete the CAPTCHA/slider if prompted (appears more often on new devices or unusual IPs) and, if you have 2FA enabled, the six-digit code from your authenticator or SMS.
4.  You will land on the DeepSeek chat page with the prompt box at the bottom. Your cross-platform chat history syncs across `chat.deepseek.com` and the mobile apps on the same account.

Once signed in, DeepSeek stays signed in across Quiper sessions.

---

## 6. Verify DeepSeek works

1.  Press **`⌥ Space`** to open the overlay (if it isn't already open).
2.  Confirm the DeepSeek tab is active and the prompt field is focused.
3.  Type a test message — for example, *"Reply with OK"* — and press **Enter**.
4.  Wait for the response to stream in. A generated answer means DeepSeek is fully working in Quiper.

### Optional refinements after sign-in

- **Native notifications:** Background generations surface as macOS notifications (requires the permission you granted in [Step 2](#2-launch-quiper)).
- **Persistent sessions:** Use `⌘ 1`–`⌘ 0` to keep up to ten separate DeepSeek threads alive. See [Daily Workflow & Shortcuts](../daily-workflow).
- **Native look:** Enable the transparent-background CSS in **Settings (`⌘ ⇧ ,`) → Engines → DeepSeek → Custom CSS** and a matching vibrancy material under **Settings → Appearance**.
- **Extra privacy:** Lock DeepSeek's local data behind Touch ID under **Settings → Engines → DeepSeek → Encrypt Local Storage**. See [Touch ID & Security](../security).

---

## Troubleshooting

| Problem | Likely fix |
| :--- | :--- |
| `⌥ Space` doesn't open the overlay | Grant Quiper Accessibility permission in **System Settings → Privacy & Security → Accessibility**, then re-bind the hotkey in **Settings (`⌘ ⇧ ,`) → Shortcuts**. |
| Google or Apple sign-in bounces to Safari | The `accounts.google.com` or `appleid.apple.com` **Internal** routing rule is missing or reordered. Add it back in **Settings → Engines → DeepSeek → Routing** (defaults: `^https?://([^/]*\.)?accounts\.google\.com(/\|$)` and `^https?://([^/]*\.)?appleid\.apple\.com(/\|$)` → **Internal**). |
| No DeepSeek tab in the selector | Re-add the engine manually (see [Step 4](#4-open-deepseek-in-quiper)). |
| Focus doesn't land in the prompt field | The focus selector is stale. Reset it in **Settings → Engines → DeepSeek → Prompt Input** (enable **Use Latest Default**) and reload with `⌘ R`. |
| No verification code email/SMS | Wait 60 seconds, request again, check spam; some disposable-email domains are blocked — try a primary mailbox. Phone delivery can stall on some carriers — switching to email or Google usually works. |
| "Email already registered" or two histories | You created two accounts with different methods. Sign in with the original provider (Email vs. Google vs. Apple). Use the same method everywhere. |
| No notifications for finished replies | Check **System Settings → Notifications → Quiper** is set to **Banners** or **Alerts**. |

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
