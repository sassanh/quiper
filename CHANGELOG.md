# Changelog

## [Unreleased]

### Added

- **Per-Engine 'Preserve Prompt' Configuration ([Settings.swift](Quiper/Settings.swift), [SettingsView.swift](Quiper/SettingsView.swift), [SettingsModels.swift](Quiper/SettingsModels.swift))**: Added a configurable per-engine setting named "Preserve Prompt" with a premium card design and SF Symbols schematic transition graphic under the newly relocated "Prompt Element" (formerly "Focus Selector") settings section.
- **Caret Selection & Input State Restoration ([WebViewManager.swift](Quiper/Components/WebViewManager.swift), [MainWindowController.swift](Quiper/MainWindowController.swift), [MainWindowController+Actions.swift](Quiper/MainWindowController+Actions.swift))**: Added support for preserving and restoring draft prompts and precise caret selection ranges when switching engines/sessions or relaunching Quiper. Implemented a robust user-interaction tracking window (`mousedown`, `keydown`, `touchstart`) to filter out programmatic page updates (e.g. React mounts/render cycles) and force-restore the correct selection range until the user starts editing.


- **Engine Locking Shortcuts ([MainWindowController+InputHandling.swift](Quiper/MainWindowController+InputHandling.swift), [MainWindowController+Actions.swift](Quiper/MainWindowController+Actions.swift), [SettingsModels.swift](Quiper/SettingsModels.swift), [ShortcutsSettingsView.swift](Quiper/ShortcutsSettingsView.swift))**: Added native keyboard shortcuts for "Lock Current Engine" (`Cmd+Opt+L` by default) and "Lock All Secure Engines" (`Cmd+Opt+Shift+L` by default). Triggering this on an unencrypted engine seamlessly prompts the user and deep-links directly to that engine's Security tab in Settings.
- **Lock Screen Password Fallback Shortcut ([LockOverlayView.swift](Quiper/Components/LockOverlayView.swift))**: Added a `Cmd+P` shortcut binding to the engine lock screen to quickly bypass the biometric prompt and fallback to password entry. Upgraded the visual styling of the button to use premium badge layouts consistent with the Control Center HUD.
- **Modifier HUD Search and Keyboard Navigation ([ModifierHUDView.swift](Quiper/Components/ModifierHUDView.swift), [MainWindowController+InputHandling.swift](Quiper/MainWindowController+InputHandling.swift))**: Added an auto-focused search bar on top of the Modifier HUD, allowing users to filter engines/tabs dynamically as they type. Implemented keyboard navigation (`Up`/`Down` arrows to navigate filtered lists, `Enter` to select) and focus trapping (`Tab`/`Shift-Tab` within the search bar). Added a custom `FlippedStackView` to align small lists to the top of the scroll view.
- **Unit Testing for HUD Search ([MainWindowControllerModifierTests.swift](QuiperTests/MainWindowControllerModifierTests.swift))**: Added the `testModifierHUDSearchAndFiltering` unit test to verify search bar focus, filtering behavior, and keyboard event routing.

- **Visual Enhancements for Selectors ([SegmentedControl.swift](Quiper/SegmentedControl.swift), [CollapsibleSelector.swift](Quiper/CollapsibleSelector.swift), [MainWindowController+Selectors.swift](Quiper/MainWindowController+Selectors.swift))**: Upgraded the `CollapsibleSelector` with a proper capsule shape and pixel-perfect internal margins. Fixed the "ghost text" shadow rendering artifact by clearing native labels during custom drawing. Designed a dark-theme adaptive lock icon that automatically inverses the segment's text color brightness to guarantee perfect contrast. Corrected the popup displacement math to accurately model capsule curvature padding and lock icon dimensions, ensuring the expanded panel aligns flawlessly over its anchor button.

- **Privacy-Aware Secure Tab Persistence ([MainWindowController.swift](Quiper/MainWindowController.swift), [MainWindowController+Actions.swift](Quiper/MainWindowController+Actions.swift), [WebViewManager.swift](Quiper/Components/WebViewManager.swift))**: Extended the Tab Preservation feature to fully support Secure Engines without leaking URLs or browsing state to unencrypted preference files. Automatically serializes active secure tabs into an isolated `quiper_tabs.json` file securely housed inside the engine's encrypted 256-bit AES APFS sparsebundle. Restores tabs automatically upon successful biometric Touch ID unlock of the engine.
- **Tab Preservation & Relaunch Recovery ([SettingsModels.swift](Quiper/SettingsModels.swift), [Settings.swift](Quiper/Settings.swift), [WebViewManager.swift](Quiper/Components/WebViewManager.swift), [MainWindowController.swift](Quiper/MainWindowController.swift), [App.swift](Quiper/App.swift), [SettingsPickers.swift](Quiper/Components/SettingsPickers.swift), [SettingsView.swift](Quiper/SettingsView.swift))**: Added support for persisting open session tabs across application restarts and crashes. Users can configure this behavior inside General Settings with three policies: **Always Restore** (automatic serialization), **Ask on Exit** (interactive modal prompt to save or close tabs), and **Never Restore** (fresh session on every launch). Includes comprehensive unit tests in [TabSurvivalTests.swift](QuiperTests/TabSurvivalTests.swift).
- **Graphical Session Switching Picker ([SettingsPickers.swift](Quiper/Components/SettingsPickers.swift), [SettingsView.swift](Quiper/SettingsView.swift))**: Replaced raw checkboxes under Behavior in General Settings with a custom graphical card picker (`SessionSwitchingPicker`). It presents side-by-side interactive card layouts for **Auto-Switch** (automatic switching when closing the last tab of an engine) and **Auto-Create** (automatic tab creation when switching to an empty engine) with custom schematic diagrams of engine transitions and tab layouts.

### Changed

- **Optimized Tab Switching and Visibility ([WebViewManager.swift](Quiper/Components/WebViewManager.swift))**: Updated the session show/hide logic to toggle the `isHidden` property of session wrapper views rather than detaching them from the view hierarchy via `removeFromSuperview()`. This prevents visual blinking, WKWebView load cancellations, and web content process terminations during rapid navigation and startup restoration.
- **Behavior Section Styling Realignment ([SettingsView.swift](Quiper/SettingsView.swift))**: Aligned Behavior section headers and row icons to resolve dynamically via `.settingsResolved`, satisfying standard #2 of the settings styling guidelines.
- **Isolated Debug and Production Environments ([Constants.swift](Quiper/Constants.swift), [Launcher.swift](Quiper/Launcher.swift), [SecureStorageManager.swift](Quiper/Components/SecureStorageManager.swift), [EncryptedVolumeManager.swift](Quiper/Components/EncryptedVolumeManager.swift), [App.swift](Quiper/App.swift), [OnboardingWizard.swift](Quiper/Components/OnboardingWizard.swift), [WebKitCacheCleaner.swift](Quiper/Components/WebKitCacheCleaner.swift), [Main.swift](Quiper/Main.swift), [NotificationDispatcher.swift](Quiper/NotificationDispatcher.swift))**: Fully isolated the LaunchAgent plist labels, Keychain keys, and OS volume names between development builds and production builds. Development builds now use `com.quiper-dev.enginekey.*` for Keychain lookup, `com.<username>.quiper.dev.plist` for the LaunchAgent, and `QuiperDevEngine-*` as the mounted volume name, preventing cross-build collisions when importing configurations. Centralized the bundle identifier lookup through a single `Constants.BUNDLE_ID` static property across the entire codebase to avoid duplicated local queries.

### Fixed

- **Inactivity Auto-Lock Reliability ([MainWindowController.swift](Quiper/MainWindowController.swift), [MainWindowController+Actions.swift](Quiper/MainWindowController+Actions.swift))**: Fixed a security vulnerability where encrypted engines could remain mounted in the background due to App Nap or system sleep suspending the auto-lock timer, briefly exposing decrypted web view contents upon application wake/show. Added synchronous inactivity lock checks immediately upon window display, application activation, and workspace wake, and expanded the event monitor to track scroll and drag gestures so the app doesn't lock during active use.
- **Keychain Password Desync Prevention ([SecureStorageManager.swift](Quiper/Components/SecureStorageManager.swift), [SettingsView.swift](Quiper/SettingsView.swift), [OnboardingWizard.swift](Quiper/Components/OnboardingWizard.swift))**: Fixed a severe data-loss edge case where if the macOS Keychain refused to save a newly generated 256-bit AES engine key (e.g., due to missing entitlements, Ad-Hoc signing transitions, or `errSecDuplicateItem` conflicts), the failure was silently ignored. The application would then proceed to create the encrypted `.sparsebundle` using the new key, but subsequent unlock attempts would fetch the older, stale key from the Keychain, resulting in an unrecoverable `hdiutil attach failed - Authentication error`. `saveKeyToKeychain` now strictly throws an error upon failure, immediately aborting the volume creation process before any mismatch can occur.
- **Encrypted Volume Deletion Cleanup ([SettingsView.swift](Quiper/SettingsView.swift))**: Fixed a critical edge case where deleting an encrypted engine via the Settings sidebar would silently fail to remove the underlying `.sparsebundle` file if the volume was currently mounted, leaving the file orphaned on disk while deleting its Keychain password. Volume deletion is now explicitly wrapped in a concurrent Task that successfully unmounts the volume before safely obliterating the file and Keychain entry.
- **Lock Overlay Error Exposing ([WebViewManager.swift](Quiper/Components/WebViewManager.swift))**: Removed a generic `"failed"` keyword filter in the biometric authentication catch block that previously swallowed critical `hdiutil` authentication mismatch errors. Users will now correctly see an informative error message overlay if their sparse bundle fails to attach due to a corrupted Keychain state, rather than being stuck on an unresponsive lock screen.

## [4.1.0] - 2026-06-15

### Added

- **Extended Background Leftover Cleanup ([WebKitCacheCleaner.swift](Quiper/Components/WebKitCacheCleaner.swift), [WebKitCacheCleanerTests.swift](QuiperTests/WebKitCacheCleanerTests.swift))**: Expanded the startup cache cleaner to automatically find and purge orphaned custom CSS files, focus selector files, action script directories, APFS sparsebundles, and secure Keychain password keys when their corresponding engines/services are deleted.

- **Settings Style Selection ([AppearanceSettingsView.swift](Quiper/AppearanceSettingsView.swift), [Settings.swift](Quiper/Settings.swift), [SettingsModels.swift](Quiper/SettingsModels.swift))**: Introduced a customizable "Settings Color Style" preference supporting **Colorful** (vibrant defaults) and **Classic** (clean monochrome) modes.
- **Settings Style Picker ([SettingsPickers.swift](Quiper/Components/SettingsPickers.swift))**: Created a custom picker display featuring side-by-side graphical layout previews for both Colorful and Classic modes.
- **Custom Colored Checkbox Toggle Style ([SettingsComponents.swift](Quiper/Components/SettingsComponents.swift))**: Added a custom SF Symbol-based `ColoredCheckboxToggleStyle` to customize settings checkboxes dynamically based on active styling.
- **Settings Styling Guidelines ([settings-styling.md](docs/settings-styling.md))**: Documented development standards for settings rows, state observation, and color resolution, and linked it in [AGENTS.md](AGENTS.md).
- **Comprehensive Unit Testing Suite ([FaviconFetcherTests](QuiperTests/FaviconFetcherTests.swift), [WebKitCacheCleanerTests](QuiperTests/WebKitCacheCleanerTests.swift), [SecureStorageManagerTests](QuiperTests/SecureStorageManagerTests.swift), [SettingsDirectoryMigratorTests](QuiperTests/SettingsDirectoryMigratorTests.swift))**: Added 31 unit tests verifying URL normalization, localhost resolution, WebKit cache cleaning filters, random key generation, Keychain errors, and Application Support directory migration.
- **Settings Directory Migrator ([SettingsDirectoryMigrator.swift](Quiper/Components/SettingsDirectoryMigrator.swift))**: Introduced a dedicated helper component to manage legacy Application Support directory migration independently of the main application lifecycle.
- **Interactive Onboarding Tips**: Introduced a premium, step-by-step onboarding guide (`GhostOnboardingManager`) with glassy physical keycap tooltips (`GhostOnboardingHUDView`) to help new users learn service/session selectors, shortcuts, and triggers on first launch.
- **Auto-start Detection**: Configured the LaunchAgent startup wrapper to pass a `--autostart` flag so the app remains hidden in the status bar at boot, showing the window only on explicit user launches.
- **Comprehensive Documentation Site**: Migrated extensive setup guides, engine management instructions, and troubleshooting tables from the README into a dedicated VitePress documentation site hosted on GitHub Pages.
- **In-App Documentation Shortcuts ([App.swift](Quiper/App.swift), [StatusBar.swift](Quiper/StatusBar.swift), [SettingsView.swift](Quiper/SettingsView.swift))**: Added native "Documentation" link shortcuts inside the main `Help` menu, the session selector's "..." dropdown menu, the macOS Status Bar menu, and the General Settings pane.
- **Window on All Spaces Toggle ([AppearanceSettingsView.swift](Quiper/AppearanceSettingsView.swift), [MainWindowController.swift](Quiper/MainWindowController.swift), [App.swift](Quiper/App.swift))**: Added a new setting under Appearance -> Window allowing the user to configure the Quiper main window to stay visible across all macOS desktop spaces.

### Changed

- **Decomposed SettingsComponents ([SettingsComponents.swift](Quiper/Components/SettingsComponents.swift), [SettingsPickers.swift](Quiper/Components/SettingsPickers.swift))**: Split custom picker controls out of the primary components file into a dedicated pickers file to improve organization and build times.
- **Instant Settings Style Re-rendering ([SettingsComponents.swift](Quiper/Components/SettingsComponents.swift), [UpdatesSettingsView.swift](Quiper/UpdatesSettingsView.swift))**: Added `@ObservedObject` references to Settings inside custom components so changes apply immediately.
- **FaviconFetcher and WebKitCacheCleaner Refactoring ([FaviconFetcher.swift](Quiper/Components/FaviconFetcher.swift), [WebKitCacheCleaner.swift](Quiper/Components/WebKitCacheCleaner.swift))**: Refactored URL normalization, resolution checks, and orphaned-store filtering logic from private to internal static functions, enabling isolated logic validation without UI overhead.
- **App Directory Migration Delegation ([Main.swift](Quiper/Main.swift))**: Updated the application entry point to delegate legacy path migrations to the new `SettingsDirectoryMigrator` helper.
- **Streamlined Landing Page**: Completely rewrote the `README.md` to serve as a focused, compelling landing page highlighting core features, visual galleries, and security audits, while delegating deep-dive technical configuration guides to the official documentation site.
- **Custom CSS and Appearance Separation**: Cleaned up the documentation architecture by relocating Custom CSS injection guides out of the general "Appearance" page and correctly associating them with the "Managing Engines" guide where they are configured.

### Fixed

- **macOS Checkbox Rendering Bug**: Replaced native checkbox toggles in Settings with the custom symbol-based toggle style to prevent solid black background rendering.
- **Danger Zone and Button Readability**: Ensured warning sections (Danger Zone) remain bright red and primary buttons (e.g., Check for Updates) remain fully colored and legible under both color styles.
- **Native Fullscreen Space Jump**: Fixed an issue where activating Quiper via the global hotkey on top of a native macOS fullscreen space (e.g., a fullscreen video in Safari/Firefox) caused a space transition/jump back to the last active normal space. The overlay window now always maintains its collection behavior as `.canJoinAllSpaces` when hidden, transitioning to `.moveToActiveSpace` only while visible to properly align with space switching preferences without triggering space jumps.
- **Space-switching global hotkey behavior ([App.swift](Quiper/App.swift))**: Fixed an issue where switching to another desktop Space and hitting the global shortcut would close the window on the original Space rather than bringing it to the active Space. The shortcut now checks `isOnActiveSpace` to ensure the window is correctly shown on the active Space on the first press.
- **Nightly and Beta Tag Loop Resolution ([integration_delivery.yml](.github/workflows/integration_delivery.yml), [build-app.sh](build-app.sh))**: Fixed an issue where nightly and beta builds would pull previous nightly release tags as their version base, resulting in a feedback loop that prepended hyphens and appended run numbers (e.g., `nightly-----v4.0.0-660-666-667-668-669`). Restructured the `git describe` command to target only release tags starting with `v*`.
- **Auto-focus on window show ([MainWindowController.swift](Quiper/MainWindowController.swift))**: Fixed input auto-focus failing for certain engines (notably Gemini) when showing the window from the hidden state. The root cause was WebKit's web content process losing its native activation after the window was ordered out, causing JavaScript `.focus()` calls to be silently ignored. The fix traverses WKWebView's internal subviews to find the deepest responder-eligible view and makes it first responder directly, cleanly re-establishing the focus chain with no side effects.

## [4.0.0] - 2026-05-29

### Added

- **Premium External Code Editor with Finder & Clipboard Integration ([SettingsView](Quiper/SettingsView.swift))**: Completely replaced the basic, raw textboxes for Action Scripts, Custom CSS, and Focus Selectors inside Settings with a highly premium, read-only syntax-highlighted code container (`HighlightedCodeContainer`).
  - **Edit**: Launches the default text editor of your choice (VS Code, Zed, Sublime Text, Cursor, etc.), generating the file dynamically on disk.
  - **Reveal**: Directly launches Finder and highlights the specific config file on disk.
  - **Copy Path**: Copies the absolute file path to the macOS clipboard.
  - **Top-Left Pinning**: Enforced strict top-leading alignment using a `GeometryReader` container, ensuring short scripts are cleanly pinned to the top-left rather than being centered.
- **Dynamic Regex Syntax Highlighter ([SyntaxHighlighter](Quiper/SyntaxHighlighter.swift))**: Engineered a lightweight, zero-dependency tokenization engine inside pure Swift that uses a Monokai-inspired dark palette. Includes custom parsing rules for both JavaScript (control statements, keywords, type references, functions, variables, strings, comments) and CSS (selectors, properties, units, value keywords, comments, punctation).
- **Storage and Syntax Highlighting Unit Tests ([SyntaxHighlighterTests](QuiperTests/SyntaxHighlighterTests.swift))**: Added robust testing suites validating JavaScript/CSS parsing layers and temporary directory isolation.

- **WebKit Legacy Data Onboarding ([OnboardingWizard](Quiper/Components/OnboardingWizard.swift))**: Added a premium, glassmorphic welcome onboarding wizard shown on first run of Quiper 4.0.0. Enables users to selectively migrate legacy shared cookies, databases, and localStorage from pre-4.0 environments into isolated, per-engine workspace directories.
- **Biometric Enclave SparseBundle Provisioning**: Integrates automated Keychain creation and 256-bit AES APFS SparseBundle initialization within the onboarding sequence, allowing users to secure sensitive engines with TouchID directly from launch.
- **Engine Web Data Settings Management ([SettingsView](Quiper/SettingsView.swift))**: Added a premium, isolated Web Data management sidebar choice for each engine. It features database storage paths, copy-to-clipboard, "Show in Finder" action, and locked security cards for encrypted storage engines.
- **Dynamic Live Reload Pipeline ([WebViewManager](Quiper/Components/WebViewManager.swift))**: Implemented a unified `.webDataCleared` notification system that completely tears down the active WebViews, cleans up orphaned directory files on disk, and seamlessly re-instantiates active sessions back to a clean sign-in state dynamically.
- **Automatic WebKit Cache Purging on Delete ([SettingsView](Quiper/SettingsView.swift))**: Integrates the native `WKWebsiteDataStore.remove(forIdentifier:)` API in the service deletion workflow to immediately wipe all cookies, databases, and localStorage cache folders from your Mac when an engine is removed.
- **Test Suite Directory Isolation ([WebViewManager](Quiper/Components/WebViewManager.swift))**: Forces unit and UI tests running under the test harness (such as XCTest) to use in-memory `WKWebsiteDataStore.nonPersistent()` instances, completely preventing persistent directories from cluttering your global host cache folder.
- **Seamless Session Data Migration ([SecureDataMigrationManager](Quiper/Components/SecureDataMigrationManager.swift))**: Implemented a highly sophisticated and completely seamless migration manager that allows users to preserve their active login sessions, cookies, and local storage when transitioning an engine between standard and secured (encrypted) states. Presents an interactive, premium confirmation dialog to let the user choose whether to transfer data or start with a clean slate, fully protecting their session state.
- **Async Data Migration HUD Loader ([SettingsView](Quiper/SettingsView.swift))**: Added an extremely premium, hardware-accelerated glassmorphic progress HUD overlay with thin blur materials to block all settings interactions during long-running async migration stages. Displays step-by-step descriptive process logs (e.g., "Creating encrypted volume...", "Transferring session data...") to inform the user exactly what is happening in real-time.
- **Settings Window Interaction Shielding ([App.swift](Quiper/App.swift))**: Implemented NSWindowDelegate `windowShouldClose` delegate monitoring on the Settings window. Prevents closing the Settings pane (via CMD+W, menu actions, or the titlebar close button) while an asynchronous secure storage migration is active, playing a system alert beep to protect filesystem operations and database integrity during transfers.
- **Background WebKit Cache Cleaner ([WebKitCacheCleaner.swift](Quiper/Components/WebKitCacheCleaner.swift))**: Implemented a highly sophisticated, non-blocking background utility that identifies and purges orphaned persistent WebKit data store directories at application launch. Features strict UUID verification (preserving system/default folders) and active preservation of all configured engine profiles, resolving disk pollution gracefully without UI hangs.
- **Cache Purge Startup Toggle ([SettingsView](Quiper/SettingsView.swift))**: Added a user-facing preference under General ➔ Startup settings to let users safely enable or disable the background WebKit cache cleaner at startup.
- **Premium Switch Toggle Style ([SettingsComponents](Quiper/Components/SettingsComponents.swift))**: Replaced default macOS form checkboxes across all settings views with a high-fidelity, modern toggle switch style (`.toggleStyle(.switch)`), dramatically improving visual aesthetics.
- **Danger Zone Differentiation ([SettingsView](Quiper/SettingsView.swift))**: Renamed and clarified global "Clear Web Data" settings controls and confirmation alerts to "Clear All Web Data" to clearly differentiate global resets from individual engine storage resets.

- **Encrypted Storage Architecture ([SecureStorageManager](Quiper/Components/SecureStorageManager.swift) & [EncryptedVolumeManager](Quiper/Components/EncryptedVolumeManager.swift))**: Built a robust, highly secure volume manager that manages creating, mounting, and locking per-engine 256-bit AES encrypted Sparsebundles inside isolated directory structures.
- **Secure Biometric Keychain Integration**: Integrates directly with the macOS secure enclave Keychain to store and retrieve volume passwords, wrapped tightly behind LocalAuthentication policies requiring TouchID or system password authentication.
- **Biometrics Lock Shield ([LockOverlayView](Quiper/Components/LockOverlayView.swift))**: Designed a premium, interactive glassmorphic overlay for locked engines that shields web content, featuring:
  - Custom geometric scanner tick rendering and pulse/glow animations that adapt dynamically to TouchID states.
  - Native password entry fallback with custom animated field shaking on validation failures.
- **Interactive Full-Window Quit Overlay ([QuitOverlayView](Quiper/Components/QuitOverlayView.swift))**: Implemented a glassy, visual-effect-based overlay covering both the web view and top bar during shutdown, blocking all mouse/keyboard inputs via overridden hit-testing and event tracking.
- **Delayed Persistent Webview Architecture**: Added in-memory, non-persistent webview loading for locked encrypted engines. Real persistent WebViews are only instantiated and swapped in after successful biometric validation and volume mounting.

### Changed

- **Deferred Core App Startup Lifecycle ([App.swift](Quiper/App.swift))**: Re-architected application initialization in `AppDelegate.applicationDidFinishLaunching` to completely defer status bar item creation, main window building, menu structures, and persistent webview instantiations until the Onboarding Wizard is completed, preventing the premature generation of empty default databases.
- **Enforced Source Cache Erasure**: Purges the legacy unencrypted `WebsiteData` folder automatically once onboarding wraps up, reclaiming disk space and ensuring no unencrypted login states are exposed.
- **Complete Environment Isolation for Settings and WebKit Data ([project.pbxproj](Quiper.xcodeproj/project.pbxproj), [Constants.swift](Quiper/Constants.swift))**: Unified both application settings and WebKit caches to resolve dynamically under the app's bundle identifier (`app.sassanh.quiper.Quiper` / `app.sassanh.quiper.QuiperDev`). This isolates cookies, logins, and configurations between the Xcode debug run and the production `/Applications` version completely, eliminating namespace collisions and session interference.
- **Automatic Settings Directory Migration on Launch ([Main.swift](Quiper/Main.swift))**: Implemented a zero-configuration migration routine on startup that automatically moves older Application Support data (`Quiper` / `QuiperDev`) to the new bundle identifier-based folders seamlessly without losing settings, logins, or scripts.
- **CI/CD Delivery Format**: Migrated the release artifact packaging from `.zip` compression to a standard macOS DMG disk image (`.dmg`) using `hdiutil` in the delivery workflow, providing a native drag-to-install experience. Artifact attestations have been updated to sign the disk image.
- **Documentation Refined (README Overhaul)**:
  - Completely rewrote the `README.md` opening hook and Highlights to focus aggressively on core user value propositions (Instant Overlay, Persistent Sessions, Biometric Sandboxing).
  - Added a prominent **Verifiable Safety** section providing a copy-pasteable AI Audit Prompt, allowing users to verify the app is telemetry-free and cryptographically attested using their own trusted AI assistant.
  - Added a strict **Local Protection Only** disclaimer to clarify that Biometric Storage encrypts *local* data on the Mac, but does not protect or encrypt server-side conversations sent to providers like OpenAI.
  - Aggressively pruned boilerplate filler and useless technical explanations to keep the documentation sleek and impactful.

- **Engine Settings Sidebar Reorganization & Secure Storage Migration ([SettingsView](Quiper/SettingsView.swift))**:
  - Reorganized the advanced settings split-pane sidebar into clear, structured categories with **Storage & Security** positioned as the first category, followed by `Routing`, `Customization`, and `Custom Actions`. All items feature premium SF Symbol icons.
  - Set the default selection on entering engine settings to **Secure Storage** for a seamless, immediate look at security parameters.
  - Migrated the monolithic **Security & Privacy** controls (APFS SparseBundle toggles, Auto-Lock Policies, and Inactivity Timeout minutes) out of the main detail body and into a dedicated first-class tab inside the sidebar list, significantly de-cluttering the engine configuration interface.
- **MainWindowController Architectural Decomposition**: Refactored the 3,800+ line god class `MainWindowController` into highly focused, single-responsibility domain extensions:
  - `MainWindowController+InputHandling.swift` for command shortcuts, modifier flags, and keyboard routing.
  - `MainWindowController+Appearance.swift` for continuous vibrancy, blur window coordination, and color schemes.
  - `MainWindowController+Selectors.swift` for segmented controllers and collapsible popups.
  - `MainWindowController+SessionManagement.swift` for session step increments, empty states, and tab lifecycles.
  - `MainWindowController+WebViewObservers.swift` for title, loading, and navigation observation.
  - `MainWindowController+HeaderVisibility.swift` for hover tracking and margins.
  - `MainWindowController+Actions.swift` for custom scripts, menu selections, and lock timers.
- **Inline Class Extraction**: Extracted five monolithic helper structures and types out of `MainWindowController` into dedicated files: [HoverIconButton.swift](Quiper/HoverIconButton.swift), [HoverTextField.swift](Quiper/HoverTextField.swift), [RefreshStopButton.swift](Quiper/RefreshStopButton.swift), [NavigationButtonGroup.swift](Quiper/NavigationButtonGroup.swift), and [Zoom.swift](Quiper/Zoom.swift).
- **Non-Blocking Safe App Termination**: Refactored `applicationShouldTerminate` to return `.terminateLater`, performing unmounting asynchronously in background tasks to prevent main-thread AppKit locks.
- **Biometric Pad Scale Transform**: Integrated a CoreAnimation layer transform inside `embedBiometricView` to visually scale the native `LAAuthenticationView` perfectly to a 36x36 scanner target while completely removing explicit width/height constraints to resolve Auto Layout warnings.
- **Settings Window Dimension Integrity**: Optimally adjusted the `SettingsWindow` to start at `800x500` and reduced the `minSize` constraint to `720x480` to completely eliminate UI clipping and truncation across all tab views while preserving a compact desktop footprint.
- **Biometrics Concurrency Safety**: Wrapped `NotificationCenter` observers inside safe asynchronous `Task { @MainActor in ... }` blocks in [LockOverlayView.swift](Quiper/Components/LockOverlayView.swift) to resolve strict Swift 6 concurrency warnings.
- **WKUIDelegate Deduplication inside WebViewManager**: Cleaned up over 80 lines of identical alerts, prompts, confirmation panels, and file dialog implementations by forwarding the main view's delegate methods directly to the shared `PopupUIDelegate.shared` singleton.
- **Redundant Log and Stale Code Cleanup**: Stripped unnecessary `NSLog` traces from the `showSession()` layout pipeline and purged stale comments and empty line gaps inside `WebViewManager.swift`.
- **Settings Class and Model Decomposition**: Decoupled settings models and serialization definitions from the main `Settings` singleton orchestrator inside [Settings.swift](Quiper/Settings.swift). Extracted 15+ sub-models, enums, structs, and custom coders—including `AutoLockPolicy`, `UpdatePreferences`, `WindowAppearanceSettings`, and `AppShortcutBindings`—into a clean, focused [SettingsModels.swift](Quiper/SettingsModels.swift) file.
- **App Controller and Status Bar Decomposition**: Extracted status-item, menu builders, and icon loader routines from the core [App.swift](Quiper/App.swift) orchestrator. Moved classes and structures like `StatusBarController`, `StatusButtonFactory`, `StatusIconProvider`, and `StatusMenuBuilder` into a newly dedicated [StatusBar.swift](Quiper/StatusBar.swift) file, trimming over 340 lines of layout builder boilerplate from the app's entry lifecycle.

### Fixed

- **Robust Migration File Copy**: Swallowed minor file-read or lock warnings gracefully during database transfers to prevent a single locked system cache file from aborting the entire user session migration.
- **App Update Deadlock on Relaunch**: Fixed a critical AppKit threading bug where clicking the "Relaunch Now" button on an update prompt would asynchronously hang the application on the "Securing Storage" screen indefinitely. Ensured the relaunch process unrolls outside the modal event loop and explicitly executes `NSApp.reply` on the `@MainActor`.
- **Cleared App Shortcuts Swallowing the 'a' Key**: Fixed a regression in [MainWindowController+InputHandling.swift](Quiper/MainWindowController+InputHandling.swift) where clearing an App Shortcut (e.g. Next Session) would set its configuration to `keyCode: 0` without modifiers. Since `0` maps to the hardware 'A' key, typing 'a' globally triggered the disabled shortcut. Added explicit validation to ignore disabled configurations during event handling, and backed the fix with a new test suite in [MainWindowControllerShortcutTests.swift](QuiperTests/MainWindowControllerShortcutTests.swift).
- **Standardized Window Menu and Cmd+W Close Tab Navigation**: Resolved a critical HIG collision where `Cmd+W` (historically bound to "Hide Quiper" in the application and window menus) intercepted standard closing behavior. Standardized `Cmd+H` for app hiding, added a standard "Close Session" menu item mapped to `Cmd+W`, and routed it natively down the responder chain using custom overrides in [OverlayWindow](Quiper/OverlayWindow.swift) and [MainWindowController](Quiper/MainWindowController.swift).
- **Session Selector Segment Selection Reset on Empty Engine**: Fixed a UI regression where closing the last session and showing the empty state page left segment "1" visually highlighted as selected due to `syncSelectorSelections()` overriding the deselected state back to index 0.
- **Click Pass-Through Protection on Initial Connect**: Fixed an issue where borderless transparent windows allowed mouse clicks, right clicks, and dragging to pass through to background windows during initial webview connection/blank-page states. Added a custom hit-test capturing [WindowContentView](Quiper/OverlayWindow.swift) and set a micro-opacity backdrop to guarantee the window is solid to the Window Server without affecting visual transparency.
- **Unified Blurred Backdrop for the Top-Bar**: Fixed a transparency issue where background/desktop text sharply bled through the top-bar's background in visible mode, causing visual clutter and readability confusion. Expanded [backgroundEffectView](Quiper/MainWindowController.swift) and [contentColorView](Quiper/MainWindowController.swift) to cover the entire unified window height, softly blurring background pixels and aligning with Safari-grade continuous window vibrancy.
- **Layout Margin Preservation on Session Switch**: Resolved a layout bug in hidden top-bar mode where switching sessions caused the new webview's wrapper to expand and fill the entire window frame, overwriting the 8px transparent margin layout. Implemented a fallback in [updateLayout()](Quiper/Components/WebViewManager.swift) to reuse and preserve the active content frame (`currentContentFrame`).
- **Neutral Settings Nomenclature ("Toolbar" Renaming)**: Corrected a logical contradiction where settings section and rows were labeled "Top Bar" and "Header Visibility" despite the user being able to render the drag area bar at the bottom. Standardized labels to "Toolbar" and "Toolbar Visibility" inside [AppearanceSettingsView.swift](Quiper/AppearanceSettingsView.swift) to keep phrasing neutral and accurate.
- **Biometrics Focus-Wake, Auto-Reprime & Inactive Focus Release**: Resolved an issue where remaining locked for long periods caused TouchID to time out or become unresponsive, and implemented dynamic biometric context invalidation to immediately release system TouchID focus when Quiper is hidden or deactivated, preventing it from blocking other applications in the background. Added active focus observers for key window and active application lifecycle state changes in [LockOverlayView.swift](Quiper/Components/LockOverlayView.swift) to coordinate acquisition and release of biometric locks seamlessly.
- **Persistent Profile & Session Protection**: Resolved a critical SQLite data race/corruption issue where WebKit created session conflict files inside unmounted folders, causing regular user logouts on rerun.
- **Swift 6 Strict Concurrency Conformity**: Isolated unmounting tasks to a `nonisolated` private function in [App.swift](Quiper/App.swift), ensuring compliance with Swift 6 actor-isolation rules.
- **Keychain errSecAuthFailed Graceful Recovery**: Resolved an issue where biometric or Keychain authentication cancellations/denials produced a cryptic `Keychain error: -25293` dialog. Gracefully mapped `errSecAuthFailed` (-25293) and `errSecUserCanceled` (-128) inside [SecureStorageManager.swift](Quiper/Components/SecureStorageManager.swift) to a human-readable authorization failed state, and enhanced the cancel detection pipeline inside [WebViewManager.swift](Quiper/Components/WebViewManager.swift) to silently clear the loading overlay without displaying annoying warning banners.
- **Software Update Dialog Polish**: Replaced the generic box icon with the Quiper app logo, hid raw build comments from release notes, and appended build numbers to the beta version text.

## [3.3.0] - 2026-05-25

### Added

- **Unified Navigation Button Capsule**: Redesigned back/forward buttons so that when both are active, they seamlessly merge into a single premium rounded capsule divided by a clean vertical hairline separator, providing individual hover-segment highlights while staying perfectly clipped to the container's rounded corner geometries.
- **Safari-style Force Reload and Origin Reload**: Added native alternate menu items and key equivalents:
  - `Cmd+Shift+R` for "Force Reload from Scratch" which reinstantiates the browser tab (loading the initial URL from scratch).
  - `Cmd+Opt+R` for "Reload Page from Origin" which bypasses the local cache on the current page using WebKit's native `reloadFromOrigin()`.
- **Child-Window Integration for Dialogs**: Integrated `SettingsWindow` and `UpdatePromptWindow` directly into the `OverlayWindow` child-window hierarchy, making them natively hide and show together with the main application window.
- **Unblocked Global Hotkeys**: Removed the hotkey-blocking checks when the settings window is active, allowing seamless toggling of the application visibility via global shortcuts.
- **Automatic Focus Restoration**: Enhanced key window focus management so that whenever the application is unhidden, the settings or update dialog automatically re-acquires active keyboard focus.
- **Double-Layered Modal Focus Defense**: Implemented `windowShouldBecomeKey` to return `false` when either settings or update prompt is active, ensuring the main window is barred from acquiring key focus. Updated `windowDidBecomeKey` focus redirection to close the child window loophole, preventing underlying web view keyboard interactions while dialogs are open.
- **Dual-Logo Empty State**: Display active engine icon next to Quiper logo.
- **Self-Healing Favicons**: Automatically scraper-upgrade blurry icons (<96px).

### Changed

- **Standard Page Reloading (`Cmd+R`)**: Updated the default `Cmd+R` behavior to refresh the current page using `webView.reload()` (which is exactly what the toolbar's Refresh button does), instead of instantiating/reloading the service from scratch.
- **Icon Picker Menu**: Refactor picker into a unified 64x64 plain Menu button.
- **Local AI Templates**: Updated custom CSS transparency rules and input focus selectors for `oMLX` and `llama.cpp`.

### Fixed

- **Favicon Resolution**: Support SVG/base64 inline data URIs, force IPv4 for localhost, and fix Grok/squircle color template clipping.
- **Concurrency & Memory Leak Fixes**: Isolated `WebViewManager`, `ConfigPortManager`, and `ShortcutValidator` to `@MainActor`, resolved KVO observer leaks in `MainWindowController.deinit`, and fixed `CheckedContinuation` leaks in `WebViewManager.tearDown`.

## [3.2.0] - 2026-05-23

### Added

- **Engine Icon Management System**: Implemented a comprehensive engine icon management architecture, supporting dynamic Visual Identification for custom browser engines.
- **High-Reliability FaviconFetcher**: Built an asynchronous, multi-tiered favicon resolution engine in [FaviconFetcher.swift](Quiper/Components/FaviconFetcher.swift) that scrapes website HTML for custom icon links, checks direct `/favicon.ico` endpoints, and falls back to the Google Favicon API, auto-resizing images to 32x32 pixels and converting them to PNG-encoded base64 strings.
- **Background Startup Enrichment**: Added automated backfilling of legacy engines' icons on application startup in [Settings.swift](Quiper/Settings.swift), running non-intrusively in background tasks.
- **SwiftUI Interactive Icon Selector**: Created a premium, hover-interactive icon picker in [ServiceDetailView](Quiper/SettingsView.swift) supporting:
  - File picker for manual uploads (`.png`, `.jpeg`, `.image` formats).
  - One-click automatic scraping trigger.
  - Debounced (1s) auto-fetching while typing URLs.
  - Focus-loss trigger for immediate URL resolution.
  - Option to manually remove icons and unset them.
- **Dynamic Empty State Favicons**: Enhanced [EngineRowView](Quiper/Components/EmptyStateView.swift) to dynamically decode and render configured base64 icons at the leading edge of directory items, falling back gracefully to a system symbol (`globe`) when none is set.
- **Engine Activation Preferences**: Added a new setting `autoCreateSessionOnEmptyEngineActivation` (default `true`) allowing users to choose whether switching to an engine with no open sessions immediately instantiates a new session or displays the clean empty state directory instead. Explicit user actions like session digit shortcuts (Cmd+1...9) bypass this check to force session creation.
- **Local AI Engines**: Integrated `llama.cpp` (running on `http://localhost:8080`) and `oMLX` (running on `http://localhost:8000`) into the default engines registry in [Settings.swift](Quiper/Settings.swift).
- **Settings Sidebar Favicons**: Replaced the hardcoded generic "globe" icon in the Settings sidebar list with each engine's dynamically-resolved base64 favicon in [SettingsView.swift](Quiper/SettingsView.swift), utilizing a graceful system fallback if no icon is set.
- **Automatic Template Favicon Fetching**: Implemented automatic favicon enrichment when adding a service in [SettingsView.swift](Quiper/SettingsView.swift)—either solo from a template or in bulk via `"Add All Templates"`. Individual template additions trigger immediate async fetches, while bulk additions cleanly batch and coalesce into a single unified fetch call at the end of the operation, avoiding concurrent duplicate task spawning.

### Changed

- **Agent Guidelines**: Updated [AGENTS.md](AGENTS.md) behavior rules to establish a clear expectation that zero compiler warnings are acceptable across all implementation and refactoring tasks.
- **Default Engine Switch Behavior**: Flipped the default value of `automaticallySwitchEngineOnLastSessionClose` to `true` to match intuitive tab workflows where closing the last session of an engine automatically switches to another active engine.
- **Tabular Session Directories**: Implemented a neat, three-column tabular layout for the nested session rows containing a right-aligned monospaced digit index column, a fixed dot column, and a natural, left-aligned title column. This prevents jagged offsets and aligns the separator dots vertically.

### Fixed

- **Favicon Fetcher Local Engine Enhancements**: Resolved port-stripping bugs inside [FaviconFetcher.swift](Quiper/Components/FaviconFetcher.swift) when resolving direct `/favicon.ico` fetches and scraped HTML link tags, correctly retaining target port numbers (e.g. `:8080`, `:8000`) instead of stripping them and defaulting to port 80.
- **Local Scheme Auto-Normalization**: Added automatic fallback to `http://` instead of `https://` when resolving `localhost` and `127.0.0.1` URLs that lack an explicit protocol scheme in [FaviconFetcher.swift](Quiper/Components/FaviconFetcher.swift).
- **Local SSL/TLS Validation Bypass**: Added custom `FaviconFetcherSessionDelegate` to permit self-signed or invalid SSL/TLS certificates specifically on `localhost`, `127.0.0.1`, and `*.local` connections.
- **Dynamic Theme Resolution on Engine Switch**: Resolved a fundamental AppKit color-resolution bug where calling `.withAlphaComponent()` on dynamic system colors (`.labelColor`, `.secondaryLabelColor`) at view-construction time permanently stripped their dynamic catalog traits, rasterizing them against whatever `NSAppearance.current` happened to be active. When views were rebuilt programmatically outside of standard draw cycles (e.g. engine switches), colors baked in light-mode values on a dark-mode window. Root-cause fix: replaced all statically-resolved alpha colors with `NSColor(name:dynamicProvider:)` factory colors that re-resolve at draw time, and switched `CALayer` color updates from `viewDidChangeEffectiveAppearance` to `updateLayer()` (the proper AppKit hook guaranteed to run under the correct appearance context). Removed the nuke-and-rebuild `viewDidChangeEffectiveAppearance` override and its four cached `last*` properties, which are no longer needed.
- **Single Source of Truth for Session Instantiation**: Unified all session switching and creation routines into `switchSession(to:)` as a Single Source of Truth. Resolved a critical bug where clicking a session number in the segment selector during the empty state page was ignored due to redundant preference checks inside `updateActiveWebview()`. Clicking a session segment now correctly forces instantiation and cleanly transitions out of the empty state, matching keyboard shortcut behavior exactly and eliminating duplicated logic blocks in `handleCommandShortcut()`.
- **Swift 6 Strict Concurrency Warning Compliance**: Refactored `ServiceDetailView` async tasks and `FaviconFetcher` to safely pass Sendable `Data` and copyable `UUID` keys across actor boundaries instead of non-Sendable `@Binding var service` references or AppKit `NSImage` objects. Fully isolated all graphics-context rendering blocks to `@MainActor`.
- **Empty State Missing Variable Compilation**: Restored the accidentally deleted `labelText` definition inside the engine enumeration loop of `EmptyStateView.swift` to resolve compiler errors and restore correct engine and session count labels.
- **Empty State Alignment & RTL Safety**: Added dynamic layout-direction-aware edge insets and `.natural` text alignments to both `EngineRowView` and `SessionChildRowView`, ensuring perfect natural alignment for both LTR and RTL directions. Introduced explicit, instant header centering calculations on engine shifts before any scroll occurs, avoiding off-center text alignment.
- **Session Selector Stale State**: Resolved an issue where selecting an engine with no open sessions could show the last active session of that engine as active in the session segmented control. The session selector is now cleanly deselected (set to `-1`) whenever the empty state is active.
- **Dynamic Theme Synchronization**: Resolved a synchronization failure where the [EmptyStateView](Quiper/Components/EmptyStateView.swift)'s labels, icons, hover highlights, and shortcut key pills did not dynamically adapt to system appearance changes (light/dark mode shift) or manual theme overrides without an application restart. Refactored the static key pill layout into a reactive `KeyPillView` subclass, added `viewDidChangeEffectiveAppearance()` overrides to the subview hierarchy, and enabled automatic, dynamic reconstruction of the empty state layout on appearance transitions.
- **Empty State Controls and Shortcuts Isolation**: Resolved a core architectural issue where computed getters like `activeWebView` and `currentWebView()` lazily instantiated and warmed up background webview sessions on any query (such as window focus restoration, Find bar activations, reload events, or zoom resets) while in the empty state. Refactored both properties into completely passive getters that query the `webViewManager` without side effects, preventing any accidental session warming. Additionally, updated `layoutSelectors()` and `showEmptyState()` to cleanly hide all top-bar navigation, reload, and action controls when no sessions are active, and added a shortcut interceptor to elegantly consume and suppress irrelevant key commands.

## [3.1.0] - 2026-05-17

### Added

- **Empty State Page**: Introduced a dedicated "No open sessions" page that appears when all sessions are closed, featuring a responsive grid of configured engines and their keyboard shortcuts.
  - Engine rows are interactive; clicking a row instantly launches the engine.
- **Navigation Buttons**: Added native back and forward navigation buttons to the top bar.
  - Implemented a custom `NavigationButtonGroup` that renders as a unified, glassy capsule.
  - Buttons automatically show/hide based on `WKWebView` history availability (`canGoBack`/`canGoForward`).
  - Added a long-press history menu (Safari/Chrome style) for both buttons to navigate directly to any page in the history stack.
- **Refresh/Stop Button**: Added a dedicated button after the title that toggles between "Reload" (clockwise arrow) and "Stop" (x-mark) icons based on the current loading state.
- **Find Bar Close Button**: Added a dedicated "Done" button to the find bar overlay, allowing it to be closed via mouse click in addition to the `Escape` key.
- **Close with Middle Click**: Middle-clicking a session closes it immediately, navigating to the nearest other open session or engine. Middle-clicking an engine closes all of its open sessions — a confirmation dialog is shown unless it has exactly one open session and is the currently active engine.

### Changed

- **Session State Reset**: Closing the last active session of an engine now resets its active session index to the first session, ensuring it opens fresh the next time the engine is launched.
- **Selector Alignment**: Dropdown panels for engine and session selectors now open directionally (left/right) to prevent obscuring their buttons in the empty state.
- **Top Bar Layout**: Re-architected the middle section of the top bar to position navigation buttons immediately before the title and the refresh/stop button immediately after it.
- **Auto-Mode Threshold**: Updated the "Auto" display mode calculation to account for the new navigation and refresh/stop buttons, ensuring the title area remains readable.
- **Reset Zoom Shortcut**: Changed the "Reset Zoom" shortcut from `Cmd+Backspace` to `Cmd+Shift+Backspace` to prevent accidental resets while typing. This is reflected in the View menu, shortcut validator, and manual key event handling.

### Fixed

- **Dynamic Popup Window Titles**: Replaced the hardcoded "Login" prefix in internal popup window titles with dynamic key-value observation (KVO) on the popup webview's title property, falling back gracefully to the service name if the page title is empty.
- **Disabled Global Shortcut Mapping**: Fixed a Carbon API registration issue where clearing/unsetting the main global shortcut registered the physical `A` key (keycode `0`) without modifiers as the hotkey and displayed `"A"` in the status bar menu.
- **Find Bar on Window Hide**: Fixed an issue where the find bar (Cmd+F) would remain visible on screen after the global shortcut hid the main window. The find bar is now explicitly closed when the window hides, and it does not reappear on the next window show.
- **Selector Synchronization**: Fixed an issue where the "Engines" placeholder could persist in the engine selector when transitioning out of the empty state.
- **Memory Leaks in Tab Closure**: Resolved multiple issues where closed tabs would fail to release memory, causing it to accumulate in `kernel_task`.
  - Added explicit `stopLoading()` and delegate nil'ing to signal WebKit to terminate background processes.
  - Fixed an issue where orphaned "wrapper" views remained in the view hierarchy after tabs were closed.
  - Implemented `WKUserContentController` cleanup to break configuration-level retain cycles.
- **Popup Window Retain Cycle**: Fixed a self-delegate retain cycle in login/modal popups that prevented them from being deallocated after closing.
- **Find Bar Hover Leaks**: Re-architected the find bar to host its content in a dedicated child `NSPanel` window instead of a subview. This genuinely blocks all mouse hover and scroll events from "leaking" through to the `WKWebView` underneath, resolving an issue where background elements would react to mouse movement over the find bar.

## [3.0.0] - 2026-05-08

### Added

- **Build Provenance Attestation**: All release builds are now stamped with a GitHub artifact attestation — a cryptographically signed record linking the binary to the exact source commit and workflow run that produced it. Verify any release disk image with `gh attestation verify Quiper.dmg --repo sassanh/quiper`.
- **Reproducible CI Builds**: Release artifacts are produced exclusively by GitHub Actions. The README now documents this and explains how to verify the provenance of any downloaded build.

- **Hierarchical Update Channels**: Refactored update settings into a single, intuitive channel selector (Stable, Beta, Nightly).
  - Introduced an inclusive selection UI where choosing a more experimental channel automatically encompasses all stable and pre-release updates to its left.
  - Added seamless data migration to preserve existing user update preferences.

- **Two-Window Architecture for High-Performance Blur**: Implemented a dual-window system that separates window structure from background effects.
  - The main "Host" window handles resizing and UI controls with a minimal blur radius of 1, ensuring the entire frame remains hit-testable for resizes while maintaining a truly transparent border when the bar is hidden.
  - A dedicated "Guest" child window provides hardware-accelerated background blurring using the optimized SkyLight private API, supporting custom user-defined blur radii.
  - Automatically synchronizes geometry and corner radii between windows and manages state resets during application switching for robust multitasking behavior.

- **Expanding Frame Auto-Hide Bar**: When the top/bottom bar is in auto-hide mode, hovering near the window edge reveals the bar outside the content area via an animated border ring — preventing accidental clicks on web content underneath.
  - A thin outline ring is always visible around the window to mark its boundary, fading out when the thick border is revealed.
  - The window casts a drop shadow to distinguish it from windows beneath.

- **Selector Auto-Collapse**: Collapsible selectors now reliably collapse when the cursor moves away, regardless of how they were opened (hover or keyboard shortcut). Collapse policy is centralised in the window controller via a cursor-position monitor rather than being owned by the selector itself.

 and "self-healing," allowing for seamless imports of configuration files from older versions even as the internal schema evolves.

- **Detailed Import Diagnostics**: Failed configuration imports now provide specific technical feedback (e.g., exactly which field or data type is missing/incorrect) instead of generic error messages.

### Fixed

- **CI/CD Test Stability**: Resolved intermittent "Failed to get matching snapshot" timeouts in UI tests.
  - Skipped the Cmd+H (Hide) test, which was causing WebKit snapshot timeouts due to macOS suspending the process.
  - Replaced high-overhead `XCTNSPredicateExpectation` with a more efficient polling mechanism in `BaseUITest`.
  - Optimized verification loops in `LaunchShortcutsUITests`, `NavigationShortcutsUITests`, and `ReorderServicesUITests` to reduce accessibility snapshot pressure on `WebContent` processes.
- **Settings Migration Path**: Added comprehensive fallback mechanisms for all core configuration structures (`Service`, `AppShortcutBindings`, `CustomAction`, `WindowAppearance`), ensuring the app can gracefully recover data from partial or outdated `.quiper` files.
- **Beta Update Channel**: Users can now opt-in to manually-triggered pre-release builds in Settings → Updates. This allows testing of new features before they are officially released without needing to use the more experimental nightly builds.
- **Smart Selector Display Mode**: The "Auto" display mode now dynamically switches between static and compact (collapsible) selectors based on available window width.
  - It automatically collapses whenever there isn't enough room to show at least 120px of the page title between the selectors.
- **Configurable Drag Area Position**: Added a new setting in Appearance → Top Bar to toggle the window drag area between the top and bottom edges of the window.
  - All layout components (web views, find bar, and mouse-hover tracking areas) dynamically adjust their positioning based on the selected setting.
- **Media Capture Support**: Enabled camera and microphone access within webviews.
  - Implemented `WKUIDelegate` hooks to automatically bridge website media requests to the native macOS permission system.
  - Added required camera and microphone hardware entitlements and usage description strings.
- **Header Visibility and Modal Windows**: Implemented a robust, declarative `hasModalWindow` system to ensure the auto-hiding header remains hidden whenever the Settings window or any other modal dialog is open.
- **Selector Expansion Race Condition**: Fixed a race condition where rapidly toggling modifiers could cause animating-out selector panels to be incorrectly classified as modal windows, leading to the header being stuck in a hidden state.
- **CI Test Reliability**: Added `skipModalCheck` to `MainWindowController` to allow unit tests to bypass environmental modal window checks, resolving intermittent failures in CI.
- **Selector Expansion Preferences**: Modifier key expansion now correctly respects the `showHiddenBarOnModifiers` setting, preventing accidental header reveals when keyboard reveals are disabled.
- **Mouse Hover Tracking on Move**: The 50pt sensory area for revealing the hidden header now correctly switches to the bottom edge when the drag area position is set to `.bottom`.
- **Selector Expansion Blocked by Modal Windows**: Modifier-key selector expansion (e.g. holding `Cmd` to reveal engine/session digits) is now suppressed whenever any modal window is open. The check is generic — not tied specifically to the settings window — so it covers all future modal dialogs as well.
- **Settings Window Color Scheme**: Changing the app's color scheme (Light/Dark/System) in Appearance settings now also updates the Settings window immediately. Previously only the main window was updated.
- **Reset Zoom Menu Shortcut**: The reset zoom menu item in the View menu now correctly shows its shortcut "⌘+⌫".
- **Customizable Window Border**: The window outline color and width are now configurable per theme (Light/Dark) in Appearance settings. Width ranges from 0 (hidden) to 4 pt in 0.5 steps; color supports full opacity control.
- **Background Opacity in Color Picker**: The separate Opacity slider has been removed. Background opacity is now set directly through the color picker, which now supports transparency.
- **Selective Web View Corner Masking**: Web view corners are now only rounded on the edge opposite the bar (top bar → bottom corners rounded, bottom bar → top corners rounded), matching the window shape more precisely.
- **Reduced Window Corner Radius**: Corner radius tightened from 10 pt to 6 pt for a cleaner, more modern look.
- **Loading Spinner Alignment**: Vertically aligned the title's loading spinner with the selectors and reduced internal padding for a more balanced layout.
- **Loading Spinner Animation**: Improved animation continuity by switching to a dash-phase based loop, resolving a visual glitch where the spinner would break at the path's seam.
- **Collapsible Selector Hover Expansion**: Fixed hover expansion for selectors when the window is not the key window (e.g., in accessory mode) and ensured they expand immediately when the top bar is revealed under the cursor.
- **Collapsible Selector Behavior**: Selectors now stay open during drag-reordering and after selection, only closing when the mouse leaves the safe zone.
- **Collapsible Selector Accuracy**: Fixed segment hit-testing to accurately handle variable-width labels by using actual rendered frames.
- **Collapsible Selector Stability**: Fixed a memory leak in tracking area management and resolved an issue where dragging would trigger premature collapsing.
- **File Selector Modal Lockup**: Fixed an issue where hiding the application via the global shortcut while a file picker (`NSOpenPanel`) was open would permanently detach the dialog, causing the web view to lock up. The application now auto-cancels any active file pickers gracefully before hiding.

## [2.9.0] - 2026-04-22

### Added

- **Config Export / Import**: Added Export and Import buttons in Settings → General. Exports all settings and action scripts to a single `.quiper` JSON file that can be imported on any machine.

### Fixed

- **Update Detection**: Completely rewrote the mechanism for tracking newer releases. The app now embeds the `GITHUB_RUN_NUMBER` generated during continuous integration as its internal Build Number. The GitHub update payload explicitly includes this number `<!-- BuildNumber: X -->`, ensuring that date-drifting and identical nightly version strings no longer trigger infinite update loops.

## [2.8.1] - 2026-04-22

### Fixed

- **Update Detection**: Fixed a bug where the app's build date was read from the `creationDate` of `Info.plist`, which is preserved when extracting zip archives and therefore always appeared older than the latest release. The app now reads the `modificationDate` of the executable binary, which is reliably set by the linker at build time.

## [2.8.0] - 2026-04-21

### Added

- **Auto-Hiding Top Bar**: Added a new "Hidden" visibility mode for the top bar header.
  - Header renders as an overlay (floating over web content) when hidden, increasing vertical space.
  - Reveal triggers: Mouse hover near the top edge (8pt trigger zone), holding tab/engine shortcut modifier keys, or during session/service switches (0.75s).
  - Added "Show on Modifier Keys" toggle in Appearance settings to allow disabling keyboard-driven reveals.
- **Top Bar Visibility Unit Tests**: Added comprehensive test suite covering settings, alpha state management, modifier key detection, and temporary reveal triggers.
- **Nightly Update Channel**: Added an opt-in setting in the Updates tab to follow experimental build streams.
- **Date-Based Update Checking**: Replaced semantic version parsing with publication date comparisons. This ensures nightly builds are correctly detected based on when they were released, even if the version string is unchanged.
- **CI/CD Maintenance**: Updated GitHub Actions dependencies (Checkout to v6 and Upload-Artifact to v7) for improved reliability.
- **Gray Accent Color**: App accent color is now gray via an `Assets.xcassets` color set, replacing the system accent color.

### Changed

- **UI Refinements**: Improved Segmented Control styling for instantiation state and selected segments, refined Collapsible Selector animations, and updated Settings layout logic.
- **Screenshot Generator**: Updated hero screenshot generation to snapshot the app element instead of the overlay window.

### Fixed

- **Dock Icon Not Removed on Hide**: `Cmd+Q`, `Cmd+H`, and the in-window hide menu item now correctly run the full hide lifecycle (dock policy update, settings dismissal, focus restore). Previously, these paths called `MainWindowController.hide()` directly, bypassing the logic in `AppController.hideWindow()`. The window controller now posts `windowDidShow`/`windowDidHide` notifications after each visibility change, and `AppController` observes them to consistently apply all lifecycle side-effects regardless of what triggered the hide or show.

## [2.7.2] - 2026-02-23

### Added

- **Window Size Toggle**: Added fixed keyboard shortcut `Cmd+M` to toggle between compact and previous window modes.
  - **Compact Mode**: Fixed 550×400 pixels window positioned at top-right corner.
  - **Previous Mode**: Restores the window to its previous size and position before entering compact mode.
  - Falls back to default 800×620 centered window if no previous size is available.
  - Includes smooth animations and proper layout updates after resize.
  - Added comprehensive UI test suite with 3 tests covering main functionality, multiple toggles, and edge cases.

- **Instantiation State Indicators**: Service and session selector segments now visually distinguish between instantiated (warm, webview loaded) and uninstantiated (cold, no webview) tabs.
  - Uninstantiated segments render with a dimmed overlay and lighter text so users can see at a glance which slots have been used vs. are empty.
  - A service is considered instantiated if any of its sessions has a loaded webview; a session is instantiated if its specific webview exists.
  - Works across both `CollapsibleSelector` and static `SegmentedControl` variants, and updates automatically when switching services.
  - Added UI test suite in `InstantiationStateUITests.swift` covering navigation heuristics.

- **Cmd+W Closes Tab**: Pressing `Cmd+W` now uninstantiates the current session and navigates to the nearest previously-used tab (browser-style heuristics: left sessions → right sessions → left services → right services → fallback to session 0) instead of hiding the app.

### Fixed

- **Service Reorder UI Test**: Improved reliability of `ReorderServicesUITests` with better timing and element selection.
  - Increased animation settling timeouts from 1.0 to 2.0 seconds.
  - Added fallback retry logic for segment tapping with improved element selection.
  - Enhanced sync verification between settings window and main window selector.

## [2.7.1] - 2026-02-22

### Fixed

- **CI/CD Test Stability**: Resolved intermittent failures in `testModifierKeysExpandSessionSelector` and `testModifierKeysExpandServiceSelector`.
  - Introduced `skipSafeAreaCheck` in `MainWindowController` to allow reliable keyboard-driven selector expansion in headless test environments.
  - Replaced fixed delays with robust polling mechanisms in modifier key tests, improving execution speed and reliability.
- **Inspector Visibility**: Fixed an issue where docked Developer Tools would not hide correctly when switching sessions or would appear blank when returning. Each session now uses a dedicated container view to reliably manage the visibility of both the web content and its inspector.

## [2.7.0] - 2026-02-21

### Added

- **Screenshot Generation**: Introduced a robust, automated screenshot generation system for marketing and documentation.
  - Added `generate-screenshots.sh` script to automate the entire flow: capture, WebP conversion (80% quality), and asset deployment.
  - New `ScreenshotGenerator` UI test with both Interactive (human-verified) and Non-Interactive (automated) modes.
  - Added `ScreenshotPromptController` for a floating "Take Screenshot" UI during interactive capture.
  - Added `--screenshot-mode` argument to force a 640x480 window size optimized for documentation.
- Added "Claude" to the list of service templates.
- **File Attachment Support**: Implemented `runOpenPanelWith` in the WebKit delegate, allowing the "Attach File" button to function correctly in engines like ChatGPT and Claude.
- **JavaScript Dialogs**: Added support for standard web dialogs (`alert`, `confirm`, and `prompt`) within both main and popup webview windows.

### Changed

- **Improved Selector Accessibility**: Added dedicated accessibility identifiers to `CollapsibleSelector` and `LoadingBorderView` for more reliable UI testing.
- **Claude Action Scripts**: Updated Claude's default action scripts for better compatibility with its latest UI, including improved "New Session" and "Temporary Session" (incognito) logic.
- **JavaScript Execution**: Switched custom action execution to `.page` content world for better compatibility with modern web app security models.

### Fixed

- **Modal Popup Stability**: Fixed a crash that occurred when closing modal popup windows (e.g., Google login windows in Claude or Grok).
- **Focus Restoration**: Improved reliability of restoring focus to the main window after closing a popup or the Settings window.
- Compability: Update open-webui actions to be compatible with the 0.7.2 version
- Compability: Update Gemini actions to be compatible with the latest Gemini UI
- **DevTools Keyboard Shortcuts**: Improved keyboard shortcut handling to prevent app-level shortcuts (like Find, Zoom, and Service switching) from firing when Developer Tools are focused (both docked and separate window). This allows DevTools to consume native shortcuts like `Cmd+F` and `Cmd+G` for its own functionality.

## [2.6.0] - 2025-12-27

### Added

- **Custom Blur Radius**: Implemented precise variable blur control for window background.

### Changed

- **Window Hierarchy**: Updated window hierarchy handling to support dynamic removal of effect views, improving performance and test reliability.

## [2.5.1] - 2025-12-24

### Fixed

- **Color Settings Saving**: Fixed potential color data corruption when saving custom colors by ensuring safe sRGB conversion (`CodableColor`).
- **Focus Restoration**: Fixed an issue where the main window would not regain focus after closing the Settings window via the close button. Implemented robust async focus restoration and updated UI tests to verify strict focus state.

## [2.5.0] - 2025-12-24

### Added

- **Modifier Key Expansion**: Holding the modifier keys for session (e.g. `Cmd+Shift`) or service (e.g. `Cmd+Ctrl`) shortcuts now automatically expands the corresponding collapsible selector in the header for quick visibility.
- **Color Scheme Control**: New appearance setting to force Light or Dark mode, or follow the system setting.
- **Per-Theme Window Backgrounds**: Window appearance settings (blur material or solid color) can now be configured separately for Light and Dark themes. When using "System" color scheme, both theme settings are shown for customization.

### Changed

- Updated default window appearance to use "Solid Color" mode with a refined teal-grey tint.
- **Documentation Refined**: Reorganized `README.md` for better flow and clarity, updated all screenshots with fresh 80% WebP assets, and added 'Custom Actions' documentation.
- Service Hotkeys Layout: Reverted to pre-2.4.0 vertical layout in `ServiceLaunchShortcutRow` for improved clarity.

### Fixed

- **Blur Material Updates**: Fixed blur material style changes not applying on macOS 26 (Tahoe) by using `NSVisualEffectView` consistently across all macOS versions.
- **Solid Color Background**: Fixed solid color mode rendering incorrectly (either covering all content or showing nothing). Now uses a refactored view hierarchy with a dedicated container view to robustly handle both solid and blurred backgrounds.

## [2.4.0] - 2025-12-22

### Added

- Added unit tests for `CollapsibleSelector` to verify initialization, state management, and delegate callbacks.
- **Custom CSS Injection**: Added support for injecting custom CSS into engine sessions.
  - Added "Custom CSS" editor in Engine settings, allowing users to override styles for any service.
  - Configured default transparent backgrounds for ChatGPT, Gemini, Grok, X, and Google to leverage the new WebView transparency.
- **Appearance Settings Tab**: New dedicated tab for visual customization, containing Dock icon visibility and Selector display mode settings.
- **Updates Settings Tab**: Separated update-related settings (version info, check/download preferences) into their own tab.
- **Window Appearance Settings**: Added configurable window background options:
  - Choose between blur effect (with selectable material) or solid color mode
  - Solid color mode includes color picker and opacity slider
  - Changes apply in real-time without restart

### Changed

- Refactored `MainWindowController` logic into dedicated `WebViewManager` and `FindBarViewController` components to improve code organization.
- **Xcode Integration**: Modified the "Quit Quiper" shortcut to behave efficiently based on the environment:
  - **Xcode Environment**: Uses `Cmd+Q` to allow quick quitting during development, preventing accidental quits of the production app.
  - **Standard Environment**: Retains the safe `Cmd+Ctrl+Shift+Q` shortcut to prevent accidental quits during normal usage.
- **WebView Transparency**: Enabled `drawsBackground = false` on WebViews, allowing the window background to show through when the loaded page has a transparent background.
- Renamed `OverlaySegmentedControl` to `SegmentedControl` and moved it to a dedicated file for clarity.
- **Settings Reorganization**: Restructured settings into five focused tabs: Engines, Shortcuts, General, Appearance, and Updates.
- **Global Shortcut**: Moved the "Show/Hide Quiper" shortcut from General to the Shortcuts tab for better discoverability.
- **Code Structure**: Extracted reusable `SettingsSection`, `SettingsRow`, `SettingsToggleRow`, and `SettingsDivider` components to `Components/SettingsComponents.swift`.
- **File Naming**: Renamed `ActionsSettingsView.swift` to `ShortcutsSettingsView.swift` to better reflect its contents.
- **Service Hotkeys Layout**: Updated `ServiceLaunchShortcutRow` to match the compact horizontal layout used by custom action rows.

### Fixed

- **Service Selector Tooltips**: Fixed tooltips always appearing on hover. Tooltips now only appear when the label is truncated.
- **Collapsible Selector Drag**: Fixed drag-and-drop reordering not working in the collapsible service selector's expanded view.

## [2.3.0] - 2025-12-21

### Added

- Collapsible selectors: Introduced `CollapsibleServiceSelector` and `CollapsibleSessionSelector` for a more compact header.
- "Selector Display" setting: New option in Startup settings with **Expanded**, **Compact**, and **Auto** modes. **Auto** mode dynamically switches to compact view when the window width is below 800px.
- Syncing selectors: Both static and collapsible selectors stay perfectly in sync when switching engines or sessions.
- **Fast Selector Tooltips**: Added custom fast-appearing tooltips (200ms delay) to service and session selectors (both static and collapsible) to show full names and page titles on hover. Tooltips are left-aligned and positioned below the elements.
- **Fast Title Tooltip**: Hovering over the page title in the header now shows a fast-appearing custom tooltip with the full title.
- **Tests**: Added `HybridSelectorInteractionsUITests` to test the functionality of the collapsible selectors.
- **CI**: Configured automated upload of the full `TestResult.xcresult` bundle on failure. This provides comprehensive debugging data (screenshots, logs, and timelines) for diagnosing flaky UI tests in GitHub Actions.

### Changed

- Unified settings management: Centralized settings window logic in `AppController` to reduce duplication and improve reliability.

### Fixed

- Fixed friend domain navigations (like X login in Grok) opening in native apps instead of staying in the webview. Uses a WebKit policy that bypasses Universal Links for configured friend domains.
- Fixed a bug where dragging to reorder engines would unexpectedly open the settings window due to circular notification triggers.
- Fixed synchronization issues where newly reordered services weren't immediately reflected in the collapsible overlay.

## [2.2.3] - 2025-12-17

### Fixed

- Fixed "Operation not permitted" error during updates by implementing manual post-build code signing. This allows the app to retain necessary entitlements (e.g., `downloads.read-write`) without Xcode automatically enforcing the App Sandbox, which blocks self-updates.
- Fixed flaky `testClearWebViewData` test by replacing fixed delay with polling expectation.

## [2.2.2] - 2025-12-16

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

- Added a default “Open WebUI” service pointing to <http://localhost:8080> with focus selector, new-session that clears temporary mode, new-temporary-session that enables it, and reload script.

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
