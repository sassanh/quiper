# Changelog

## Unreleased

### Added

- Display the active session's title in the overlay header, positioned between the service and session selectors.

### Changed

- Removed unused legacy helper code (`configureItem`, `menuItem`, `keyEquivalent`, `initiateDownload`) from `MainWindowController`.

### Fixed

- Resolves Swift 6 concurrency warnings in webview title observation.

## [2.2.1] - 2025-12-16

### Added

- **Shortcut UI Tests**: Added isolated test classes for in-app shortcuts with proper verification:
  - `ZoomShortcutsUITests`: Tests `Cmd+=`/`Cmd+-` with width-based relative zoom verification
  - `ReloadShortcutsUITests`: Tests `Cmd+r` with dynamic random ID change detection
  - `FindShortcutsUITests`: Tests `Cmd+f` (open), `Cmd+g`/`Enter` (forward), `Cmd+Shift+g`/`Shift+Enter` (backward), `Escape` (close), with custom HTML containing multiple search targets
  - `GeneralShortcutsUITests`: Tests `Cmd+,` (Settings), `Cmd+h` (Hide), `Cmd+w` (Close)
- **Test Infrastructure**: Added `--test-custom-engines-path` argument for file-based HTML content injection in UI tests

### Changed

- **Test Custom Engines**: Refactored `--test-custom-engines` to accept a count parameter (e.g., `--test-custom-engines=4`)
- **ReorderServicesUITests**: Updated to use `--test-custom-engines=4`
- **CustomActionUITests**: Updated to use `--test-custom-engines=2`

### Fixed

## [2.2.0] - 2025-12-16

### Added

- **UI Tests**: Added `CustomActionUITests` to robustly verify the custom action lifecycle, script execution, and error handling.
- **UI Tests**: Added `DownloadUITests` to verify native file download functionality, ensuring `blob:` files are correctly saved and readable on disk.
- **Unit Tests**: Added `MainWindowControllerTests` to verify core logic like service selection.
- **Test Infrastructure**: Added support for `DistributedNotification` based test signaling (`app.sassanh.quiper.test.beep`) to verify system audible alerts without UI inspection.
- **Development**: Added `scripts/generate_icons.sh` to automate app icon generation.

### Changed

- **Codebase Cleanup**: Removed legacy `share` functionality and associated tests to streamline the codebase.
- **Launch Shortcuts UI Tests:** Fixed a race condition where tests would type hotkeys before the application had finished registering them, by synchronizing the "Saved" status indicator with the hotkey registration task.
- **Launch Shortcuts UI Tests (Refactor):** Refactored `LaunchShortcutsUITests` to align with the robust patterns of `NavigationShortcutsUITests`, replacing flaky "Saved" label checks with deterministic button value verification and implementing comprehensive functional verification for global hotkeys and cleanup.
- **Documentation:** Added comprehensive companion documentation for all UI tests in `QuiperUITests/UserFlows`, covering setups, actions, and expected results for templates, updates, custom actions, and service management.
- **Icons**: Updated App Icon to a new squircle design.
- **UI**: Refined `SettingsView` and `Menu` layouts for consistent spacing and alignment.

### Fixed

- **Downloads**: Fixed an issue where `blob:` URL downloads (e.g., generated images) were failing silently or throwing errors. Implemented native `WKDownload` handling and added necessary Sandbox entitlements (`com.apple.security.files.downloads.read-write`) to allow saving directly to the user's Downloads folder. Verified with `DownloadUITests` which confirms file content integrity.

## [2.1.0] - 2025-12-10

### Added

- **Notification Status**: Added a real-time status indicator to the menu bar menu (e.g., "Notifications: Authorized") that updates automatically when permissions change.
- **Smart Deep Linking**: The "Open System Settings" button now attempts to deep-link directly to Quiper's specific notification settings page, falling back to the general list if needed.
- **Permission Sync**: The app now automatically refreshes permission status when returning to the foreground, ensuring immediate updates without restart.

### Changed

- **UI Clarity**: Renamed "Open Settings" in the General tab to "Open System Settings" to clearly indicate it opens macOS System Settings.

### Fixed

- **Code Coverage**: Fixed Codecov reporting issues by providing industry-standard LCOV coverage reports for better Codecov integration.
- **CI Reliability**: Fixed UI tests in CI by ensuring the app is explicitly activated before simulating hotkeys and using robust scroll-to-find logic.

## [2.0.0] - 2025-12-10

### Added

- **UI Tests**: Added extensive UI tests covering window reordering and other interactions to ensure robustness.
- **Template Management UI Tests**: Implemented comprehensive UI tests for adding and deleting service templates, covering both one-by-one and bulk operations.
- **Code Coverage**: Integrated Codecov for automated test coverage reporting on every CI build.
- **CI/CD Enhancements**: Updated GitHub Actions workflow to run robustly on macOS runners with parallel testing disabled for stability.

### Changed

- **Codebase Cleanup**: Removed extensive debug print statements from the application and UI tests to reduce log noise and improve performance.
- **Project Structure**: Migrated codebase from a simple Swift package project to a full Xcode project structure.
- **Testing Reliability**: Refactored `run-tests-with-coverage.sh` to generate JSON coverage reports and handle headless execution more reliably.

## [1.4.0] - 2025-11-28

### Added

- Added test coverage for `ShortcutFormatter` to verify glyph rendering and fallback behavior.
- Added integration tests for Settings to verify default shortcut configurations, vim-style alternates, and modifier key bindings.
- Migrated tests to Swift Testing framework (`@Test` macro, `#expect` assertions) for modern test runner support.
- Improved Test Quality: Replaced shallow rendering tests with meaningful behavior verification for Settings and Shortcuts.
- New Tests: Added comprehensive tests for `CustomAction`, `Service`, `UpdatePreferences`, and `HotkeyManager` data models.
- Coverage Reporting: Added a script to generate HTML code coverage reports.esting in different bundle locations.

### Changed

- Nightly builds now update a single "nightly" release instead of creating a new release each night.
- Nightly build artifacts set `CFBundleShortVersionString` to include a `-nightly-nonproduction` suffix to signal they are not production builds.

### Fixed

- Fixed an issue where authentication and internal links (sharing the same root domain) were opening in the external browser instead of the app overlay.

## [1.3.0] - 2025-11-25

### Added

- Allow assigning a per-engine global shortcut that launches Quiper straight into that engine.

### Changed

- Allowed bare F1–F20 keys to be recorded and used as shortcuts without requiring modifier keys; non-function keys still require Command/Option/Control/Shift.
- Shortcut formatting now uses glyphs for Return/Escape/arrows and adds labels for F1–F20 plus punctuation/keypad symbols, matching macOS menus.
- Status menu items now display proper modifier-aware shortcuts (e.g., Command+, for Settings, Command+Option+I for Inspector, Command+Q for Quit) and avoid unmodified key equivalents.
- Settings window now defaults to the Engines tab, with the former Services tab relabeled to "Engines" and General moved to the end of the tab order.
- Global show/hide hotkey (⌥Space, with ⌃Space fallback in Xcode) is now configurable directly in Settings → General without an overlay on the main window.
- Engine launch hotkeys no longer override the global toggle, and ⌘W now hides the overlay in addition to the hotkey.
- Unified the design of all shortcut buttons, adding clear and reset options where applicable for a consistent experience.
- Improved "Shortcut reserved" error messages to explicitly state which action owns the conflicting shortcut (e.g., "Reserved for Settings").
- Global shortcuts (like Show/Hide) are now temporarily disabled while the Settings window is focused to prevent accidental triggering.
- Fixed an issue where the Software Update window could appear behind other windows.

## [1.2.0] - 2025-11-21

### Added

- Introduced initial XCTest target with coverage for `ShortcutValidator` hotkey rules.

### Changed

- Added default shortcuts for next/previous session/service: `⌘⇧←` and `⌘⇧→` to cycle sessions, `⌘⌃←` and `⌘⌃→`.
- Added default alternative vim-like bindings for session/service switching: `⌘H`/`⌘L` for sessions, `⌘⌃H`/`⌘⌃L` for services.
- Added shortcut editor UI: inline primary/alternate badges with per-badge reset, fixed label column, compact widened badges.

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
