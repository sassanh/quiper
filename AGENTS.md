# Repository Guidelines

## Project Structure & Module Organization

- App code lives in `Sources/Quiper/`. Entry points: `Main.swift` (launch), `App.swift` (app delegate), and `MainWindowController.swift` (overlay window + tab stacks). UI components and helpers sit beside them (e.g., `HotkeyCaptureOverlay.swift`, `OverlayWindow.swift`, `WebNotificationBridge.swift`).
- Shared constants and settings: `Constants.swift`, `Settings.swift`, `SettingsView.swift`, `ActionsSettingsView.swift`.
- Assets: `Sources/Quiper/logo/` and `Supporting/` (Info.plist, icon resources). Release builds drop `Quiper.app` at repo root.

## Build, Test, and Development Commands

- `xcodebuild -project Quiper.xcodeproj -scheme Quiper -configuration Debug -destination "platform=macOS" build` — Debug build.
- `./build-app.sh` — Release bundle + Info.plist + assets + ad-hoc codesign; outputs `Quiper.app`.
- Ensure Xcode 16+ Command Line Tools (`xcode-select --install`) are available.

## Coding Style & Naming Conventions

- Swift 6.2 target; use 4-space indentation and file-scoped `import`s.
- Types and protocols in UpperCamelCase; properties, functions, locals in lowerCamelCase; constants prefer `let`.
- Favor `struct` and `enum` for value semantics; mark classes `final` unless subclassed.
- Keep UI work on the main thread; isolate side effects in helpers (e.g., notification dispatch, hotkey capture).
- Follow the [Settings Styling Standards](file:///Users/sassanharadji/Projects/Personal/quiper/docs/settings-styling.md) when adding or modifying rows, sections, and controls in the Settings window.
- If you introduce formatting, use `swift-format` defaults; avoid reflowing unchanged code.

## Testing Guidelines

- The XCTest targets are `QuiperTests` (unit tests) and `QuiperUITests` (UI tests).
- Prefer focused unit tests for shortcut parsing, notification metadata, and settings serialization. Run only unit tests with:
  `xcodebuild test -project Quiper.xcodeproj -scheme Quiper -destination "platform=macOS" -only-testing:QuiperTests`
- To run all tests including code coverage, run `./tests-with-coverage.sh`.
- For UI changes, include a quick manual checklist (hotkey capture, overlay show/hide, service switching) in the PR.

## Commit & Pull Request Guidelines

- Follow the Conventional Commits-style prefixes: `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:` (see recent history).
- Keep subject lines imperative, lowercase, and concise: `feat(ui): add session actions menu`.
- **Do not pollute commit messages or changelogs with irrelevant technical details. Write clearly and focus strictly on the value delivered to the reader.**
- Use a bulleted list (`- Details...`) in the body for multiple changes, starting each bullet with a capital letter. **CRITICAL: Do NOT use multiple `-m` flags for bullet points (e.g. `git commit -m "sub" -m "- 1" -m "- 2"`), as this inserts a blank line between every single bullet. Instead, pass the body as a single multiline string or use a temporary file to keep bullet points adjacent.**
- PRs should summarize behavior change, list manual tests, and note platform (macOS version, Intel/Apple Silicon). Add screenshots or short screen recordings for UI-facing edits and mention if settings schema changes.

## Configuration & Security Notes

- User settings live at `~/Library/Application Support/app.sassanh.quiper.Quiper/settings.json` (and `app.sassanh.quiper.QuiperDev/settings.json` in Debug); include migrations if you change its shape or location.
- Notifications use the WebKit bridge; ensure new features respect macOS notification permissions and sandbox expectations.

## Agent Behavior Rules

- **BUILD WARNINGS ARE NOT ACCEPTABLE**: When implementing or refactoring code, always aim for zero compiler warnings. Code must be written cleanly, following the strict concurrency guidelines of Swift 6, and avoiding deprecated APIs. Any warnings introduced during changes must be resolved immediately before completing the task.
- **DO NOT RUN TESTS WITHOUT EXPLICIT APPROVAL**: Never execute any test suites, unit tests, integration tests, or UI test commands (e.g., `xcodebuild test`, `swift test`, or helper test scripts) unless explicitly requested and approved by the user in the current message context.
