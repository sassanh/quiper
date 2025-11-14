# Changelog

## [Unreleased]

### Added
- Restored focus to the previously active application whenever Quiper hides, so dismissing the overlay via the global hotkey instantly returns you to your work without an extra click. (`Sources/Quiper/App.swift`)

### Changed
- All preferences now persist inside `~/Library/Application Support/Quiper/settings.json`. The services array and the global hotkey live in one JSON payload, and legacy `hotkey_config.json` files are migrated automatically. (`Sources/Quiper/Settings.swift`, `Sources/Quiper/Listener.swift`)
- Updated the README to reflect the consolidated settings file and the revised hotkey persistence model. (`README.md`)

## [0.3.0] - 2025-11-13

### Added
- Bridged the web `Notification` API inside every WKWebView so in-app services can request macOS notification permission and deliver local banners, complete with metadata linking back to the originating service/session. (`Sources/Quiper/WebNotificationBridge.swift`, `Sources/Quiper/NotificationDispatcher.swift`, `Sources/Quiper/MainWindowController.swift`, `Supporting/Info.plist`)
- Added a status-bar menu item that jumps straight to macOS Notification Settings for Quiper, making it easy to re-authorize the app when testing in different bundle locations. (`Sources/Quiper/App.swift`)

### Fixed
- Clicking a notification banner now activates Quiper, selects the correct service and chat session, and focuses the input for immediate reply. (`Sources/Quiper/NotificationDispatcher.swift`, `Sources/Quiper/App.swift`)

## [0.2.1] - 2025-11-10

### Fixed
- Switching services now also refreshes the session selector so it reflects the previously active pane for that service, eliminating stale “pane 1” indicators when returning to a different session (`Sources/Quiper/MainWindowController.swift`).

## [0.2.0] - 2025-11-10

### Added

- Rebuilt Quiper as a native Swift/SwiftUI app (replacing the prior Python/Cocoa stack) with an always-on-top `OverlayWindow`, per-engine WKWebView pools, inspector toggles, and keyboard-driven service/session switching (`Sources/Quiper/MainWindowController.swift`, `Sources/Quiper/App.swift`).
- Introduced a glassy SwiftUI settings window that lets you add/reorder/remove AI services, edit CSS focus selectors, and toggle login-item installation without leaving the app (`Sources/Quiper/SettingsView.swift`, `Sources/Quiper/Settings.swift`, `Sources/Quiper/Launcher.swift`).
- Added a Carbon-powered hotkey manager with an inline capture overlay so users can redefine the global shortcut at runtime while persisting the selection to disk (`Sources/Quiper/Listener.swift`).
- Bundled the Finder icon directly in the repo (`Supporting/QuiperIcon.icns`) and wired it into `build-app.sh`/`CFBundleIconFile` so the `.app` shows the correct badge immediately (`build-app.sh`, `Supporting/Info.plist`).

### Changed

- The release build now flows entirely through SwiftPM (`build-app.sh`) and copies service logos alongside the new icon to keep the bundle self-contained for CI and local installs.
- README and default settings document the multi-service, multi-instance experience and describe the new `./build-app.sh` entry point for building native artifacts (`README.md`, `Sources/Quiper/Settings.swift`).

### Removed

- Deleted the old Python launcher (`quiper/`), uv/pyproject scaffolding, generated icns assets, and bespoke build scripts in favor of the streamlined Swift target and resources committed under `Sources/Quiper` plus `Supporting`.

### Automation

- `.github/workflows/integration_delivery.yml` drives every artifact: the `build` job on `macos-26` runs `actions/checkout@v4`, executes `./build-app.sh`, compresses with `ditto`, and ships the zip via `actions/upload-artifact@v4`.
- Nightly pre-releases and tag pushes reuse the produced artifact via `actions/download-artifact@v4` and publish with `softprops/action-gh-release@v2`, ensuring the same toolchain (macOS runners + SwiftPM) is exercised before public release.
