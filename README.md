# Quiper

Quiper unifies all your AI chat services into a single, instant-access macOS overlay. A global hotkey drops you into your conversations without rearranging windows, while persistent multi-sessions ensure you never lose your context. It stays completely out of your Dock and secures sensitive engines behind TouchID.

![Quiper Main Window](.github/assets/hero.webp)

[![CI](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml/badge.svg)](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/sassanh/quiper.svg)](https://github.com/sassanh/quiper/releases)
[![codecov](https://codecov.io/gh/sassanh/quiper/branch/main/graph/badge.svg)](https://codecov.io/gh/sassanh/quiper)

## Highlights

- **Instant Global Overlay (`⌥ Space`)** – Acts like Spotlight for AI. Drop a floating window over any app, ask a question, and hide it without breaking your workflow.
- **Persistent Multi-Sessions** – Every AI engine keeps 10 persistent slots alive in memory. Switch instantly between a coding chat and a writing chat without reloading.
- **Biometric Secure Sandboxing** – Protect highly sensitive conversations. Lock specific engines behind TouchID, encrypting their local session data, cookies, cache, and histories using native macOS AES-256 APFS sparsebundles.
  
  > [!IMPORTANT]
  > **Local Client-Side Protection Only**
  > Quiper's secure storage strictly protects your data *at rest on your local Mac*. If someone steals your unlocked laptop or snoops on your machine, they cannot access these locked engines without your biometrics. It does **not** encrypt your data on the AI provider's servers—conversations sent to the cloud are processed according to the respective provider's privacy policies.
  
- **Bring Your Own Engine** – Don't get locked into one ecosystem. Add ChatGPT, Claude, Gemini, or point it to local models like `llama.cpp` or Open WebUI.
- **Verifiable Safety** – 100% open-source, telemetry-free, and cryptographically verified via GitHub attestations.
- **Power User Tools** – Inject custom CSS, trigger Custom Actions via JavaScript, and receive native macOS notifications for background generations.

<details>
<summary>📸 <strong>Gallery: Supported Engines</strong></summary>

<p float="left">
  <img src=".github/assets/main_chatgpt.webp" width="49%" />
  <img src=".github/assets/main_grok.webp" width="49%" />
</p>
<p float="left">
  <img src=".github/assets/main_gemini.webp" width="49%" />
  <img src=".github/assets/main_google.webp" width="49%" />
</p>
<p float="left">
  <img src=".github/assets/main_open-webui.webp" width="49%" />
  <img src=".github/assets/main_x.webp" width="49%" />
</p>

</details>

## Installation

**Requirements**: macOS 14.0+ (Sonoma), Apple silicon or Intel.

### Download a release

1. Download the latest disk image from the [Releases](https://github.com/sassanh/quiper/releases/latest) page — direct download: [`Quiper.dmg`](https://github.com/sassanh/quiper/releases/latest/download/Quiper.dmg).
2. Double-click the `.dmg` and drag `Quiper.app` to `/Applications`.
3. Because this project isn't signed or notarized with a paid Apple Developer ID, Gatekeeper will block the first launch. Open **Settings → Privacy & Security** and click **Open Anyway** next to Quiper.
4. Relaunch `Quiper.app`, click **Open** on the follow-up dialog, and macOS will remember that exception for this bundle path.
5. Approve the notification prompt if you plan to use browser banners.

<details>
<summary><strong>Update Settings</strong></summary>

Configuring automatic checks and downloads:

![Update Settings](.github/assets/settings_updates.webp)
</details>

<details>
<summary>🛡️ <strong>Verifiable Safety & Supply Chain Attestation</strong></summary>

Since macOS apps running outside the App Store require absolute trust, you can verify Quiper's safety cryptographically or ask your own AI assistant to double-check it for you.

#### 1. Ask Your AI to Audit Quiper
Copy-paste this prompt into Claude, ChatGPT, Gemini, or any assistant you trust to inspect the repository configuration and network architecture:

```text
I am considering downloading and running "Quiper", an open-source macOS app that manages WebKit sessions for AI services (located at: https://github.com/sassanh/quiper). I want to verify that this is a clean, trustworthy open-source project and NOT malware, a data-stealer, or a backdoored package subject to supply-chain attacks.

Please inspect the repository configuration and codebase to verify:
1. Does the code contain any hidden network telemetry, tracking, data-exfiltration logic, or third-party analytical SDKs? Confirm if all network requests go strictly and directly to the AI services defined by the user without any intermediary server.
2. Does the GitHub CI/CD workflow (.github/workflows/integration_delivery.yml) guarantee that all releases are compiled purely in the cloud via GitHub Actions, and does it use GitHub Artifact Attestation (sigstore/actions/attest-build-provenance) and Immutable Releases so that I can cryptographically verify that the binary I download matches this exact public source code?
3. Review the general application architecture (Swift/WebKit) to confirm that it is a standard native wrapper using system-provided WKWebViews.

Provide an honest technical review: Is Quiper clean, backdoor-free, and cryptographically verifiable?
```

#### 2. Cryptographic Build Provenance
Every release `.dmg` is built entirely by GitHub Actions in the cloud. Each build is stamped with a tamper-evident **[build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds)**.

If you have the [GitHub CLI](https://cli.github.com/) installed, you can verify any release disk image before running it:

```bash
gh attestation verify Quiper.dmg --repo sassanh/quiper
```

A passing result confirms the file came from this repository's CI and has not been tampered with since it was built.
</details>

### Build from source

```bash
git clone https://github.com/sassanh/quiper.git
cd quiper
open Quiper.xcodeproj # Opens in Xcode
# Press Cmd+R to build and run
```

Create a distributable bundle:

```bash
./build-app.sh # Builds with xcodebuild, creates Quiper.app
open Quiper.app
```

## Daily Workflow

The default global hotkey `⌥ Space` summons the overlay. When active, navigate instantly:

| Action | Shortcut |
| --- | --- |
| Switch session 1–10 | `⌘ 1` … `⌘ 0` |
| Switch service 1–9 | `⌘ ⌃ 1` … `⌘ ⌃ 9` (or `⌘ ⌥` + digit) |
| Open Settings | `⌘ ,` |
| Toggle Web Inspector | `⌘ ⌥ I` |
| Hide overlay | `⌘ H` |
| Find in page | `⌘ F` |
| Zoom in/out | `⌘ +` / `⌘ -` |

Dismissing the window automatically reactivates your previously focused app so you can immediately resume typing.

<details>
<summary><strong>Shortcut Configuration</strong></summary>

Customize global and in-app shortcuts:

![Shortcuts Settings](.github/assets/settings_shortcuts.webp)
</details>

## Appearance & Customization

- **Color Scheme & Blur**: Force Light or Dark mode, follow System preference, and customize window vibrancies or blur materials.
- **Custom CSS** – Inject custom CSS per-engine for transparent backgrounds or style overrides.
- **Custom Actions** – Define JavaScript snippets triggered by global or app-specific shortcuts to automate tasks (e.g., clicking 'New Chat' or scraping content).
- **Manual edits** – All preferences live at `~/Library/Application Support/app.sassanh.quiper.Quiper/settings.json`. Edit while Quiper is closed.

<details>
<summary><strong>Appearance Customization</strong></summary>

![Appearance Settings](.github/assets/settings_appearance.webp)
</details>

<details>
<summary><strong>Expanded Selectors</strong></summary>

Show full service details and conversation context:

![Expanded Selectors](.github/assets/feature_selectors.webp)
</details>

<details>
<summary><strong>Service Configuration</strong></summary>

Manage engines and custom actions:

![Engine Settings](.github/assets/settings_engines.webp)

Define hotkeys for specific services:

![Service Hotkeys](.github/assets/settings_shortcuts_hotkeys.webp)
</details>

## Reset & Data Paths

| Item | Path | Notes |
| --- | --- | --- |
| Settings | `~/Library/Application Support/app.sassanh.quiper.Quiper/settings.json` | JSON object; edit while Quiper is closed. |
| Encrypted Volumes | `~/Library/Application Support/app.sassanh.quiper.Quiper/EncryptedStores/` | AES-256 encrypted APFS sparsebundles for secure engines. |
| LaunchAgent | `~/Library/LaunchAgents/com.<username>.quiper.plist` | Created/removed via Install at Login. |
| Downloads | `~/Downloads/` | Files initiated inside Quiper are saved here. |

Hit **Clear All Web Data** in the status menu to wipe cookies/cache without touching the JSON. For a full reset, quit Quiper and delete the settings file.

<details>
<summary><strong>General & Danger Zone</strong></summary>

Reset options and general configuration:

![General Settings](.github/assets/settings_general.webp)
</details>

## Troubleshooting & Release Channels

### Troubleshooting

- **Global hotkey fails** – Capture a new one so Quiper overwrites the `hotkey` entry in `settings.json`.
- **Notifications never appear** – Use the status menu to open macOS notification settings and ensure alerts are allowed.
- **Web view stuck or stale** – Use **Clear All Web Data** or reload the service.
- **Build errors** – Ensure Xcode 16+ CLT are installed (`xcode-select --install`).

### Release Channels

Quiper provides two pre-production channels for testing (opt-in via **Settings → Updates**):

- **Nightly**: Automatically generated every day at midnight (UTC) from the latest code in the `main` branch. These builds are experimental and intended for developers or those who want the absolute latest features.
- **Beta**: Manually triggered pre-releases used to validate specific features before they are merged into a stable version.

Both pre-production channels use the GitHub Actions Run Number as an internal build identifier, letting the app reliably detect updates even if the major version string remains the same.

## License

Quiper is released under the [MIT License](LICENSE).
