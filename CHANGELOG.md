# Changelog

## [Unreleased]

### Added

- Introduced initial XCTest target with coverage for `ShortcutValidator` hotkey rules.

## [1.1.0] - 2025-11-20

### Added

- Added a default “Ollama” service pointing to <http://localhost:8080> with focus selector, new-session that clears temporary mode, new-temporary-session that enables it, and reload script.

### Changed

- Fixed service selector hit-testing to use AppKit's segment bounds directly, eliminating offset drift when clicking later engine items.
- Improved drag-and-drop reordering feedback to avoid flickering and ensure smooth segment movement.

## [1.0.0] - 2025-11-20

### Added

- Introduced an Update Manager that checks GitHub releases, downloads newer builds, and surfaces update status directly inside Settings. The General tab now shows a “Check for Updates” button beside the version string plus toggles for automatic checking and automatic download.
- Added built-in “New Session”, “New Temporary Session”, and “Reload” custom actions with per-service scripts for ChatGPT, Gemini, Grok, X, and Google so fresh installs have working automation out of the box.

### Changed

- Restyled the General tab so Startup and Updates live inside standard macOS rounded group boxes, added clearer helper copy for each toggle/button, and updated `onChange` usages to the macOS 14-compliant signature to silence deprecation warnings.
- Default services now append `?referrer=https://github.io/sassanh/quiper`, and the starter list includes X and Google with sensible focus selectors and action scripts aligned with the new default actions.
- Services tab now includes an “Add from Template” menu (ChatGPT, Gemini, Grok, etc., plus an “Add All” option) so users can quickly re-create the bundled engines without retyping settings.
- General tab gains a “Danger Zone” with buttons to clear saved web data and to erase all local Quiper data (services, actions, shortcuts, and scripts) with confirmation prompts.
- Services tab now includes an "Erase All" control that removes every configured service, custom action, shortcut, and script directory so you can drop back to a factory-fresh state in one click.
- Overlay zoom controls now use `⌘+` / `⌘−` to change web content scale per service (sessions stay in lockstep), remember the level between switches, and add `⌘⌫` to snap back to 100%.
- Added a “Session Actions” menu button beside the settings gear that lists every built-in shortcut (zoom, reload, copy/cut/paste) plus your custom actions so you can trigger them by click while seeing their keyboard equivalents.
- Added a lightweight inline Find bar (⌘F to toggle, ⌘G/⇧⌘G to step results, Escape to dismiss) that uses WebKit’s native find to search the active service and shows live match counts.

### Fixed

- Removing custom actions in Settings → Actions now routes through a trash button with a confirmation alert, so deletions only occur after approval and the related on-disk scripts are cleaned up reliably.
- Deleting services now shows a confirmation alert whether you use the sidebar swipe/delete gesture or the "Remove Service" button. The prompt clarifies that the operation wipes the service’s sessions and custom action scripts so you know exactly what’s affected before confirming.

## [0.3.2] - 2025-11-17

### Added

- Custom action scripts now live as individual `.js` files under `~/Library/Application Support/Quiper/ActionScripts/<service>/<action>.js`, making it easy to edit them in any external editor. The Advanced tab exposes an “Open in Text Editor” button for each action, and Quiper reads the script file at run time so the latest content is always executed.

### Changed

- Hiding the overlay no longer forces focus back to whatever app was active when Quiper opened; macOS now decides which app should be active when the window closes.
- Documented the Gatekeeper bypass steps for unsigned builds in the README, including the need to use System Settings → Privacy & Security → Open Anyway on first launch.
- Reworked the service selector so services activate on mouse-down and drag-and-drop reordering is fully handled by a custom `ServiceSelectorControl`, producing immediate closed-hand feedback and robust hit testing across uneven segment widths.
- Removing a service or a custom action now deletes the corresponding on-disk script files so stale code doesn’t accumulate, and the settings payload keeps service/action script metadata in sync.

## [0.3.1] - 2025-11-14

### Added

- Restored focus to the previously active application whenever Quiper hides, so dismissing the overlay via the global hotkey instantly returns you to your work without an extra click.
- Services can now be reordered directly from the overlay header by dragging the segmented control; the new order is saved immediately.

### Changed

- All preferences now persist inside `~/Library/Application Support/Quiper/settings.json`. The services array and the global hotkey live in one JSON payload, and legacy `hotkey_config.json` files are migrated automatically.
- Updated the README to reflect the consolidated settings file and the revised hotkey persistence model.
- Added an always-visible gear button to the overlay header so Settings is one click away, and tweaked the button styling so it matches light/dark appearances.

## [0.3.0] - 2025-11-13

### Added

- Bridged the web `Notification` API inside every WKWebView so in-app services can request macOS notification permission and deliver local banners, complete with metadata linking back to the originating service/session.
- Added a status-bar menu item that jumps straight to macOS Notification Settings for Quiper, making it easy to re-authorize the app when testing in different bundle locations.

### Fixed

- Clicking a notification banner now activates Quiper, selects the correct service and chat session, and focuses the input for immediate reply.

## [0.2.1] - 2025-11-10

### Fixed

- Switching services now also refreshes the session selector so it reflects the previously active pane for that service, eliminating stale “pane 1” indicators when returning to a different session.

## [0.2.0] - 2025-11-10

### Added

- Rebuilt Quiper as a native Swift/SwiftUI app (replacing the prior Python/Cocoa stack) with an always-on-top `OverlayWindow`, per-engine WKWebView pools, inspector toggles, and keyboard-driven service/session switching.
- Introduced a glassy SwiftUI settings window that lets you add/reorder/remove AI services, edit CSS focus selectors, and toggle login-item installation without leaving the app.
- Added a Carbon-powered hotkey manager with an inline capture overlay so users can redefine the global shortcut at runtime while persisting the selection to disk.
- Bundled the Finder icon directly in the repo and wired it into `build-app.sh`/`CFBundleIconFile` so the `.app` shows the correct badge immediately.

### Changed

- The release build now flows entirely through SwiftPM and copies service logos alongside the new icon to keep the bundle self-contained for CI and local installs.
- README and default settings document the multi-service, multi-instance experience and describe the new `./build-app.sh` entry point for building native artifacts.

### Removed

- Deleted the old Python launcher (`quiper/`), uv/pyproject scaffolding, generated icns assets, and bespoke build scripts in favor of the streamlined Swift target and resources committed under `Sources/Quiper` plus `Supporting`.

### Automation

- `.github/workflows/integration_delivery.yml` drives every artifact: the `build` job on `macos-26` runs `actions/checkout@v4`, executes `./build-app.sh`, compresses with `ditto`, and ships the zip via `actions/upload-artifact@v4`.
- Nightly pre-releases and tag pushes reuse the produced artifact via `actions/download-artifact@v4` and publish with `softprops/action-gh-release@v2`, ensuring the same toolchain (macOS runners + SwiftPM) is exercised before public release.
