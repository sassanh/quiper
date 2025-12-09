# Quiper

Quiper is a macOS status-bar app that keeps your AI chat services in a single floating window. A global hotkey reveals the overlay, every service gets ten pre-created WebKit tabs, and the app stays out of the Dock so you can drop into an AI convo and return to work without re-arranging windows.

![Quiper screenshot](https://quiper.sassanh.com/quiper-screenshot.jpg)

[![CI](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml/badge.svg)](https://github.com/sassanh/quiper/actions/workflows/integration_delivery.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/sassanh/quiper.svg)](https://github.com/sassanh/quiper/releases)
[![codecov](https://codecov.io/gh/sassanh/quiper/branch/main/graph/badge.svg)](https://codecov.io/gh/sassanh/quiper)

## Highlights

- **Overlay built for AI sites** – Define any site that works in Safari (ChatGPT, Gemini, Grok, Claude, internal tools, etc.). Quiper opens each one inside its own `WKWebView` stack so session switches are instant.
- **Keyboard first** – The default global shortcut is `⌥ Space`, but you can record any combination. Once the window is visible, service switches (`⌘ ⌃ 1`…`⌘ ⌃ 9`), session switches (`⌘ 1`…`⌘ 0`), the inspector (`⌘ ⌥ I`), and settings (`⌘ ,`) are all bound to keys.
- **Persistent sessions** – Each service owns ten live `WKWebView`s. They keep scrollback and form contents, while cookies/cache live in the shared WebKit store so authentication survives next launch.
- **Notification bridge** – A JavaScript shim mirrors the browser `Notification` API into `UNUserNotificationCenter`. Banners carry the originating service URL and session index, so clicking one reopens the proper context.
- **Status-bar utility** – Quiper runs with `NSApplication.shared.activationPolicy = .accessory`. The menu extra exposes show/hide, cache clearing, hotkey capture, inspector toggle, login-item install, and notification settings.

## Requirements

- macOS 14.0 (Sonoma) or newer. The codebase targets Swift 6.2 and uses APIs that ship with Xcode 16.
- Apple silicon or Intel hardware. (Intel continues to work as long as macOS does; Apple announced Tahoe as the final Intel release.)
- Xcode 16 Command Line Tools (or newer) to build from source.

## Installation

### Download a release

1. Download the latest `.app` from the [Releases](https://github.com/sassanh/quiper/releases/latest) page — direct download: [`Quiper.app.zip`](https://github.com/sassanh/quiper/releases/latest/download/Quiper.app.zip).
2. Move `Quiper.app` to `/Applications`.
3. Because this project isn’t signed or notarized (Apple requires a paid Developer ID for that), Gatekeeper will block the first launch. Open **Settings → Privacy & Security** and click **Open Anyway** next to Quiper.
4. Relaunch `Quiper.app`, click **Open** on the follow-up dialog, and macOS will remember that exception for this bundle path.
5. Approve the notification prompt if you plan to use browser banners.

> If you rebuild, rename, or move `Quiper.app`, Gatekeeper treats it as a new binary, so repeat steps 3–4 after each update.

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

`build-app.sh` performs an `xcodebuild` release build, sets version info from the latest git tag (override with `APP_VERSION=x.y.z`), and leaves `Quiper.app` at the repo root.

## Daily Workflow

### Global hotkey

- Default `⌥ Space` toggles the overlay above every desktop.
- Capture a new combo via Status menu → **Set New Hotkey**. The selection is saved into `~/Library/Application Support/Quiper/settings.json` under the `hotkey` key and re-registered immediately.

### Inside the overlay

| Action | Shortcut |
| --- | --- |
| Switch session 1–9 | `⌘ 1` … `⌘ 9` |
| Session 10 | `⌘ 0` |
| Switch service 1–9 | `⌘ ⌃ 1` … `⌘ ⌃ 9` (or `⌘ ⌥` + digit) |
| Open Settings | `⌘ ,` |
| Toggle Web Inspector | `⌘ ⌥ I` |
| Hide overlay | `⌘ H` |

The segmented controls in the header mirror these shortcuts for mouse users. Dismissing the window via shortcut or menu simply hides it; Quiper reactivates the previously focused app automatically.

### Status-bar menu

- Show / Hide Quiper
- Settings window
- Show / Hide Inspector (reflects the active state)
- Share current page (via `NSSharingServicePicker`)
- Clear Web Cache (purges `WKWebsiteDataStore.default()`)
- Set New Hotkey
- Notification Settings… (opens macOS System Settings → Notifications → Quiper)
- Install at Login / Uninstall from Login
- Quit

## Sessions and Storage

- Each service entry in `settings.json` spawns ten `WKWebView`s during startup (`MainWindowController.createWebviewStack`). Quiper hides all but the active view, so switching is instantaneous.
- WebKit data (cookies, local storage, cache) is shared. Logging out of a service in one session signs out the others. Clearing the cache in the status menu flushes data for every service.
- The default services (ChatGPT, Gemini, Grok) live in `Settings.shared.defaultEngines`. Add or reorder entries via the Settings window or by editing the JSON file directly while Quiper is closed.

## Notifications

- `WebNotificationBridge` installs a user script that patches `Notification`, `Notification.requestPermission`, and `navigator.permissions.query` to match Safari’s behavior.
- When a site issues `new Notification(...)`, Quiper builds a `UNNotificationRequest` with the service URL, display name, and session index stored in `userInfo`.
- `NotificationDispatcher` implements `UNUserNotificationCenterDelegate`; clicking a banner brings Quiper to the front, selects the recorded service, and activates the session before focusing the input field.
- Use the status menu entry to jump straight to macOS notification settings if permissions change.

## Customization

- **Services** – Drag services directly in the header segmented control or open Settings → Services to add/delete/reorder entries. Each service includes a CSS selector used by `focusInputInActiveWebview()` to focus the correct input field when the session becomes visible.
- **Window aesthetics** – On macOS 26 Quiper wraps content in `NSGlassEffectView`; earlier versions use `NSVisualEffectView` with rounded corners. Drag anywhere on the translucent header to reposition.
- **Manual edits** – All preferences live at `~/Library/Application Support/Quiper/settings.json`. The JSON object contains `services: [...]` and a `hotkey` entry (`{ "keyCode": <UInt32>, "modifierFlags": <UInt> }`), so you can edit service lists and the global shortcut in one place while Quiper is closed.

## Reset & Data Paths

| Item | Path | Notes |
| --- | --- | --- |
| Settings (services + hotkey) | `~/Library/Application Support/Quiper/settings.json` | JSON object; edit while Quiper is closed. |
| LaunchAgent | `~/Library/LaunchAgents/com.<username>.quiper.plist` | Created/removed via Install at Login. |
| Downloads | `~/Downloads/` | Files initiated inside Quiper are saved here. |

Hit **Clear Web Cache** in the status menu to wipe cookies/cache without touching the JSON. For a full reset, quit Quiper and delete the two folders above.

## Login Automation

`Launcher.swift` creates a per-user LaunchAgent (`~/Library/LaunchAgents/com.<username>.quiper.plist`) so Quiper starts after login. The status menu toggles install/uninstall via `launchctl load/unload`.

## Troubleshooting

- **Global hotkey fails** – Another tool is likely using the same shortcut. Capture a new one so Quiper overwrites the `hotkey` entry in `settings.json`.
- **Notifications never appear** – Use the status menu to open macOS notification settings and ensure alerts are allowed. If you move the `.app`, macOS may treat it as a new bundle—toggle the permission again.
- **Web view stuck or stale** – Use **Clear Web Cache** or reload the service. All sessions share cookies, so re-authentication affects every session.
- **Login item doesn’t launch Quiper** – Inspect `~/Library/LaunchAgents/com.<username>.quiper.plist`. If it exists but isn’t running, run `launchctl bootout gui/$UID com.<username>.quiper` and reinstall via the status menu.
- **Build errors** – Ensure Xcode 16+ CLT are installed (`xcode-select --install`) and retry `swift build` or `./build-app.sh`.

## Contributing

1. Fork the repository and branch from `main` (`feat/<topic>`).
2. Run `swift build` (and any tooling you add) before opening a pull request.
3. Include macOS version, Quiper build hash, repro steps, and screenshots or screen recordings for UI changes.

Bug reports are most useful when they specify which service/session was active and whether browser permissions (camera, microphone, clipboard) were involved.

## License

Quiper is released under the [MIT License](LICENSE).
