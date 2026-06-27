# Quiper

Quiper unifies all your AI chat services into a single, instant-access macOS overlay. A global hotkey drops you into your conversations without rearranging windows, while persistent multi-sessions ensure you never lose your context. It stays completely out of your Dock and secures sensitive engines behind TouchID.

![Quiper Main Window](.github/assets/hero.webp)

[![CI](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml/badge.svg)](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/sassanh/quiper.svg)](https://github.com/sassanh/quiper/releases)
[![codecov](https://codecov.io/gh/sassanh/quiper/branch/main/graph/badge.svg)](https://codecov.io/gh/sassanh/quiper)

### 📖 [Read the Official Documentation ➔](https://sassanh.github.io/quiper/)

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
3. Launch `Quiper.app` and approve the notification prompt if you plan to use browser banners.

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

---

### 📖 [Read the Official Documentation ➔](https://sassanh.github.io/quiper/)
For full details on keyboard shortcuts, managing engines, customizing CSS, setting up Custom Actions, and troubleshooting, please refer to our comprehensive documentation.

## Acknowledgments

- Special thanks to [Ubo Pod](https://github.com/ubopod/) for providing the Apple Developer code signing certificate used for official releases.

## License

Quiper is released under the [MIT License](LICENSE).
