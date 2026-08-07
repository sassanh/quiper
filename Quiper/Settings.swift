import Combine
import Foundation
import AppKit
import SwiftUI
import Carbon

// Models extracted to QuiperShared/SharedModels.swift and QuiperShared/SharedSettings.swift

class SettingsWindow: NSWindow {
    static let shared = SettingsWindow()
    private var hostingController: NSHostingController<SettingsView>

    public weak var appController: AppController? {
        didSet {
            hostingController.rootView = SettingsView(
                appController: appController,
                initialServiceID: appController?.currentServiceID
            )
            delegate = appController
        }
    }

    private init() {
        hostingController = NSHostingController(rootView: SettingsView(appController: nil, initialServiceID: nil))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = Settings.shared.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        setFrameAutosaveName("SettingsWindow")
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        title = "Settings"
        minSize = NSSize(width: 720, height: 480)
        center()

        configureContentForGlass()

        // Apply the initial color scheme and observe future changes
        appearance = Settings.shared.colorScheme.nsAppearance
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColorSchemeChanged),
            name: .colorSchemeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnAllSpacesChanged),
            name: .showOnAllSpacesChanged,
            object: nil
        )
    }

    @objc private func handleColorSchemeChanged() {
        appearance = Settings.shared.colorScheme.nsAppearance
    }

    @objc private func handleShowOnAllSpacesChanged() {
        collectionBehavior = Settings.shared.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        if SecureDataMigrationManager.shared.isMigrationPending {
            NSSound.beep()
            return
        }
        super.close()
    }

    override func performClose(_ sender: Any?) {
        if SecureDataMigrationManager.shared.isMigrationPending {
            NSSound.beep()
            return
        }
        super.performClose(sender)
    }

    override func orderOut(_ sender: Any?) {
        if SecureDataMigrationManager.shared.isMigrationPending {
            NSSound.beep()
            return
        }
        super.orderOut(sender)
    }

    override func keyDown(with event: NSEvent) {
        // 53 is the key code for the Escape key
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    private func configureContentForGlass() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: contentRect(forFrameRect: frame))
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.cornerRadius = 12

            let hostingView = hostingController.view
            hostingView.frame = glass.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.translatesAutoresizingMaskIntoConstraints = true

            glass.contentView = hostingView
            contentView = glass
        }
        contentViewController = hostingController
    }

    public override func isAccessibilityElement() -> Bool {
        return true
    }
    
    public override func accessibilityTitle() -> String? {
        return "Quiper Settings"
    }
}

@MainActor
class Settings: ObservableObject {
    static let shared = Settings()
    static let defaultPromptHistoryLimit = 10
    static let promptHistoryLimitRange = 1...50

    static func clampedPromptHistoryLimit(_ value: Int) -> Int {
        min(max(value, promptHistoryLimitRange.lowerBound), promptHistoryLimitRange.upperBound)
    }

    @Published var services: [Service] = []
    @Published var hotkeyConfiguration: HotkeyManager.Configuration = HotkeyManager.defaultConfiguration
    @Published var customActions: [CustomAction] = []
    @Published var updatePreferences: UpdatePreferences = UpdatePreferences()
    @Published var serviceZoomLevels: [UUID: CGFloat] = [:]
    @Published var appShortcutBindings: AppShortcutBindings = .defaults
    @Published var dockVisibility: DockVisibility = .whenVisible {
        didSet {
            NotificationCenter.default.post(name: .dockVisibilityChanged, object: nil)
        }
    }
    @Published var engineSelectorDisplayMode: SelectorDisplayMode = .auto {
        didSet {
            NotificationCenter.default.post(name: .selectorDisplayModeChanged, object: nil)
        }
    }
    @Published var sessionSelectorDisplayMode: SelectorDisplayMode = .auto {
        didSet {
            NotificationCenter.default.post(name: .selectorDisplayModeChanged, object: nil)
        }
    }
    @Published var topBarVisibility: TopBarVisibility = .visible {
        didSet {
            NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)
        }
    }
    @Published var dragAreaPosition: DragAreaPosition = .top {
        didSet {
            NotificationCenter.default.post(name: .dragAreaPositionChanged, object: nil)
        }
    }
    @Published var showHiddenBarOnModifiers: Bool = true
    @Published var windowAppearance: WindowAppearanceSettings = .default
    @Published var colorScheme: AppColorScheme = .system {
        didSet {
            NotificationCenter.default.post(name: .colorSchemeChanged, object: nil)
        }
    }
    @Published var showOnAllSpaces: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .showOnAllSpacesChanged, object: nil)
            saveSettings()
        }
    }
    @Published var automaticallySwitchEngineOnLastSessionClose: Bool = true
    @Published var autoCreateSessionOnEmptyEngineActivation: Bool = true
    @Published var shouldPurgeDanglingWebData: Bool = true
    @Published var hasCompletedGhostOnboarding: Bool = false {
        didSet {
            saveSettings()
        }
    }
    @Published var enableHUDDoubleTapCmd: Bool = true {
        didSet {
            saveSettings()
        }
    }
    @Published var enableHUDCmdEscape: Bool = true {
        didSet {
            saveSettings()
        }
    }
    /// When true, pressing an engine's global launch shortcut while Quiper is already
    /// visible, focused, and showing that engine hides Quiper (toggle behavior).
    @Published var hideQuiperWhenRetriggeringActiveEngineShortcut: Bool = true
    /// Set when the user dismissed the one-time notice explaining that Cmd+, opens
    /// the engine's own Settings rather than Quiper's.
    @Published var hasDismissedEngineSettingsShortcutNotice: Bool = false {
        didSet {
            saveSettings()
        }
    }
    /// Makes the primary Go to engine 1–10 modifier shortcuts available system-wide.
    @Published var globalEngineDigitShortcutsEnabled: Bool = false
    @Published var settingsColorStyle: SettingsColorStyle = .colorful {
        didSet {
            saveSettings()
        }
    }
    @Published var tabSurvivalPolicy: TabSurvivalPolicy = .always {
        didSet {
            saveSettings()
        }
    }
    @Published var tabNavigationRingSize: Int = 2 {
        didSet {
            let clamped = max(2, min(10, tabNavigationRingSize))
            if tabNavigationRingSize != clamped {
                tabNavigationRingSize = clamped
                return
            }
            saveSettings()
        }
    }
    @Published var enablePromptHistory: Bool = true {
        didSet {
            saveSettings()
        }
    }
    @Published var promptRecordingIndicatorStyle: PromptRecordingIndicatorStyle = .dashed {
        didSet {
            saveSettings()
        }
    }
    @Published var promptHistoryRecordOnSubmit: Bool = true {
        didSet {
            saveSettings()
        }
    }
    @Published var promptHistoryRecordOnCmdBackspace: Bool = true {
        didSet {
            saveSettings()
        }
    }
    @Published var promptHistoryRecordOnSelectionClear: Bool = false {
        didSet {
            saveSettings()
        }
    }
    @Published var promptHistoryLimit: Int = defaultPromptHistoryLimit {
        didSet {
            let clampedValue = Self.clampedPromptHistoryLimit(promptHistoryLimit)
            if promptHistoryLimit != clampedValue {
                promptHistoryLimit = clampedValue
                return
            }
            NotificationCenter.default.post(name: .promptHistoryLimitChanged, object: nil)
            saveSettings()
        }
    }
    @Published var persistedTabState: PersistedTabState? = nil {
        didSet {
            saveSettings()
        }
    }
    
    func reset() {
        isPerformingWipe = true
        defer { isPerformingWipe = false }
        services = []
        hotkeyConfiguration = HotkeyManager.defaultConfiguration
        customActions = []
        didResolveEngineSettingsShortcutMigration = nil
        updatePreferences = UpdatePreferences()
        serviceZoomLevels = [:]
        appShortcutBindings = .defaults
        engineSelectorDisplayMode = .auto
        sessionSelectorDisplayMode = .auto
        topBarVisibility = .visible
        dragAreaPosition = .top
        showHiddenBarOnModifiers = true
        windowAppearance = .default
        colorScheme = .system
        automaticallySwitchEngineOnLastSessionClose = true
        autoCreateSessionOnEmptyEngineActivation = true
        shouldPurgeDanglingWebData = true
        hasCompletedGhostOnboarding = false
        enableHUDDoubleTapCmd = true
        enableHUDCmdEscape = true
        hideQuiperWhenRetriggeringActiveEngineShortcut = true
        globalEngineDigitShortcutsEnabled = false
        showOnAllSpaces = false
        settingsColorStyle = .colorful
        tabSurvivalPolicy = .always
        tabNavigationRingSize = 2
        enablePromptHistory = true
        promptRecordingIndicatorStyle = .dashed
        promptHistoryRecordOnSubmit = true
        promptHistoryRecordOnCmdBackspace = true
        promptHistoryRecordOnSelectionClear = false
        promptHistoryLimit = Self.defaultPromptHistoryLimit
        persistedTabState = nil
        beginPersistedSettingsMigrationEvaluation(
            loadedFromDisk: false,
            persistedVersion: nil
        )
    }

    private let settingsFile: URL = {
        // Use temporary directory during tests to avoid modifying real config
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        
        let baseDir: URL
        if isRunningTests || isUITesting {
            // Tests use a temp directory that gets cleaned up
            // Use process identifier to ensure isolation between parallel runs or sequential UI test launches
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            baseDir = tempDir.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            // Production uses Application Support
            baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(Constants.APP_FOLDER_NAME)
        }
        
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
        return baseDir.appendingPathComponent("settings.json")
    }()

    private let legacyHotkeyFile: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/quiper/hotkey_config.json")
    }()


    var defaultActionTemplates: [CustomAction] {
        DefaultActions.defaults
    }

    var defaultServiceTemplates: [Service] {
        defaultEngines
    }


    private var defaultEngines: [Service] {
        DefaultEngineDefinitions.definitions.sorted { lhs, rhs in
            let lhsIsLocal = Self.isLocalDefaultEngine(lhs)
            let rhsIsLocal = Self.isLocalDefaultEngine(rhs)
            if lhsIsLocal != rhsIsLocal {
                return !lhsIsLocal
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func isLocalDefaultEngine(_ service: Service) -> Bool {
        guard let host = URL(string: service.url)?.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }


    private var isPerformingWipe = false
    /// Prevents `@Published` didSet handlers from writing settings while `loadSettings()` is applying disk state.
    private var isLoadingSettings = false
    private var persistedSettingsMigrationContext = PersistedSettingsMigrationContext(
        loadedFromDisk: false,
        persistedVersion: nil,
        currentVersion: Bundle.main.versionDisplayString
    )
    private var persistedSettingsMigrationDispositions:
        [PersistedSettingsMigration: PersistedSettingsMigrationDisposition] = [:]
    var needsTemplateActionSyncMigrationPrompt: Bool {
        migrationDisposition(for: .templateActionScriptSync) == .awaitingPrompt
    }
    private(set) var needsSparseBundleMigrationPrompt = false
    var needsEngineShortcutToggleMigrationPrompt: Bool {
        migrationDisposition(for: .engineShortcutToggle) == .awaitingPrompt
    }
    private var didResolveEngineSettingsShortcutMigration: Bool?
    var needsEngineSettingsShortcutMigrationPrompt: Bool {
        migrationDisposition(for: .engineSettingsShortcut) == .awaitingPrompt
    }

    init() {
        FaviconFetcher.configure(imageProcessor: AppKitFaviconImageProcessor.self)
        _ = loadSettings()
        enrichMissingIconsIfNeeded()
    }

    func enrichMissingIconsIfNeeded() {
        var localUpdated = false
        for idx in 0..<services.count {
            if let defaultB64 = EngineIconService.defaultIcon(for: services[idx], defaults: defaultEngines) {
                services[idx].iconBase64 = defaultB64
                localUpdated = true
            }
        }
        
        if localUpdated {
            self.saveSettings()
            NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
        }

        let enginesWithMissingIcons = EngineIconService.servicesMissingIcons(in: services)
        guard !enginesWithMissingIcons.isEmpty else { return }
        
        Task(priority: .background) {
            let fetchedIcons = await EngineIconService.fetchFavicons(for: enginesWithMissingIcons)
            
            if !fetchedIcons.isEmpty {
                await MainActor.run {
                    var updated = false
                    for (id, base64) in fetchedIcons {
                        if let idx = self.services.firstIndex(where: { $0.id == id }) {
                            self.services[idx].iconBase64 = base64
                            updated = true
                        }
                    }
                    if updated {
                        self.saveSettings()
                        NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
                    }
                }
            }
        }
    }

    func loadSettings() -> [Service] {
        isLoadingSettings = true

        let (persisted, loadedFromDisk) = readPersistedSettings()
        beginPersistedSettingsMigrationEvaluation(
            loadedFromDisk: loadedFromDisk,
            persistedVersion: persisted.quiperVersion
        )
        setMigrationDisposition(
            persistedSettingsMigrationContext.disposition(
                whenDetected: persisted.didDecodeLegacySelectorDisplayMode,
                presentation: .automatic
            ),
            for: .selectorDisplayModes
        )
        setMigrationDisposition(
            persistedSettingsMigrationContext.disposition(
                whenDetected: persisted.didDecodeLegacyServiceIdentifiers,
                presentation: .automatic
            ),
            for: .serviceIdentifiers
        )

        // Resolve migration state before any @Published assignments that may call saveSettings().
        // Mid-load saves must not stamp new keys (that would clear the prompt on the next loadSettings()).
        applyEngineShortcutToggleSetting(
            persistedValue: persisted.hideQuiperWhenRetriggeringActiveEngineShortcut
        )
        
        services = persisted.services
        if !loadedFromDisk {
            enableTemplateResourceSyncForBundledServices()
        }
        let useDefaultActions = !CommandLine.arguments.contains("--no-default-actions")
        customActions = loadedFromDisk ? (persisted.customActions ?? []) : (useDefaultActions ? DefaultActions.defaults : [])
        updatePreferences = persisted.updatePreferences ?? UpdatePreferences()
        serviceZoomLevels = (persisted.serviceZoomLevels ?? [:]).mapValues { CGFloat($0) }
        appShortcutBindings = persisted.appShortcuts ?? .defaults
        if let altSessionDigits = persisted.sessionDigitsAlternateModifiers {
            appShortcutBindings.sessionDigitsAlternateModifiers = altSessionDigits
        }
        if dockVisibility != (persisted.dockVisibility ?? .whenVisible) {
            dockVisibility = persisted.dockVisibility ?? .whenVisible
        }
        if engineSelectorDisplayMode != (persisted.engineSelectorDisplayMode ?? .auto) {
            engineSelectorDisplayMode = persisted.engineSelectorDisplayMode ?? .auto
        }
        if sessionSelectorDisplayMode != (persisted.sessionSelectorDisplayMode ?? .auto) {
            sessionSelectorDisplayMode = persisted.sessionSelectorDisplayMode ?? .auto
        }
        if topBarVisibility != (persisted.topBarVisibility ?? .visible) {
            topBarVisibility = persisted.topBarVisibility ?? .visible
        }
        if dragAreaPosition != (persisted.dragAreaPosition ?? .top) {
            dragAreaPosition = persisted.dragAreaPosition ?? .top
        }
        if showHiddenBarOnModifiers != (persisted.showHiddenBarOnModifiers ?? true) {
            showHiddenBarOnModifiers = persisted.showHiddenBarOnModifiers ?? true
        }
        if windowAppearance != (persisted.windowAppearance ?? .default) {
            windowAppearance = persisted.windowAppearance ?? .default
        }
        if colorScheme != (persisted.colorScheme ?? .system) {
            colorScheme = persisted.colorScheme ?? .system
        }
        if settingsColorStyle != (persisted.settingsColorStyle ?? .colorful) {
            settingsColorStyle = persisted.settingsColorStyle ?? .colorful
        }
        automaticallySwitchEngineOnLastSessionClose = persisted.automaticallySwitchEngineOnLastSessionClose ?? true
        autoCreateSessionOnEmptyEngineActivation = persisted.autoCreateSessionOnEmptyEngineActivation ?? true
        shouldPurgeDanglingWebData = persisted.shouldPurgeDanglingWebData ?? true
        hasCompletedGhostOnboarding = persisted.hasCompletedGhostOnboarding ?? false
        enableHUDDoubleTapCmd = persisted.enableHUDDoubleTapCmd ?? true
        enableHUDCmdEscape = persisted.enableHUDCmdEscape ?? true
        globalEngineDigitShortcutsEnabled = persisted.globalEngineDigitShortcutsEnabled ?? false
        showOnAllSpaces = persisted.showOnAllSpaces ?? false
        tabSurvivalPolicy = persisted.tabSurvivalPolicy ?? .always
        enablePromptHistory = persisted.enablePromptHistory ?? true
        promptRecordingIndicatorStyle = persisted.promptRecordingIndicatorStyle ?? .dashed
        promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit ?? true
        promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace ?? true
        promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear ?? false
        promptHistoryLimit = Self.clampedPromptHistoryLimit(persisted.promptHistoryLimit ?? Self.defaultPromptHistoryLimit)
        persistedTabState = persisted.persistedTabState
        tabNavigationRingSize = persisted.tabNavigationRingSize ?? 2
        configureTemplateActionSyncMigration()
        applyEngineSettingsShortcutMigrationSetting(
            persistedValue: persisted.didResolveEngineSettingsShortcutMigration
        )
        needsSparseBundleMigrationPrompt =
            services.contains(where: { $0.isEncrypted })
            && EncryptedVolumeManager.shared.hasAnyLegacyBundles(in: services)

        var shouldSaveAfterLoad = false
        if loadedFromDisk, let storedHotkey = persisted.hotkey {
            hotkeyConfiguration = storedHotkey
        } else if loadedFromDisk, let legacy = loadLegacyHotkeyConfiguration() {
            hotkeyConfiguration = legacy
            shouldSaveAfterLoad = true
        } else {
            hotkeyConfiguration = HotkeyManager.defaultConfiguration
        }
        if persistedSettingsMigrationContext.isUnversionedExistingSettings
            && !migrationDisposition(for: .templateActionScriptSync).isUnresolved {
            shouldSaveAfterLoad = true
        }
        if migrationDisposition(for: .selectorDisplayModes) == .runAutomatically {
            shouldSaveAfterLoad = true
        }
        if migrationDisposition(for: .serviceIdentifiers) == .runAutomatically {
            shouldSaveAfterLoad = true
        }

        isLoadingSettings = false
        if shouldSaveAfterLoad {
            saveSettings()
        }
        return services
    }

    func defaultActionID(matching name: String) -> UUID? {
        ActionScripts.defaultActionID(matching: name)
    }

    func discardSavedTabs() {
        persistedTabState = nil
        saveSettings()
    }

    func saveSettings() {
        if isPerformingWipe || isLoadingSettings {
            return
        }
        do {
            let payload = PersistedSettings(services: services,
                                            hotkey: hotkeyConfiguration,
                                            customActions: customActions,
                                            updatePreferences: updatePreferences,
                                            serviceZoomLevels: serviceZoomLevels.mapValues { Double($0) },
                                            appShortcuts: appShortcutBindings,
                                            sessionDigitsAlternateModifiers: appShortcutBindings.sessionDigitsAlternateModifiers,
                                            dockVisibility: dockVisibility,
                                            engineSelectorDisplayMode: engineSelectorDisplayMode,
                                            sessionSelectorDisplayMode: sessionSelectorDisplayMode,
                                            topBarVisibility: topBarVisibility,
                                            dragAreaPosition: dragAreaPosition,
                                            showHiddenBarOnModifiers: showHiddenBarOnModifiers,
                                            windowAppearance: windowAppearance,
                                            colorScheme: colorScheme,
                                            automaticallySwitchEngineOnLastSessionClose: automaticallySwitchEngineOnLastSessionClose,
                                            autoCreateSessionOnEmptyEngineActivation: autoCreateSessionOnEmptyEngineActivation,
                                            shouldPurgeDanglingWebData: shouldPurgeDanglingWebData,
                                            hasCompletedGhostOnboarding: hasCompletedGhostOnboarding,
                                            enableHUDDoubleTapCmd: enableHUDDoubleTapCmd,
                                            enableHUDCmdEscape: enableHUDCmdEscape,
                                            showOnAllSpaces: showOnAllSpaces,
                                            settingsColorStyle: settingsColorStyle,
                                            tabSurvivalPolicy: tabSurvivalPolicy,
                                            persistedTabState: persistedTabState,
                                            enablePromptHistory: enablePromptHistory,
                                            promptRecordingIndicatorStyle: promptRecordingIndicatorStyle,
                                            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
                                            promptHistoryRecordOnCmdBackspace: promptHistoryRecordOnCmdBackspace,
                                            promptHistoryRecordOnSelectionClear: promptHistoryRecordOnSelectionClear,
                                            promptHistoryLimit: promptHistoryLimit,
                                            tabNavigationRingSize: tabNavigationRingSize,
                                            hideQuiperWhenRetriggeringActiveEngineShortcut: persistedEngineShortcutToggleForSave(),
            didResolveEngineSettingsShortcutMigration: persistedEngineSettingsShortcutMigrationForSave(),
                                            hasDismissedEngineSettingsShortcutNotice: hasDismissedEngineSettingsShortcutNotice,
                                            globalEngineDigitShortcutsEnabled: globalEngineDigitShortcutsEnabled,
                                            quiperVersion: persistedQuiperVersionForSave())
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsFile)
            syncSecuredEngineMetadataToBundles()
        } catch {
        }
    }

    /// For migrated+unlocked engines, writes current in-memory metadata back to
    /// the secure bundle so edits made in Settings persist alongside the encrypted data.
    private func syncSecuredEngineMetadataToBundles() {
        for service in services where service.isEncrypted && service.hasMigratedMetadata {
            guard EncryptedVolumeManager.shared.isUnlocked(for: service.id) else { continue }
            guard EngineMetadataMigrationManager.shared.cachedMetadata(for: service.id) != nil else {
                continue
            }
            do {
                try EngineMetadataMigrationManager.shared.saveMetadataToBundle(for: service.id)
            } catch {
                NSLog("[Settings] Failed to sync metadata to bundle for %@: %@", service.name, error.localizedDescription)
            }
        }
    }

    func makePersistedSettings() -> PersistedSettings {
        PersistedSettings(
            services: services,
            hotkey: hotkeyConfiguration,
            customActions: customActions,
            updatePreferences: updatePreferences,
            serviceZoomLevels: serviceZoomLevels.mapValues { Double($0) },
            appShortcuts: appShortcutBindings,
            sessionDigitsAlternateModifiers: appShortcutBindings.sessionDigitsAlternateModifiers,
            dockVisibility: dockVisibility,
            engineSelectorDisplayMode: engineSelectorDisplayMode,
            sessionSelectorDisplayMode: sessionSelectorDisplayMode,
            topBarVisibility: topBarVisibility,
            showHiddenBarOnModifiers: showHiddenBarOnModifiers,
            windowAppearance: windowAppearance,
            colorScheme: colorScheme,
            automaticallySwitchEngineOnLastSessionClose: automaticallySwitchEngineOnLastSessionClose,
            autoCreateSessionOnEmptyEngineActivation: autoCreateSessionOnEmptyEngineActivation,
            shouldPurgeDanglingWebData: shouldPurgeDanglingWebData,
            hasCompletedGhostOnboarding: hasCompletedGhostOnboarding,
            enableHUDDoubleTapCmd: enableHUDDoubleTapCmd,
            enableHUDCmdEscape: enableHUDCmdEscape,
            showOnAllSpaces: showOnAllSpaces,
            settingsColorStyle: settingsColorStyle,
            tabSurvivalPolicy: tabSurvivalPolicy,
            persistedTabState: persistedTabState,
            enablePromptHistory: enablePromptHistory,
            promptRecordingIndicatorStyle: promptRecordingIndicatorStyle,
            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
            promptHistoryRecordOnCmdBackspace: promptHistoryRecordOnCmdBackspace,
            promptHistoryRecordOnSelectionClear: promptHistoryRecordOnSelectionClear,
            promptHistoryLimit: promptHistoryLimit,
            tabNavigationRingSize: tabNavigationRingSize,
            hideQuiperWhenRetriggeringActiveEngineShortcut: persistedEngineShortcutToggleForSave(),
            didResolveEngineSettingsShortcutMigration: persistedEngineSettingsShortcutMigrationForSave(),
            globalEngineDigitShortcutsEnabled: globalEngineDigitShortcutsEnabled,
            quiperVersion: persistedQuiperVersionForSave()
        )
    }

    func applyPersistedSettings(_ persisted: PersistedSettings) {
        isLoadingSettings = true
        beginPersistedSettingsMigrationEvaluation(
            loadedFromDisk: true,
            persistedVersion: persisted.quiperVersion
        )
        applyEngineShortcutToggleSetting(
            persistedValue: persisted.hideQuiperWhenRetriggeringActiveEngineShortcut
        )
        services = persisted.services
        customActions = persisted.customActions ?? []
        configureTemplateActionSyncMigration()
        applyEngineSettingsShortcutMigrationSetting(
            persistedValue: persisted.didResolveEngineSettingsShortcutMigration
        )
        hasDismissedEngineSettingsShortcutNotice = persisted.hasDismissedEngineSettingsShortcutNotice ?? false
        updatePreferences = persisted.updatePreferences ?? UpdatePreferences()
        serviceZoomLevels = (persisted.serviceZoomLevels ?? [:]).mapValues { CGFloat($0) }
        appShortcutBindings = persisted.appShortcuts ?? .defaults
        if let altSessionDigits = persisted.sessionDigitsAlternateModifiers {
            appShortcutBindings.sessionDigitsAlternateModifiers = altSessionDigits
        }
        dockVisibility = persisted.dockVisibility ?? .whenVisible
        engineSelectorDisplayMode = persisted.engineSelectorDisplayMode ?? .auto
        sessionSelectorDisplayMode = persisted.sessionSelectorDisplayMode ?? .auto
        topBarVisibility = persisted.topBarVisibility ?? .visible
        dragAreaPosition = persisted.dragAreaPosition ?? .top
        showHiddenBarOnModifiers = persisted.showHiddenBarOnModifiers ?? true
        windowAppearance = persisted.windowAppearance ?? .default
        colorScheme = persisted.colorScheme ?? .system
        automaticallySwitchEngineOnLastSessionClose = persisted.automaticallySwitchEngineOnLastSessionClose ?? true
        autoCreateSessionOnEmptyEngineActivation = persisted.autoCreateSessionOnEmptyEngineActivation ?? true
        shouldPurgeDanglingWebData = persisted.shouldPurgeDanglingWebData ?? true
        hasCompletedGhostOnboarding = persisted.hasCompletedGhostOnboarding ?? false
        enableHUDDoubleTapCmd = persisted.enableHUDDoubleTapCmd ?? true
        enableHUDCmdEscape = persisted.enableHUDCmdEscape ?? true
        globalEngineDigitShortcutsEnabled = persisted.globalEngineDigitShortcutsEnabled ?? false
        showOnAllSpaces = persisted.showOnAllSpaces ?? false
        settingsColorStyle = persisted.settingsColorStyle ?? .colorful
        tabSurvivalPolicy = persisted.tabSurvivalPolicy ?? .always
        tabNavigationRingSize = persisted.tabNavigationRingSize ?? 2
        enablePromptHistory = persisted.enablePromptHistory ?? true
        promptRecordingIndicatorStyle = persisted.promptRecordingIndicatorStyle ?? .dashed
        promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit ?? true
        promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace ?? true
        promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear ?? false
        promptHistoryLimit = Self.clampedPromptHistoryLimit(persisted.promptHistoryLimit ?? Self.defaultPromptHistoryLimit)
        persistedTabState = persisted.persistedTabState
        if let storedHotkey = persisted.hotkey {
            hotkeyConfiguration = storedHotkey
        }
        isLoadingSettings = false
    }

    func defaultActionScript(for service: Service, action: CustomAction) -> String? {
        ActionScripts.defaultScript(for: service, action: action)
    }

    func defaultPromptInputSelector(for service: Service) -> String? {
        guard let template = defaultServiceTemplate(for: service) else {
            return nil
        }
        let selector = template.focus_selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return nil }
        return selector
    }

    func defaultCustomCSS(for service: Service) -> String? {
        ActionScripts.defaultCustomCSS(for: service)
    }

    func isTemplatePromptInputSelector(_ service: Service) -> Bool {
        defaultPromptInputSelector(for: service) != nil
    }

    func isTemplateCustomCSS(_ service: Service) -> Bool {
        defaultCustomCSS(for: service) != nil
    }

    func isTemplatePromptInputSelectorInSync(serviceID: UUID) -> Bool {
        guard let service = services.first(where: { $0.id == serviceID }) else { return false }
        return service.templatePromptInputSelectorSync && isTemplatePromptInputSelector(service)
    }

    func isTemplateCustomCSSInSync(serviceID: UUID) -> Bool {
        guard let service = services.first(where: { $0.id == serviceID }) else { return false }
        return service.templateCustomCSSSync && isTemplateCustomCSS(service)
    }

    func promptInputSelector(for service: Service) -> String {
        if service.templatePromptInputSelectorSync,
           let defaultSelector = defaultPromptInputSelector(for: service) {
            return defaultSelector
        }
        return FocusSelectorStorage.loadSelector(
            serviceID: service.id,
            fallback: service.focus_selector
        )
    }

    func customCSS(for service: Service) -> String {
        if let syncedCSS = ActionScripts.syncedCustomCSS(for: service) {
            return syncedCSS
        }
        return CustomCSSStorage.loadCSS(
            serviceID: service.id,
            fallback: service.customCSS ?? ""
        )
    }

    func setTemplatePromptInputSelectorSync(_ isInSync: Bool, serviceID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let defaultSelector = defaultPromptInputSelector(for: services[serviceIndex]) else {
            return
        }

        services[serviceIndex].templatePromptInputSelectorSync = isInSync
        if isInSync {
            services[serviceIndex].focus_selector = ""
            FocusSelectorStorage.deleteSelector(for: serviceID)
        } else {
            services[serviceIndex].focus_selector = defaultSelector
            FocusSelectorStorage.saveSelector(defaultSelector, serviceID: serviceID)
        }
        saveSettings()
    }

    func setTemplateCustomCSSSync(_ isInSync: Bool, serviceID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let defaultCSS = defaultCustomCSS(for: services[serviceIndex]) else {
            return
        }

        services[serviceIndex].templateCustomCSSSync = isInSync
        if isInSync {
            services[serviceIndex].customCSS = nil
            CustomCSSStorage.deleteCSS(for: serviceID)
        } else {
            services[serviceIndex].customCSS = defaultCSS
            CustomCSSStorage.saveCSS(defaultCSS, serviceID: serviceID)
        }
        saveSettings()
    }

    func savePromptInputSelector(_ selector: String, serviceID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[serviceIndex].templatePromptInputSelectorSync = false
        services[serviceIndex].focus_selector = selector
        FocusSelectorStorage.saveSelector(selector, serviceID: serviceID)
        saveSettings()
    }

    func saveCustomCSS(_ css: String, serviceID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[serviceIndex].templateCustomCSSSync = false
        services[serviceIndex].customCSS = css
        CustomCSSStorage.saveCSS(css, serviceID: serviceID)
        saveSettings()
    }

    func isTemplateActionScript(_ service: Service, action: CustomAction) -> Bool {
        defaultActionScript(for: service, action: action) != nil
    }

    func isTemplateActionScriptInSync(serviceID: UUID, actionID: UUID) -> Bool {
        services.first(where: { $0.id == serviceID })?.templateActionScriptSync[actionID] == true
    }

    func actionScript(for service: Service, action: CustomAction) -> String {
        if service.templateActionScriptSync[action.id] == true,
           let defaultScript = defaultActionScript(for: service, action: action) {
            return defaultScript
        }
        return ActionScriptStorage.loadScript(
            serviceID: service.id,
            actionID: action.id,
            fallback: service.actionScripts[action.id] ?? ""
        )
    }

    func setTemplateActionScriptSync(_ isInSync: Bool, serviceID: UUID, actionID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let action = customActions.first(where: { $0.id == actionID }),
              let defaultScript = defaultActionScript(for: services[serviceIndex], action: action) else {
            return
        }

        services[serviceIndex].templateActionScriptSync[actionID] = isInSync
        if isInSync {
            services[serviceIndex].actionScripts.removeValue(forKey: actionID)
            ActionScriptStorage.deleteScript(serviceID: serviceID, actionID: actionID)
        } else {
            let existingScript = ActionScriptStorage.loadScript(
                serviceID: serviceID,
                actionID: actionID,
                fallback: services[serviceIndex].actionScripts[actionID] ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if existingScript.isEmpty {
                services[serviceIndex].actionScripts[actionID] = defaultScript
                ActionScriptStorage.saveScript(defaultScript, serviceID: serviceID, actionID: actionID)
            }
        }
        saveSettings()
    }

    func saveCustomActionScript(_ script: String, serviceID: UUID, actionID: UUID) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[serviceIndex].templateActionScriptSync[actionID] = false
        services[serviceIndex].actionScripts[actionID] = script
        ActionScriptStorage.saveScript(script, serviceID: serviceID, actionID: actionID)
        saveSettings()
    }

    func resolveTemplateActionSyncMigration(updateScripts: Bool) {
        for serviceIndex in services.indices {
            for action in customActions where isTemplateActionScript(services[serviceIndex], action: action) {
                if updateScripts {
                    let serviceID = services[serviceIndex].id
                    services[serviceIndex].templateActionScriptSync[action.id] = true
                    services[serviceIndex].actionScripts.removeValue(forKey: action.id)
                    ActionScriptStorage.deleteScript(serviceID: serviceID, actionID: action.id)
                } else if services[serviceIndex].templateActionScriptSync[action.id] == nil {
                    services[serviceIndex].templateActionScriptSync[action.id] = false
                }
            }
        }
        clearMigrationDisposition(for: .templateActionScriptSync)
        saveSettings()
    }

    func resolveEngineShortcutToggleMigration(enable: Bool) {
        hideQuiperWhenRetriggeringActiveEngineShortcut = enable
        clearMigrationDisposition(for: .engineShortcutToggle)
        saveSettings()
    }

    /// Installs (or declines) the Cmd+, engine-Settings shortcut for existing
    /// settings that predate it. Opt-in, so the action and per-engine scripts are
    /// added to the current schema only when the user accepts.
    func resolveEngineSettingsShortcutMigration(add: Bool) {
        if add,
           let settingsAction = DefaultActions.defaults.first(where: { $0.id == DefaultEngineDefinitions.openSettingsActionID }) {
            if !customActions.contains(where: { $0.id == settingsAction.id }) {
                customActions.append(settingsAction)
            }
            for serviceIndex in services.indices
            where isTemplateActionScript(services[serviceIndex], action: settingsAction) {
                let serviceID = services[serviceIndex].id
                services[serviceIndex].templateActionScriptSync[settingsAction.id] = true
                services[serviceIndex].actionScripts.removeValue(forKey: settingsAction.id)
                ActionScriptStorage.deleteScript(serviceID: serviceID, actionID: settingsAction.id)
            }
        }
        didResolveEngineSettingsShortcutMigration = add
        clearMigrationDisposition(for: .engineSettingsShortcut)
        saveSettings()
    }

    /// User-facing setter that also settles any pending migration for this preference.
    func setHideQuiperWhenRetriggeringActiveEngineShortcut(_ enabled: Bool) {
        hideQuiperWhenRetriggeringActiveEngineShortcut = enabled
        clearMigrationDisposition(for: .engineShortcutToggle)
        saveSettings()
    }

    func setGlobalEngineDigitShortcutsEnabled(_ enabled: Bool) {
        globalEngineDigitShortcutsEnabled = enabled
        saveSettings()
    }

    private func applyEngineShortcutToggleSetting(persistedValue: Bool?) {
        if !persistedSettingsMigrationContext.isExistingSettings {
            hideQuiperWhenRetriggeringActiveEngineShortcut = true
            clearMigrationDisposition(for: .engineShortcutToggle)
            return
        }
        if let persistedValue {
            hideQuiperWhenRetriggeringActiveEngineShortcut = persistedValue
            clearMigrationDisposition(for: .engineShortcutToggle)
            return
        }

        // Existing settings from before this preference existed: keep old behavior and offer opt-in.
        hideQuiperWhenRetriggeringActiveEngineShortcut = false
        setMigrationDisposition(
            persistedSettingsMigrationContext.disposition(
                whenDetected: true,
                presentation: .prompted
            ),
            for: .engineShortcutToggle
        )
    }

    private func applyEngineSettingsShortcutMigrationSetting(persistedValue: Bool?) {
        if !persistedSettingsMigrationContext.isExistingSettings {
            didResolveEngineSettingsShortcutMigration = nil
            clearMigrationDisposition(for: .engineSettingsShortcut)
            return
        }
        if let persistedValue {
            didResolveEngineSettingsShortcutMigration = persistedValue
            clearMigrationDisposition(for: .engineSettingsShortcut)
            return
        }

        // Existing settings predating the Cmd+, engine-Settings action: offer to
        // install it unless the user already added the action another way.
        let settingsActionInstalled = customActions.contains { $0.id == DefaultEngineDefinitions.openSettingsActionID }
        setMigrationDisposition(
            persistedSettingsMigrationContext.disposition(
                whenDetected: !settingsActionInstalled,
                presentation: .prompted
            ),
            for: .engineSettingsShortcut
        )
    }

    private func beginPersistedSettingsMigrationEvaluation(
        loadedFromDisk: Bool,
        persistedVersion: String?
    ) {
        persistedSettingsMigrationContext = PersistedSettingsMigrationContext(
            loadedFromDisk: loadedFromDisk,
            persistedVersion: persistedVersion,
            currentVersion: Bundle.main.versionDisplayString
        )
        persistedSettingsMigrationDispositions.removeAll()
    }

    private func configureTemplateActionSyncMigration() {
        let detected = persistedSettingsMigrationContext.isUnversionedExistingSettings
            && hasTemplateActionScriptMigrationCandidates()
        setMigrationDisposition(
            persistedSettingsMigrationContext.disposition(
                whenDetected: detected,
                presentation: .prompted
            ),
            for: .templateActionScriptSync
        )
    }

    private func persistedQuiperVersionForSave() -> String? {
        if migrationDisposition(for: .templateActionScriptSync).isUnresolved {
            return nil
        }
        return persistedSettingsMigrationContext.versionForPersistence
    }

    private func persistedEngineShortcutToggleForSave() -> Bool? {
        migrationDisposition(for: .engineShortcutToggle).isUnresolved
            ? nil
            : hideQuiperWhenRetriggeringActiveEngineShortcut
    }

    private func persistedEngineSettingsShortcutMigrationForSave() -> Bool? {
        migrationDisposition(for: .engineSettingsShortcut).isUnresolved
            ? nil
            : didResolveEngineSettingsShortcutMigration
    }

    private func migrationDisposition(
        for migration: PersistedSettingsMigration
    ) -> PersistedSettingsMigrationDisposition {
        persistedSettingsMigrationDispositions[migration] ?? .notNeeded
    }

    private func setMigrationDisposition(
        _ disposition: PersistedSettingsMigrationDisposition,
        for migration: PersistedSettingsMigration
    ) {
        if disposition == .notNeeded {
            persistedSettingsMigrationDispositions.removeValue(forKey: migration)
        } else {
            persistedSettingsMigrationDispositions[migration] = disposition
        }
    }

    private func clearMigrationDisposition(for migration: PersistedSettingsMigration) {
        persistedSettingsMigrationDispositions.removeValue(forKey: migration)
    }
    
    private func hasTemplateActionScriptMigrationCandidates() -> Bool {
        for service in services {
            if customActions.contains(where: { isTemplateActionScript(service, action: $0) }) {
                return true
            }
        }
        return false
    }

    private func defaultServiceTemplate(for service: Service) -> Service? {
        ActionScripts.defaultServiceTemplate(for: service)
    }

    private func enableTemplateResourceSyncForBundledServices() {
        for serviceIndex in services.indices {
            let serviceID = services[serviceIndex].id
            if isTemplatePromptInputSelector(services[serviceIndex]) {
                services[serviceIndex].templatePromptInputSelectorSync = true
                services[serviceIndex].focus_selector = ""
                FocusSelectorStorage.deleteSelector(for: serviceID)
            }
            if isTemplateCustomCSS(services[serviceIndex]) {
                services[serviceIndex].templateCustomCSSSync = true
                services[serviceIndex].customCSS = nil
                CustomCSSStorage.deleteCSS(for: serviceID)
            }
        }
    }

    func deleteScripts(for actionID: UUID) {
        for index in services.indices {
            services[index].actionScripts.removeValue(forKey: actionID)
            services[index].templateActionScriptSync.removeValue(forKey: actionID)
            ActionScriptStorage.deleteScript(serviceID: services[index].id, actionID: actionID)
        }
        saveSettings()
    }

    func storeZoomLevel(_ value: CGFloat, for serviceID: UUID) {
        if serviceZoomLevels[serviceID] == value {
            return
        }
        serviceZoomLevels[serviceID] = value
        saveSettings()
    }

    func clearZoomLevel(for serviceID: UUID) {
        if serviceZoomLevels.removeValue(forKey: serviceID) != nil {
            saveSettings()
        }
    }

    func wipeAllData() {
        isPerformingWipe = true
        defer { isPerformingWipe = false }
        services.removeAll()
        customActions.removeAll()
        updatePreferences = UpdatePreferences()
        hotkeyConfiguration = HotkeyManager.defaultConfiguration
        serviceZoomLevels.removeAll()
        beginPersistedSettingsMigrationEvaluation(
            loadedFromDisk: false,
            persistedVersion: nil
        )
        hideQuiperWhenRetriggeringActiveEngineShortcut = true
        globalEngineDigitShortcutsEnabled = false
        engineSelectorDisplayMode = .auto
        sessionSelectorDisplayMode = .auto
        try? FileManager.default.removeItem(at: settingsFile)
        ActionScriptStorage.deleteAllScripts()
        CustomCSSStorage.deleteAllCSS()
        FocusSelectorStorage.deleteAllSelectors()
    }

    private func readPersistedSettings() -> (PersistedSettings, Bool) {
        if let data = try? Data(contentsOf: settingsFile) {
            if let payload = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
                return (payload, true)
            }
            if let legacyServices = try? JSONDecoder().decode([Service].self, from: data) {
                return (PersistedSettings(services: legacyServices,
                                          hotkey: nil,
                                          customActions: nil,
                                          updatePreferences: nil,
                                          serviceZoomLevels: nil), true)
            }
        }
        // Check for parameterized custom engines argument
        let customEnginesArg = CommandLine.arguments.first { $0.hasPrefix("--test-custom-engines=") }
        let isCustomEnginesFlag = CommandLine.arguments.contains("--test-custom-engines")

        // Check for custom path argument
        let customEnginesPathArg = CommandLine.arguments.first { $0.hasPrefix("--test-custom-engines-path=") }
        let customEnginesPath = customEnginesPathArg?.split(separator: "=").last.map(String.init)
        
        if let arg = customEnginesArg, let value = Int(arg.split(separator: "=").last ?? "") {
             let count = value
             let testEngines = (0..<count).map { i in
                 let index = i + 1
                 // Check for override file
                 let overrideFilename = "test-custom-engine-\(index).html"
                 let fileManager = FileManager.default
                 let directoryURL: URL
                 
                 if let customPath = customEnginesPath {
                     directoryURL = URL(fileURLWithPath: customPath)
                 } else {
                     directoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                 }
                 
                 let overrideFileObj = directoryURL.appendingPathComponent(overrideFilename)
                 
                 if fileManager.fileExists(atPath: overrideFileObj.path) {
                     return Service(name: "Engine \(index)", url: overrideFileObj.absoluteString, focus_selector: "")
                 } else {
                     // Use "Content X" to distinguish from Service Name "Engine X" in UI tests
                     // Add <title> for robust accessibility-based verification
                     let html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                     let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                     return Service(name: "Engine \(index)", url: dataURL, focus_selector: "")
                 }
             }
             return (PersistedSettings(services: testEngines,
                                       hotkey: nil,
                                       customActions: nil,
                                       updatePreferences: nil,
                                       serviceZoomLevels: nil), false)
        } else if isCustomEnginesFlag {
            // Fallback for non-parameterized usage (default to 4)
             let testEngines = (0..<4).map { i in
                 let index = i + 1
                 // Check for override file (duplicate logic for fallback case)
                 let overrideFilename = "test-custom-engine-\(index).html"
                 let fileManager = FileManager.default
                 let directoryURL: URL
                 
                 if let customPath = customEnginesPath {
                     directoryURL = URL(fileURLWithPath: customPath)
                 } else {
                     directoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                 }

                 let overrideFileObj = directoryURL.appendingPathComponent(overrideFilename)
                 
                 if fileManager.fileExists(atPath: overrideFileObj.path) {
                     return Service(name: "Engine \(index)", url: overrideFileObj.absoluteString, focus_selector: "")
                 } else {
                     let html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                     let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                     return Service(name: "Engine \(index)", url: dataURL, focus_selector: "")
                 }
             }
             return (PersistedSettings(services: testEngines,
                                       hotkey: nil,
                                       customActions: nil,
                                       updatePreferences: nil,
                                       serviceZoomLevels: nil), false)
        }
        
        let useDefaultServices = !CommandLine.arguments.contains("--no-default-services")
        return (PersistedSettings(services: useDefaultServices ? defaultEngines : [],
                                  hotkey: nil,
                                  customActions: nil,
                                  updatePreferences: nil,
                                  serviceZoomLevels: nil), false)
    }

    private func loadLegacyHotkeyConfiguration() -> HotkeyManager.Configuration? {
        guard FileManager.default.fileExists(atPath: legacyHotkeyFile.path) else { return nil }
        do {
            let data = try Data(contentsOf: legacyHotkeyFile)
            let config = try JSONDecoder().decode(HotkeyManager.Configuration.self, from: data)
            try? FileManager.default.removeItem(at: legacyHotkeyFile)
            return config
        } catch {
            return nil
        }
    }
    
    // Conflict logic moved to ShortcutValidator.swift
    
    private func digitValue(for keyCode: UInt16) -> Int {
        switch keyCode {
        case UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_Keypad1): return 1
        case UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_Keypad2): return 2
        case UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_Keypad3): return 3
        case UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_Keypad4): return 4
        case UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_Keypad5): return 5
        case UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_Keypad6): return 6
        case UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_Keypad7): return 7
        case UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_Keypad8): return 8
        case UInt16(kVK_ANSI_9), UInt16(kVK_ANSI_Keypad9): return 9
        case UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Keypad0): return 10
        default: return 0
        }
    }
}
