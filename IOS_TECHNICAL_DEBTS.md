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
- **Milestone 1 (shipped):** Custom actions/action scripts are ported, and
  session/tab persistence now matches macOS — last-visited URL restore and
  save-on-background, per-tab input-state (drafts + cursor), per-session prompt
  history, and legacy `PersistedTabState` migration. The double-tap navigation
  ring ships the MRU tab switcher with live thumbnails, hold-to-move
  highlighting, edge auto-scroll, and an expanding selection transition. The
  in-app routing rules editor ships a shared rule row, the portable settings
  surface (behavior, tab survival, prompt-history triggers) is complete, and the
  iOS action-script editor now reuses the shared CodeMirror bundle.
  Remaining: encrypted engine storage (Keychain), file-backed `CustomCSSStorage`,
  and test parity.

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
| Previous-tab / MRU tab-history navigation | Double-tap navigation ring (live thumbnails) |
| Unified composer + focus injection (`focus_selector`) | Prompt fill injection into the focused web page |
| Encrypted sparsebundle volumes | Deferred → Keychain-based key + local encryption (debt #2) |
| `UpdateManager`/`UpdateInstaller`/launch agents | N/A → App Store updates (debt #9) |
| Dock visibility / LSUIElement | N/A (normal iOS app lifecycle) |
| `NSAlert` migration prompts | Deferred → in-app sheet equivalents (debt #6) |

## Parity matrix

| macOS feature | iOS status | Debt |
| --- | --- | --- |
| Engine list (defaults + user-defined) | ✅ shipped | — |
| Sessions/tabs per engine | ✅ shipped (simplified) | #12 |
| Prompt focus + fill via `focus_selector` | ✅ shipped | — |
| Prompt history (store, reuse, limit, clear-on-submit) | ✅ shipped | — |
| Web notifications via `WebNotificationBridge` | ✅ shipped (shared bridge) | #8 |
| Engine icons (favicon fetch + defaults, macOS/iOS shared) | ✅ shipped | — |
| Settings (engines, prompt history, behavior, appearance) | ✅ shipped (portable subset) | #11 |
| Session/tab persistence & restore (URLs, drafts, cursor, tab history) | ✅ shipped | #12 |
| Tab switcher ring (double-tap MRU navigation with live thumbnails) | ✅ shipped | #12 |
| Custom actions + action scripts (JS injection) | ✅ shipped | — |
| Code-editor container (CodeMirror) | ✅ shipped (shared bundle + iOS container) | #3 |
| Find bar | ✅ shipped (shared find script) | #4 |
| Ghost onboarding / HUDs / tooltips | ⏳ deferred | #6 |
| Engine metadata migration & secure bundle | ⏳ deferred | #2 |
| Encrypted engines (sparsebundle/diskutil) | ⏳ deferred | #2 |
| Update manager / installer / launch-at-login | N/A (App Store / system) | #9 |
| App Intents / shortcuts / digit shortcuts | ⏳ deferred | #10 |
| Settings parity (appearance materials, drag area, bar visibility, HUDs) | ⏳ deferred | #11 |
| Routing rules (internal/popup/prompt/external) | ✅ shipped (shared `RoutingResolver` + in-app editor) | #13 |
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
prompt/code editing. The HTML/JS assets are platform-neutral and shared; the
AppKit container isn't.

**Shipped:** the macro bundle moved to `QuiperShared/` (compiled into both
targets as adjacent resources), `CodeEditorLanguage` is a shared enum, and iOS
gets a `WKWebView`-based `CodeEditorView` (`QuiperiOS/CodeEditorView.swift`)
that mirrors the macOS `CodeMirrorEditor` coordinator: `quiperCodeEditor`
message handler, initial-theme user script, config-equality-gated
`setDocument`, and `didStartProvisionalNavigation`/process-terminate resets.
A lightweight `CodeEditorSession` (`QuiperiOS/CodeEditorSession.swift`) maps
`EditorDocumentSession`'s document/debounced-save/read-only contract to
in-memory storage (no file monitoring). The action-script editor
(`ActionScriptEditView`) uses it with JavaScript mode.

**Residual:** read-only rendering and non-JavaScript modes (CSS, CSS-selector)
are wired in the container but unused by the current iOS screens; the prompt
composer is a plain text input. File-backed custom CSS editing and macOS
conflict/external-update UI are out of scope on iOS (in-memory documents only).

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

### #9 Updater / install-at-login ✅ DONE
`UpdateManager`, `UpdateInstaller`, `Launcher`, `UpdatePromptWindowController`
are macOS-only.

**Resolution:** nothing to port. iOS binary updates, install, and launch
handling are provided by the App Store and the system, so this debt is closed;
`UpdatePreferences` stays in the shared schema for settings parity only.

### #10 App Intents / shortcuts
AppIntents and global digit shortcuts are macOS-only.

**Future work:** App Shortcuts on iOS via App Intents for "open engine X",
"new session", "clear web data", etc.

### #11 Full settings parity ✅ DONE
All portable `PersistedSettings` values are surfaced in the iOS Settings
`Form`, following the shared schema: engines (icon fetch/removal), prompt
history (enable, per-trigger recording, limit), tab survival policy,
tab-navigation ring size, color scheme, custom actions, automatic engine
switching on last-session close, auto-create on empty engine, and purging
dangling web data. The newly surfaced settings are wired to real behavior
mirroring macOS: per-`clearType` prompt-history recording, `.never` tab
survival boots clean and never persists tab state, empty-engine activation
creates (or refuses to create) a session per the toggle, closing the last
session auto-switches to the nearest engine with sessions, and removing an
engine purges its website data.

Not portable (macOS-only, intentionally not surfaced):
- Window chrome: `windowAppearance` (materials/blur/outline),
  `topBarVisibility`, `dragAreaPosition` — iOS has no overlay window or top
  bar; the bottom bar is the iOS chrome.
- `engineSelectorDisplayMode`/`sessionSelectorDisplayMode` — macOS segmented
  control display modes; iOS uses its own native session selector.
- HUDs (`enableHUDDoubleTapCmd`/`enableHUDCmdEscape`), `showOnAllSpaces` —
  macOS HUD/Spaces concepts.
- `settingsColorStyle` — macOS Settings accent styling; iOS uses the system
  accent.
- `serviceZoomLevels` — per-engine page zoom (feature, not just a setting);
  deferred.
- Input/window machinery: `hotkey`, `appShortcutBindings`,
  `globalEngineDigitShortcutsEnabled`, `dockVisibility`,
  `hideQuiperWhenRetriggeringActiveEngineShortcut`, `updatePreferences` —
  no iOS equivalent (App Store updates, no Dock, no hotkeys).
- `promptRecordingIndicatorStyle` — the macOS composer glow/dash indicator;
  iOS composes in the page, so there is no composer to decorate.

Behavioral notes: `TabSurvivalPolicy.askOnExit` is hidden from the iOS picker
because iOS has no exit prompt; a value ported from macOS still round-trips in
the schema and behaves like `.always`. `promptHistoryRecordOnCmdBackspace` /
`promptHistoryRecordOnSelectionClear` map to the same `clearType` triggers the
shared input tracker emits.

### #12 Session/tab persistence parity ✅ DONE
URL restore matches macOS: `QuiperShared/TabRestoration.swift` builds the
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

The interactive ring is an iOS-only adaptation of that MRU history.
`DoubleTapGestureRecognizer` never activates, so it coexists with WKWebView's
own gestures; `RingTouchShield` swallows the second tap so the page never
receives it (no click, scroll, or text selection while the ring is open).
Cards show live page thumbnails captured when a session is left and refreshed
after each load (`sessionThumbnails` / `captureThumbnailWhenLeaving` /
`storeThumbnail`); the current page is recaptured fresh as the ring opens via a
deferred `captureFreshSnapshot()` so the active tab never shows a stale frame.
A held finger highlights cards and edge-scrolls through overflow; releasing
over a card switches with an expanding selection animation while the target
session pre-loads behind it (mounted hidden and swapped at completion). With a
ring size of 2, a quick double-tap switches tabs directly with no HUD.

### #13 Custom CSS injection & routing rules
Custom CSS injection and `RoutingRule` evaluation now share one implementation:
`QuiperShared/LinkRouting.swift` exposes `RoutingResolver` (same-origin,
top-to-bottom rule evaluation, default external) and `QuiperShared/WebScripts`
provides the CSS injection script; both the macOS `WebViewManager` and the iOS
`WebSessionCoordinator` call the same code. On iOS the routing prompt is a
`UIAlertController` and "Always…" choices persist via
`AppEnvironment.rememberRoutingDecision` (`RoutingResolver.applyingRememberedRule`),
matching macOS `rememberDecision`.

Routing rules are editable in-app: Settings → engine → Routing Rules offers the
same top-to-bottom, first-match-wins list as macOS with pattern editing, action
picking, swipe-to-delete, and Edit-mode reordering (draft-saved with the
engine's Save). The rule row itself is shared: `QuiperShared/RoutingRuleEditor.swift`
(`RoutingRuleField`) renders the pattern field and `RoutingAction` picker for
both targets, and macOS's `SettingsView` embeds it, so the editor cannot drift.

Residual gap:
- `CustomCSSStorage` (macOS file-backed per-service CSS overrides) has no iOS
  equivalent; iOS resolves CSS from `service.customCSS` and the synced template
  default only.

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
