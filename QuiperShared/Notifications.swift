import Foundation

/// Central registry of every application notification name — in-process
/// (NotificationCenter) and cross-process (DistributedNotificationCenter).
/// Never construct a `Notification.Name` from a raw string elsewhere; for
/// DistributedNotificationCenter pairs that cannot share this module (the
/// UI-test runner process), keep the counterpart literal in sync with the
/// relevant documented name here.

extension Notification.Name {
    // MARK: Shared state (macOS + iOS)

    static let shortcutRecordingDidTriggerReserved = Notification.Name("shortcutRecordingDidTriggerReserved")
    static let webDataCleared = Notification.Name("QuiperWebDataCleared")
    static let promptHistoryLimitChanged = Notification.Name("QuiperPromptHistoryLimitChanged")

    /// Posted with the service ID as object whenever an engine stylesheet
    /// changes for any reason (user edit, Hide, template sync toggle).
    static let engineCustomCSSChanged = Notification.Name("QuiperEngineCustomCSSChanged")

    /// Posted with the service ID as object whenever an engine prompt input
    /// selector changes (user edit, template sync toggle).
    static let enginePromptSelectorChanged = Notification.Name("QuiperEnginePromptSelectorChanged")
}

extension Notification.Name {
    // MARK: macOS app state

    static let inspectorVisibilityChanged = Notification.Name("InspectorVisibilityChanged")
    static let showSettings = Notification.Name("QuiperShowSettings")
    static let startGlobalHotkeyCapture = Notification.Name("QuiperStartGlobalHotkeyCapture")
    static let appVisibilityChanged = Notification.Name("QuiperAppVisibilityChanged")
    static let hotkeyConfigurationChanged = Notification.Name("QuiperHotkeyConfigurationChanged")
    static let notificationPermissionChanged = Notification.Name("QuiperNotificationPermissionChanged")
    static let dockVisibilityChanged = Notification.Name("QuiperDockVisibilityChanged")
    static let selectorDisplayModeChanged = Notification.Name("QuiperSelectorDisplayModeChanged")
    static let topBarVisibilityChanged = Notification.Name("QuiperTopBarVisibilityChanged")
    static let dragAreaPositionChanged = Notification.Name("QuiperDragAreaPositionChanged")
    static let windowAppearanceChanged = Notification.Name("QuiperWindowAppearanceChanged")
    static let colorSchemeChanged = Notification.Name("QuiperColorSchemeChanged")
    static let showOnAllSpacesChanged = Notification.Name("QuiperShowOnAllSpacesChanged")
    static let keepOverlayOnTopChanged = Notification.Name("QuiperKeepOverlayOnTopChanged")
    static let focusLossEffectChanged = Notification.Name("QuiperFocusLossEffectChanged")
    static let windowDidShow = Notification.Name("QuiperWindowDidShow")
    static let windowDidHide = Notification.Name("QuiperWindowDidHide")
    static let settingsWindowDidOpen = Notification.Name("QuiperSettingsWindowDidOpen")
    static let settingsWindowDidClose = Notification.Name("QuiperSettingsWindowDidClose")
    static let servicesIconsUpdated = Notification.Name("QuiperServicesIconsUpdated")
    static let servicesOrderUpdated = Notification.Name("QuiperServicesOrderUpdated")
    static let orphanedEncryptedStoresFound = Notification.Name("QuiperOrphanedEncryptedStoresFound")

    /// Posted by `KeyFocusGate` after it handled AppKit's key-status
    /// notification. The gate is the app's only listener of AppKit's key
    /// notifications; windows that react to focus changes subscribe here
    /// instead of opening a second observer of their own.
    static let quiperKeyWindowDidBecomeKey = Notification.Name("QuiperKeyWindowDidBecomeKey")
    static let quiperKeyWindowDidResignKey = Notification.Name("QuiperKeyWindowDidResignKey")
}

extension Notification.Name {
    // MARK: Cross-process (DistributedNotificationCenter)

    /// Asks the app to show its screenshot-capture confirmation prompt.
    /// Observed by `ScreenshotPromptController`; posted by the UI-test
    /// screenshot generator (`QuiperUITests/ScreenshotGenerator.swift`),
    /// which runs in a separate process and cannot reference this constant.
    static let showCapturePrompt = Notification.Name("app.sassanh.quiper.ShowCapturePrompt")

    /// Test-only beep broadcast, posted whenever the user flow under test
    /// plays the error beep. Observed by UI-test tooling
    /// (`QuiperUITests/UserFlows/custom-actions/CustomActionUITests.swift`),
    /// which runs in a separate process and cannot reference this constant.
    static let distributedTestBeep = Notification.Name("QuiperTestBeep")
}
