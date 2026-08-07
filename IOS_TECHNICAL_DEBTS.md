# Quiper iOS/iPadOS Port — Technical Debts & Parity Roadmap

This document tracks the iOS/iPadOS port of Quiper. The macOS app is a
hotkey-launched overlay browser; iOS has no such interaction model, so the iOS
build reimagines Quiper as a native, full-screen, multi-engine browser
(sessions, prompt focus/fill, prompt history, notifications, settings).

The goal is **eventual full feature parity** with the macOS app for everything
that can map to mobile, replacing macOS-only machinery with the closest iOS
equivalent. This file records what is deferred, why, and what a future
iteration must do.

## Status

- **Milestone 0 (shipped):** Shared pure-Foundation core extracted to
  `QuiperShared/`, iOS/iPadOS target added, native SwiftUI browser shell with
  engine list, sessions, prompt focus/fill, prompt history, notification bridge,
  engine icons, and settings.
- **Milestone 1 (mostly shipped):** Custom actions/action scripts are ported and
  session/tab persistence now matches macOS (last-visited URL restore +
  save-on-background). Remaining: encrypted engine storage (Keychain) and the
  code-editor container.

## Platform adaptation model

The macOS app is 24.5k lines across ~70 files, of which 49 import AppKit. The
port does **not** try to compile AppKit code for iOS. Instead:

1. Pure Foundation/WebKit logic that is genuinely cross-platform lives in
   `QuiperShared/` and is compiled into **both** targets.
2. macOS-only surface (windows, hotkeys, menu bar, status item, encrypted disk
   volumes, updater, login items, App Intents, TemplateValidationServer) stays
   in the macOS target.
3. iOS gets a SwiftUI shell in `QuiperiOS/` that reuses the shared core and
   reimplements only the presentation layer.

### Mapping macOS concepts to iOS

| macOS | iOS/iPadOS |
| --- | --- |
| Overlay window + global hotkey show/hide | Full-screen browser; app-switch or scene to bring forward |
| Menu-bar status item | None (standard app); settings inside the app |
| Per-engine global shortcuts (`HotkeyManager`) | None; engine switching via UI |
| Session tabs + Cmd+N / Cmd+Shift+N | Session picker + "New session" button |
| Unified composer + focus injection (`focus_selector`) | Prompt fill injection into the focused web page |
| Encrypted sparsebundle volumes | Deferred → Keychain-based key + local encryption (debt #2) |
| `UpdateManager`/`UpdateInstaller`/launch agents | Deferred → App Store updates (debt #9) |
| Dock visibility / LSUIElement | N/A (normal iOS app lifecycle) |
| `NSAlert` migration prompts | Deferred → in-app sheet equivalents (debt #6) |

## Parity matrix

| macOS feature | iOS status | Debt |
| --- | --- | --- |
| Engine list (defaults + user-defined) | ✅ shipped | — |
| Sessions/tabs per engine | ✅ shipped (simplified) | #12 |
| Prompt focus + fill via `focus_selector` | ✅ shipped | — |
| Prompt history (store, reuse, limit, clear-on-submit) | ✅ shipped (core) | #12 |
| Web notifications via `WebNotificationBridge` | ✅ shipped (shared bridge) | #8 |
| Engine icons (favicon fetch + defaults, macOS/iOS shared) | ✅ shipped | — |
| Settings (engines, prompt history, appearance, tab survival) | ✅ shipped (subset) | #11 |
| Session/tab persistence & restore (URL parity) | ✅ shipped | #12 |
| Custom actions + action scripts (JS injection) | ✅ shipped | — |
| Code-editor container (CodeMirror) | ⏳ deferred | #3 |
| Find bar | ✅ shipped (shared find script) | #4 |
| Ghost onboarding / HUDs / tooltips | ⏳ deferred | #6 |
| Engine metadata migration & secure bundle | ⏳ deferred | #2 |
| Encrypted engines (sparsebundle/diskutil) | ⏳ deferred | #2 |
| Update manager / installer / launch-at-login | ⏳ deferred | #9 |
| App Intents / shortcuts / digit shortcuts | ⏳ deferred | #10 |
| Settings parity (appearance materials, drag area, bar visibility, HUDs) | ⏳ deferred | #11 |
| Routing rules (internal/popup/prompt/external) | ✅ shipped (shared `RoutingResolver`) | #13 |
| Custom CSS injection | ✅ shipped (shared script) | #13 |
| Camera/mic permission prompting in web views | ✅ shipped | #14 |
| Template validation server / interactive screenshots | ⏳ deferred | #15 |
| Unit/UI test parity | ⏳ deferred | #16 |

Legend: ✅ shipped · ⏳ deferred, ordered below.

## Debts (ordered by priority)

### #1 Shared model & action-script extraction ✅ DONE
The macOS models (`Service`, `CustomAction`, `RoutingRule`, `Settings`,
`PersistedSettings`, `PersistedTabState`, …) were entangled with AppKit types.
Extraction is complete: platform-neutral Codable models and pure logic now live
in `QuiperShared/` (`SharedModels.swift`, `SharedSettings.swift`,
`DefaultEngineDefinitions.swift`, `DefaultActions.swift`, `WebScripts.swift`,
`InputStatePayload.swift`, `SessionSlots.swift`, `TabRestoration.swift`,
`LinkRouting.swift`), and
both targets consume the same types. Custom actions and their JS action scripts
are fully ported (`AppEnvironment.runAction` + shared fallback scripts).

Residual: routing and CSS now share `QuiperShared` implementations with macOS
(see #13); remaining gap is file-backed `CustomCSSStorage` on iOS.

### #2 Encrypted engine storage (Keychain)
macOS encrypts engine profiles with sparsebundle volumes via `diskutil`
(`EncryptedVolumeManager`, `SparseBundleMigrationManager`,
`SecureStorageManager`, `LockOverlayView`). None of this exists on iOS.

**Future work:** store engine keys in the iOS Keychain and encrypt at-rest
profiles (e.g., AES-GCM over engine metadata + tab data). Provide a
`SecureStorageManager` equivalent with the same API shape so higher layers
(`LockOverlayView` → `LockOverlayView_iOS`) can be shared later.

### #3 Code-editor container (CodeMirror)
`CodeEditorContainer`, `EditorDocumentSession`, and the bundled
`quiper-code-editor.html/.js` (CodeMirror bundle) power an in-page editor for
prompt/code editing. The HTML/JS assets are platform-neutral and already
shared, but the AppKit container isn't.

**Future work:** `WKWebView`-based `UIViewRepresentable` editor container,
mapping `EditorDocumentSession`'s document/selection/save contract.

### #4 Find bar
`FindBarViewController` provides in-page search.

**Future work:** reuse the same JS find routines in an iOS overlay.

### #5 Hotkey & menu-bar machinery
`HotkeyManager`, `EngineHotkeyManager`, `PreviousTabHotkeyManager`,
`StatusBar`, `MenuFactory`, `ShortcutRecorder`, `ShortcutFormatter`,
`EngineDigitShortcut` are macOS-only. iOS exposes actions via UI instead.
Revisit only if Catalyst/App Intents require shared shortcut configuration.

### #6 Onboarding, HUDs, tooltips, migration prompts
`OnboardingWizard`, `GhostOnboardingManager`, HUDs, `MigrationAlertPresenter`,
and the various `NSAlert` migration prompts are AppKit.

**Future work:** in-app SwiftUI sheets/confirmation dialogs for first-run
onboarding and settings migrations; keep migration predicates byte-identical to
macOS so persisted data stays portable.

### #7 MainWindowController layer
`MainWindowController` + extensions (actions, appearance, downloads,
header-visibility, input-handling, selectors, session-management,
web-view-observers) is the macOS brain. The iOS shell in `QuiperiOS/`
(`AppEnvironment`, `EngineBrowserView`, `WebViewSession`) implements the
equivalent state machine (active engine, active session, composer state)
natively. Revisit only if shared behavior logic is extracted to
`QuiperShared`/`WebViewManager`.

### #8 Notification deep-linking
`NotificationDispatcher` handles tapping a delivered notification to focus the
right engine/session. The shared `WebNotificationBridge` delivers them, and the
iOS app requests notification authorization at launch, but it still ignores
`UNUserNotificationCenter` delegate callbacks.

**Future work:** implement the `UNUserNotificationCenterDelegate` on iOS and
route `didReceive` responses to `browser.selectService`/`switchSession`.

### #9 Updater / install-at-login
`UpdateManager`, `UpdateInstaller`, `Launcher`, `UpdatePromptWindowController`
are macOS-only.

**Future work:** none for iOS binary updates (App Store handles them); keep
`UpdatePreferences` schema for parity of stored settings only.

### #10 App Intents / shortcuts
AppIntents and global digit shortcuts are macOS-only.

**Future work:** App Shortcuts on iOS via App Intents for "open engine X",
"new session", "clear web data", etc.

### #11 Full settings parity
Shipped settings are a subset: engines (including icon fetch/removal),
prompt-history toggles, color scheme, custom actions. Deferred: appearance
materials/blur/outline, drag-area position, top-bar visibility, selector display
modes, HUD toggles, show-on-all spaces, `settingsColorStyle`, zoom,
`appShortcutBindings`, `dockVisibility`, tab-survival policy.

**Future work:** surface the shared `PersistedSettings` schema in an iOS
`Form`/`NavigationStack`; gate macOS-only rows behind `#if os(macOS)` in a
shared `SettingsView`.

### #12 Session/tab persistence parity
URL restore now matches macOS: `QuiperShared/TabRestoration.swift` builds the
restore plan from persisted `openTabs`, `AppEnvironment.restoreTabsState()`
pre-instantiates every saved session with its last URL (the active one loads
immediately, the rest lazily), `WebViewSession` forwards URL/title changes into
`PersistedTabState`, and `QuiperiOSApp` saves when the scene leaves the active
state — mirroring macOS's `restoreTabsState`/`saveTabsState`.

Input-state persistence matches macOS: `WebViewSession` reports per-tab input
state via the shared `TabInputState` (`handleInputState`), `AppEnvironment`
stores it under `preservePrompt` services, and focus restore reuses the shared
`makeFocusInputScript` polling/selection logic (`WebSessionCoordinator` fires
`onDidFinish` → `restoreInputStateIfNeeded`). Prompt-history per-session
restore and legacy `PersistedTabState` migration (`decodeServiceDictionary`
legacy keys) already flow through the shared decoder; `AppEnvironment.load()`
re-saves when legacy identifiers were migrated. The tab-history ring mirrors
macOS: `recordTabHistory(switchingTo:)` keeps a MRU ring capped at
`tabNavigationRingSize − 1` (the setting is now persisted on iOS), and
closed/removed sessions are pruned from `tabHistory`/`tabInputs`.

### #13 Custom CSS injection & routing rules
Custom CSS injection and `RoutingRule` evaluation now share one implementation:
`QuiperShared/LinkRouting.swift` exposes `RoutingResolver` (same-origin,
top-to-bottom rule evaluation, default external) and `QuiperShared/WebScripts`
provides the CSS injection script; both the macOS `WebViewManager` and the iOS
`WebSessionCoordinator` call the same code. On iOS the routing prompt is a
`UIAlertController` and "Always…" choices persist via
`AppEnvironment.rememberRoutingDecision` (`RoutingResolver.applyingRememberedRule`),
matching macOS `rememberDecision`.

Residual gaps:
- `CustomCSSStorage` (macOS file-backed per-service CSS overrides) has no iOS
  equivalent; iOS resolves CSS from `service.customCSS` and the synced template
  default only.
- iOS has no in-app editor for routing rules; rules are only added via the
  routing prompt.

### #14 Media capture permissions ✅ DONE
Camera/microphone permission prompting is shared: `MediaCapturePermission` moved
to `QuiperShared/MediaCapturePermission.swift` (AVFoundation-based TCC bridge)
and used by both targets. iOS `WebSessionCoordinator` implements
`requestMediaCapturePermissionFor` (grant/deny via `ensureAccess`), and both iOS
build configurations carry `NSCameraUsageDescription` /
`NSMicrophoneUsageDescription`.

### #4 Find bar ✅ DONE
The in-page find logic is shared: `WebScripts.makeFindScript` /
`makeResetFindScript` (extracted from the macOS `FindBarViewController`) power
both targets. On iOS, the Actions menu's "Find in Page" opens a find bar in
place of the bottom bar with previous/next/close icon buttons and an in-field
clear button; typing searches via the same debounced matching (300ms) and
highlights as you type.

### #15 Template validation server / interactive screenshot tooling
`TemplateValidationServer`, `ScreenshotPromptController`, and the
`generate-screenshots.sh` flow are macOS-specific development tools. No iOS
equivalent planned; treat as dev-only.

### #16 Test parity
`QuiperTests`/`QuiperUITests` are macOS XCTest targets. iOS needs its own
targets for: shortcut-free model decoding, prompt-history behavior, session
management, and the notification bridge.

## Conventions & rules for future work

- **Web behavior must stay identical.** The input-tracker and notification
  bridge JS live in `QuiperShared/` and are shared verbatim by both targets.
- **Preserve the settings schema.** Any new iOS-persisted field must match the
  macOS `PersistedSettings`/`PersistedTabState` coding keys so a `settings.json`
  remains portable between platforms.
- **Gate, don't fork.** When a file must differ per platform, prefer
  `#if os(macOS)` / `#else` inside a single `QuiperShared/` file over two
  divergent copies.
- **Follow AGENTS.md.** Zero build warnings, Swift 6 strict concurrency,
  `@MainActor` default isolation, 4-space indent, UpperCamelCase types.
