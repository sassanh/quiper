# Quiper

Quiper unifies all your AI chat services into a single, instant-access macOS overlay. A global hotkey drops you into your conversations without rearranging windows, while persistent multi-sessions ensure you never lose your context. It stays completely out of your Dock and secures sensitive engines behind TouchID. **Most importantly, Quiper is 100% open-source, telemetry-free, and cryptographically attested to be backdoor-free ([Why is Quiper safe?](#safety)).**

![Quiper Main Window](.github/assets/hero.webp)

[![CI](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml/badge.svg)](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/sassanh/quiper.svg)](https://github.com/sassanh/quiper/releases)
[![codecov](https://codecov.io/gh/sassanh/quiper/branch/main/graph/badge.svg)](https://codecov.io/gh/sassanh/quiper)

## Highlights

- **Instant Global Overlay (`⌥ Space`)** – Acts like Spotlight for AI. Drop a floating window over any app, ask a question, and hide it without breaking your workflow.
- **Persistent Multi-Sessions** – Every AI engine gets 10 persistent slots kept alive in memory. Switch instantly between a coding chat and a writing chat without reloading.
- **Biometric Secure Sandboxing** – Protect highly sensitive conversations. Lock specific engines behind TouchID, encrypting their local data to prevent snooping.
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

## <a id="safety"></a>🛡️ Verifiable Safety & Supply Chain Integrity

**Quiper is built from the ground up to be completely transparent, telemetry-free, and safe.** Because macOS apps running outside the App Store require absolute trust, we don't expect you to take our word for it. Instead, **you can verify everything cryptographically—or ask your own AI assistant to double-check it for you.**

### 🤖 Ask Your AI to Audit Quiper
If you want to be 100% sure this app is safe and does not contain telemetry, tracking, backdoors, or malicious logic, copy-paste the prompt below into Claude, ChatGPT, Gemini, or any assistant you trust. It instructs the AI to inspect Quiper's open-source configuration, network architecture, and CI/CD pipelines to verify our claims:

> [!TIP]
> **Copy-paste this prompt into your trusted AI assistant:**
> 
> ```text
> I am considering downloading and running "Quiper", an open-source macOS app that manages WebKit sessions for AI services (located at: https://github.com/sassanh/quiper). I want to verify that this is a clean, trustworthy open-source project and NOT malware, a data-stealer, or a backdoored package subject to supply-chain attacks.
> 
> Please inspect the repository configuration and codebase to verify:
> 1. Does the code contain any hidden network telemetry, tracking, data-exfiltration logic, or third-party analytical SDKs? Confirm if all network requests go strictly and directly to the AI services defined by the user without any intermediary server.
> 2. Does the GitHub CI/CD workflow (.github/workflows/integration_delivery.yml) guarantee that all releases are compiled purely in the cloud via GitHub Actions, and does it use GitHub Artifact Attestation (sigstore/actions/attest-build-provenance) and Immutable Releases so that I can cryptographically verify that the binary I download matches this exact public source code?
> 3. Review the general application architecture (Swift/WebKit) to confirm that it is a standard native wrapper using system-provided WKWebViews.
> 
> Provide an honest technical review: Is Quiper clean, backdoor-free, and cryptographically verifiable?
> ```

## Installation

**Requirements**: macOS 14.0+ (Sonoma), Apple silicon or Intel.

### Download a release

1. Download the latest disk image from the [Releases](https://github.com/sassanh/quiper/releases/latest) page — direct download: [`Quiper.dmg`](https://github.com/sassanh/quiper/releases/latest/download/Quiper.dmg).
2. Double-click the `.dmg` and drag `Quiper.app` to `/Applications`.
3. Because this project isn't signed or notarized (Apple requires a paid Developer ID for that), Gatekeeper will block the first launch. Open **Settings → Privacy & Security** and click **Open Anyway** next to Quiper.
4. Relaunch `Quiper.app`, click **Open** on the follow-up dialog, and macOS will remember that exception for this bundle path.
5. Approve the notification prompt if you plan to use browser banners.

> If you rebuild, rename, or move `Quiper.app`, Gatekeeper treats it as a new binary, so repeat steps 3–4 after each update.

<details>
<summary><strong>Update Settings</strong></summary>

Configuring automatic checks and downloads:

![Update Settings](.github/assets/settings_updates.webp)
</details>

#### Build provenance

Every release `.dmg` is built entirely by [GitHub Actions](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml) — no builds are produced on a developer's local machine and uploaded manually. This means you can inspect the exact steps that produced the binary by looking at the [workflow file](https://github.com/sassanh/quiper/blob/main/.github/workflows/integration_delivery.yml) in the repository.

On top of that, each build is stamped with a **[build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds)**. Think of it as a tamper-evident seal: GitHub Signs a record that says *"this exact file was produced by this exact workflow run, triggered from this exact commit."* The signature is stored publicly on GitHub's transparency log, so anyone can verify it — without trusting anything you say.

If you have the [GitHub CLI](https://cli.github.com/) installed, you can verify any release disk image before running it:

```bash
gh attestation verify Quiper.dmg --repo sassanh/quiper
```

A passing result confirms the file came from this repository's CI and hasn't been tampered with since it was built. A failure means the file should not be trusted.

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

## Appearance

Quiper supports per-theme window customization:

- **Color Scheme**: Force Light or Dark mode, or follow System preference.
- **Window Background**: Choose blur effect (with material options) or solid color.
- **Per-Theme Settings**: When using System mode, configure light and dark themes separately.

<p float="left">
  <img src=".github/assets/settings_appearance.webp" width="49%" />
</p>

## Customization

- **Services** – Drag services directly in the header segmented control or open Settings → Engines to add/delete/reorder entries. Each service includes a CSS selector used to focus the correct input field when the session becomes visible.
- **Custom CSS** – Inject custom CSS per-engine for transparent backgrounds or style overrides.
- **Custom Actions** – Define JavaScript snippets triggered by global or app-specific shortcuts to automate tasks (e.g., clicking 'New Chat' or scraping content).
- **Manual edits** – All preferences live at `~/Library/Application Support/app.sassanh.quiper.Quiper/settings.json`. Edit while Quiper is closed.

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

## Feature Deep Dive

### Persistent Multi-Sessions
To achieve instant context switching, each service configured in `settings.json` spawns ten `WKWebView`s during startup. Quiper hides all but the active view, meaning switching tabs does not reload the page—your scrollback and typed text remain exactly as you left them. WebKit data (cookies, local storage) is shared across the engine, so logging in once authenticates all 10 slots.

### Biometric Secure Sandboxing
Quiper provides premium local sandboxing for highly sensitive engines:
- **Encrypted Volumes:** When secure storage is enabled for an engine, a 256-bit AES encrypted APFS `sparsebundle` is created at `~/Library/Application Support/app.sassanh.quiper.Quiper/EncryptedStores/<ServiceID>.sparsebundle`.
- **TouchID Integration:** A cryptographically random volume passphrase is securely generated and stored inside the macOS Secure Enclave Keychain, protected by LocalAuthentication policies requiring TouchID or your system password.
- **Biometrics Lock Shield:** Locked engines are visually shielded by a hardware-accelerated glassmorphic overlay. The real, persistent WebViews are only loaded and swapped into memory *after* successful authentication and volume mounting.

> [!IMPORTANT]
> **Local Client-Side Protection Only**
> Quiper's secure storage strictly protects your data *at rest on your local Mac*. It does **not** encrypt your data on the AI provider's servers.
> - **What IS Protected:** Local session tokens, cookies, `localStorage`, cached web assets, and offline chat histories saved to your Mac's disk by the web browser. If someone steals your unlocked laptop or snoops on your machine, they cannot access these locked engines without your biometrics.
> - **What is NOT Protected:** The actual conversations sent over the internet to the cloud. If you type a highly sensitive prompt into ChatGPT or Claude, OpenAI and Anthropic still receive, process, and store that data on their servers according to their own privacy policies. Quiper cannot make a third-party cloud service zero-knowledge.

### Custom Actions & JavaScript Automation
Power users can define JavaScript snippets triggered by global or app-specific keyboard shortcuts. This allows you to automate repetitive tasks—like clicking a "New Chat" button, clearing a context window, or scraping text—without reaching for the mouse.

### Native Notification Bridge
Long-running AI generations shouldn't force you to stare at a loading screen. `WebNotificationBridge` installs a user script that intercepts browser `Notification` APIs and bridges them directly into native macOS `UNUserNotificationCenter` banners. Clicking a banner brings Quiper to the front, selects the correct engine, and activates the right session automatically.

## Reset & Data Paths

| Item | Path | Notes |
| --- | --- | --- |
| Settings | `~/Library/Application Support/app.sassanh.quiper.Quiper/settings.json` | JSON object; edit while Quiper is closed. |
| Encrypted Volumes | `~/Library/Application Support/app.sassanh.quiper.Quiper/EncryptedStores/` | AES-256 encrypted APFS sparsebundles for secure engines. |
| LaunchAgent | `~/Library/LaunchAgents/com.<username>.quiper.plist` | Created/removed via Install at Login. |
| Downloads | `~/Downloads/` | Files initiated inside Quiper are saved here. |

Hit **Clear Web Cache** in the status menu to wipe cookies/cache without touching the JSON. For a full reset, quit Quiper and delete the settings file.

<details>
<summary><strong>General & Danger Zone</strong></summary>

Reset options and general configuration:

![General Settings](.github/assets/settings_general.webp)
</details>

## Troubleshooting

- **Global hotkey fails** – Capture a new one so Quiper overwrites the `hotkey` entry in `settings.json`.
- **Notifications never appear** – Use the status menu to open macOS notification settings and ensure alerts are allowed.
- **Web view stuck or stale** – Use **Clear Web Cache** or reload the service.
- **Build errors** – Ensure Xcode 16+ CLT are installed (`xcode-select --install`).

## Contributing

1. Fork the repository and branch from `main` (`feat/<topic>`).
2. Run `swift build` before opening a pull request.
3. Include macOS version, Quiper build hash, repro steps, and screenshots for UI changes.

## Versioning

Quiper follows **[Pride Versioning](https://pridever.org/)** (PrideVer). This means we release when we are genuinely proud of the progress and quality, and our version numbers reflect our sentiment toward each release. Since Quiper is an end-user desktop application and not a library, this human-centric approach allows us to prioritize architectural integrity and user experience over rigid semantic constraints.

### Update Channels

In addition to stable releases, Quiper provides two pre-production channels for testing:

- **Nightly**: Automatically generated every day at midnight (UTC) from the latest code in the `main` branch. These builds are experimental and intended for developers or those who want the absolute latest features.
- **Beta**: Manually triggered pre-releases used to validate specific features before they are merged into a stable version.

Both pre-production channels use the GitHub Actions **Run Number** as an internal build identifier. This ensures that the app can reliably detect updates even if the version string remains the same. Pre-production builds are explicitly marked with a `-nonproduction` suffix in their version string (e.g., `2.1.0-nightly-nonproduction`).

You can opt-in to these channels in **Settings → Updates**.

## ⚠️ Security & Privacy Disclaimer

While Quiper is built with a strong focus on user privacy and local isolation, it is **not a cryptographic vault formally audited or reviewed by professional security firms.**

Our secure storage features (APFS encrypted sparsebundles, TouchID Enclave, and macOS Keychain integration) are implemented using standard, robust macOS APIs to protect your sessions from casual local access. However:
- **No Expert Peer-Review:** This implementation has not been formally audited or peer-reviewed by professional cryptographic experts.
- **No Absolute Warranties:** As stated in the [MIT License](LICENSE), the software is provided "as is", without warranty of any kind, express or implied.
- **User Responsibility:** You are solely responsible for securing your local Mac user account, locking your machine, and ensuring your system is free from malware or spyware that could compromise active web sessions.

Quiper is designed to protect you from passive web tracking and accidental local exposure, but it should not be treated as a high-security container for critical state secrets or military-grade assets.

## License

Quiper is released under the [MIT License](LICENSE).
