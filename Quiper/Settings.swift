import Combine
import Foundation
import AppKit
import SwiftUI
import Carbon

// Models extracted to SettingsModels.swift

struct Service: Codable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var focus_selector: String
    var actionScripts: [UUID: String] = [:]
    var activationShortcut: HotkeyManager.Configuration?
    var customCSS: String?
    var friendDomains: [String] = []
    var iconBase64: String?
    var iconManuallyUnset: Bool?
    var isEncrypted: Bool = false
    var lockOnSwitchAway: Bool = true
    var lockAfterInactivity: Bool = false
    var autoLockInactivityTimeout: Int = 5
    var preservePrompt: Bool = true

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case focus_selector
        case actionScripts
        case activationShortcut
        case friendDomains
        case customCSS
        case iconBase64
        case iconManuallyUnset
        case isEncrypted
        case lockOnSwitchAway
        case lockAfterInactivity
        case autoLockInactivityTimeout
        case autoLockPolicy // Keep for decoding legacy settings
        case preservePrompt
    }

    init(id: UUID = UUID(),
         name: String,
         url: String,
         focus_selector: String,
         actionScripts: [UUID: String] = [:],
         activationShortcut: HotkeyManager.Configuration? = nil,
         friendDomains: [String] = [],
         customCSS: String? = nil,
         iconBase64: String? = nil,
         iconManuallyUnset: Bool? = nil,
         isEncrypted: Bool = false,
         lockOnSwitchAway: Bool = true,
         lockAfterInactivity: Bool = false,
         autoLockInactivityTimeout: Int = 5,
         preservePrompt: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
        self.activationShortcut = activationShortcut
        self.friendDomains = friendDomains
        self.customCSS = customCSS
        self.iconBase64 = iconBase64
        self.iconManuallyUnset = iconManuallyUnset
        self.isEncrypted = isEncrypted
        self.lockOnSwitchAway = lockOnSwitchAway
        self.lockAfterInactivity = lockAfterInactivity
        self.autoLockInactivityTimeout = autoLockInactivityTimeout
        self.preservePrompt = preservePrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Service"
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        focus_selector = try container.decodeIfPresent(String.self, forKey: .focus_selector) ?? ""
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
        activationShortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .activationShortcut)
        friendDomains = try container.decodeIfPresent([String].self, forKey: .friendDomains) ?? []
        customCSS = try container.decodeIfPresent(String.self, forKey: .customCSS)
        iconBase64 = try container.decodeIfPresent(String.self, forKey: .iconBase64)
        iconManuallyUnset = try container.decodeIfPresent(Bool.self, forKey: .iconManuallyUnset)
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
        
        let switchAway = try container.decodeIfPresent(Bool.self, forKey: .lockOnSwitchAway)
        let inactivity = try container.decodeIfPresent(Bool.self, forKey: .lockAfterInactivity)
        
        if let switchAway = switchAway, let inactivity = inactivity {
            self.lockOnSwitchAway = switchAway
            self.lockAfterInactivity = inactivity
        } else if let legacyPolicy = try container.decodeIfPresent(AutoLockPolicy.self, forKey: .autoLockPolicy) {
            self.lockOnSwitchAway = (legacyPolicy == .onSwitchAway)
            self.lockAfterInactivity = (legacyPolicy == .afterInactivity)
        } else {
            self.lockOnSwitchAway = true
            self.lockAfterInactivity = false
        }
        
        autoLockInactivityTimeout = try container.decodeIfPresent(Int.self, forKey: .autoLockInactivityTimeout) ?? 5
        preservePrompt = try container.decodeIfPresent(Bool.self, forKey: .preservePrompt) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(focus_selector, forKey: .focus_selector)
        if !actionScripts.isEmpty {
            try container.encode(actionScripts, forKey: .actionScripts)
        }
        if let activationShortcut {
            try container.encode(activationShortcut, forKey: .activationShortcut)
        }
        if !friendDomains.isEmpty {
            try container.encode(friendDomains, forKey: .friendDomains)
        }
        if let customCSS, !customCSS.isEmpty {
            try container.encode(customCSS, forKey: .customCSS)
        }
        if let iconBase64 {
            try container.encode(iconBase64, forKey: .iconBase64)
        }
        if let iconManuallyUnset {
            try container.encode(iconManuallyUnset, forKey: .iconManuallyUnset)
        }
        try container.encode(isEncrypted, forKey: .isEncrypted)
        try container.encode(lockOnSwitchAway, forKey: .lockOnSwitchAway)
        try container.encode(lockAfterInactivity, forKey: .lockAfterInactivity)
        try container.encode(autoLockInactivityTimeout, forKey: .autoLockInactivityTimeout)
        try container.encode(preservePrompt, forKey: .preservePrompt)
    }
}

extension Service: Equatable {}

// Other models extracted to SettingsModels.swift

class SettingsWindow: NSWindow {
    static let shared = SettingsWindow()
    private var hostingController: NSHostingController<SettingsView>

    public weak var appController: AppController? {
        didSet {
            hostingController.rootView = SettingsView(appController: appController,
                                                      initialServiceURL: appController?.currentServiceURL)
            delegate = appController
        }
    }

    private init() {
        hostingController = NSHostingController(rootView: SettingsView(appController: nil, initialServiceURL: nil))
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

    @Published var services: [Service] = []
    @Published var hotkeyConfiguration: HotkeyManager.Configuration = HotkeyManager.defaultConfiguration
    @Published var customActions: [CustomAction] = []
    @Published var updatePreferences: UpdatePreferences = UpdatePreferences()
    @Published var serviceZoomLevels: [String: CGFloat] = [:]
    @Published var appShortcutBindings: AppShortcutBindings = .defaults
    @Published var dockVisibility: DockVisibility = .whenVisible {
        didSet {
            NotificationCenter.default.post(name: .dockVisibilityChanged, object: nil)
        }
    }
    @Published var selectorDisplayMode: SelectorDisplayMode = .auto {
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
    @Published var enablePromptHistory: Bool = true {
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
        updatePreferences = UpdatePreferences()
        serviceZoomLevels = [:]
        appShortcutBindings = .defaults
        selectorDisplayMode = .auto
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
        showOnAllSpaces = false
        settingsColorStyle = .colorful
        tabSurvivalPolicy = .always
        enablePromptHistory = true
        promptHistoryRecordOnSubmit = true
        promptHistoryRecordOnCmdBackspace = true
        promptHistoryRecordOnSelectionClear = false
        persistedTabState = nil
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

    private static let newSessionActionID = UUID()
    private static let newTemporarySessionActionID = UUID()
    private static let shareActionID = UUID()
    private static let historyActionID = UUID()

    private let defaultActions: [CustomAction] = [
        CustomAction(
            id: Settings.newSessionActionID,
            name: "New Session",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_N),
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            )
        ),
        CustomAction(
            id: Settings.newTemporarySessionActionID,
            name: "New Temporary Session",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_N),
                modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
            )
        ),
        CustomAction(
            id: Settings.shareActionID,
            name: "Share",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_S),
                modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
            )
        ),
        CustomAction(
            id: Settings.historyActionID,
            name: "History",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_H),
                modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
            )
        )
    ]

    var defaultActionTemplates: [CustomAction] {
        defaultActions
    }

    var defaultServiceTemplates: [Service] {
        defaultEngines
    }

    private static let defaultActionScriptHelpers = """
    function waitFor(check, timeoutMs = 1000) {
      return new Promise((resolve, reject) => {
        const start = Date.now();
        const step = () => {
          try {
            if (check()) { resolve(true); return; }
          } catch (err) {
            reject(err);
            return;
          }
          if (Date.now() - start >= timeoutMs) {
            reject(new Error(`waitFor timed out after ${timeoutMs}ms`));
            return;
          }
          window.requestAnimationFrame(step);
        };
        step();
      });
    }

    function quiperNormalize(value) {
      return (value || "").replace(/\\s+/g, " ").trim();
    }

    function quiperElements(selectors) {
      const found = [];
      for (const selector of selectors) {
        try {
          found.push(...document.querySelectorAll(selector));
        } catch {}
      }
      return [...new Set(found)];
    }

    function quiperIsVisible(element) {
      if (!element) { return false; }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) {
        return false;
      }
      const rects = element.getClientRects();
      return rects.length > 0 && [...rects].some((rect) => rect.width > 0 && rect.height > 0);
    }

    function quiperIsDisabled(element) {
      return !element ||
        element.disabled === true ||
        element.getAttribute("aria-disabled") === "true" ||
        element.closest("[aria-disabled='true']");
    }

    function quiperClickable(element) {
      return element?.closest("button,a,[role='button'],[role='menuitem'],[tabindex]") || element;
    }

    function quiperUsable(element) {
      const target = quiperClickable(element);
      return target && quiperIsVisible(target) && !quiperIsDisabled(target) ? target : null;
    }

    function quiperText(element) {
      return quiperNormalize([
        element?.getAttribute("aria-label"),
        element?.getAttribute("title"),
        element?.innerText,
        element?.textContent
      ].filter(Boolean).join(" "));
    }

    function quiperFind(selectors, options = {}) {
      const visible = options.visible !== false;
      for (const element of quiperElements(selectors)) {
        const target = quiperClickable(element);
        if (!target || quiperIsDisabled(target)) { continue; }
        if (visible && !quiperIsVisible(target)) { continue; }
        return target;
      }
      return null;
    }

    function quiperFindByText(labels, options = {}) {
      const visible = options.visible !== false;
      const normalizedLabels = labels.map( quiperNormalize ).filter(Boolean);
      const candidates = quiperElements([
        "button",
        "a",
        "[role='button']",
        "[role='menuitem']",
        "[tabindex]",
        "[aria-label]",
        "[title]",
        "span",
        "div"
      ]);

      for (const mode of ["exact", "contains"]) {
        for (const element of candidates) {
          const target = quiperClickable(element);
          if (!target || quiperIsDisabled(target)) { continue; }
          if (visible && !quiperIsVisible(target)) { continue; }
          const text = quiperText(element);
          if (!text) { continue; }
          const match = normalizedLabels.some((label) =>
            mode === "exact" ? text === label : text.includes(label)
          );
          if (match) { return target; }
        }
      }
      return null;
    }

    async function quiperClickElement(element, errorMessage = "Target not found") {
      const target = quiperUsable(element);
      if (!target) { throw new Error(errorMessage); }
      target.scrollIntoView({ block: "center", inline: "center" });
      target.click();
      await new Promise((resolve) => window.requestAnimationFrame(resolve));
      return target;
    }

    async function quiperClick(selectors, labels, errorMessage) {
      const target = quiperFind(selectors) || quiperFindByText(labels || []);
      return quiperClickElement(target, errorMessage);
    }

    async function quiperOpenDisclosure(disclosureSelectors, disclosureLabels, expectedSelectors, expectedLabels) {
      if (quiperFind(expectedSelectors || []) || quiperFindByText(expectedLabels || [])) {
        return;
      }
      const disclosure = quiperFind(disclosureSelectors || []) || quiperFindByText(disclosureLabels || []);
      if (!disclosure) { return; }
      await quiperClickElement(disclosure, "Disclosure button not found");
      await waitFor(() => quiperFind(expectedSelectors || []) || quiperFindByText(expectedLabels || []), 1200);
    }
    """

    private let defaultEngines: [Service] = [
        Service(
            name: "Gemini",
            url: "https://gemini.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "rich-textarea .textarea, .textarea, div[contenteditable='true'], textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const newChatSelectors = [
                  "a[aria-label='New chat'].gem-nav-list-item",
                  ".gds-sidenav-list a[aria-label='New chat']",
                  "mat-nav-list a[aria-label='New chat']",
                  "a[aria-label='New chat']:not(.side-nav-sparkle-button)",
                  "button[aria-label='New chat']"
                ];
                const activeTemporarySelectors = [
                  ".temp-chat-on button[aria-label='Temporary chat']",
                  ".temp-chat-on [aria-label='Temporary chat']",
                  "button[aria-label='Turn off temporary chat']",
                  "[aria-label='Turn off temporary chat']",
                  "button[aria-label='Temporary chat'].temp-chat-on",
                  "button[aria-label='Temporary chat'][aria-pressed='true']",
                  "[aria-label='Temporary chat'][aria-checked='true']"
                ];

                function geminiTemporaryActive() {
                  return quiperFind(activeTemporarySelectors) || quiperFindByText(["Temporary Chat"]);
                }

                function geminiTemporaryToggle() {
                  return quiperFind([
                    ".temp-chat-on button[aria-label='Temporary chat']",
                    ".temp-chat-on [aria-label='Temporary chat']",
                    "button[aria-label='Turn off temporary chat']",
                    "[aria-label='Turn off temporary chat']",
                    "button[aria-label='Temporary chat']",
                    "[aria-label='Temporary chat']"
                  ]);
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  newChatSelectors,
                  ["New chat", "New Chat"]
                );

                if (geminiTemporaryActive()) {
                  const temporaryToggle = geminiTemporaryToggle();
                  if (temporaryToggle) {
                    await quiperClickElement(temporaryToggle, "Temporary chat button not found");
                    await waitFor(() => !geminiTemporaryActive(), 1200);
                  }
                }

                await quiperClick(
                  newChatSelectors,
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const temporarySelectors = [
                  "button[aria-label='Temporary chat']",
                  "[aria-label='Temporary chat']"
                ];
                const activeTemporarySelectors = [
                  ".temp-chat-on button[aria-label='Temporary chat']",
                  ".temp-chat-on [aria-label='Temporary chat']",
                  "button[aria-label='Turn off temporary chat']",
                  "[aria-label='Turn off temporary chat']",
                  "button[aria-label='Temporary chat'].temp-chat-on",
                  "button[aria-label='Temporary chat'][aria-pressed='true']",
                  "[aria-label='Temporary chat'][aria-checked='true']"
                ];
                const newChatSelectors = [
                  "a[aria-label='New chat'].gem-nav-list-item",
                  ".gds-sidenav-list a[aria-label='New chat']",
                  "mat-nav-list a[aria-label='New chat']",
                  "a[aria-label='New chat']:not(.side-nav-sparkle-button)",
                  "button[aria-label='New chat']"
                ];
                function geminiTemporaryActive() {
                  return quiperFind(activeTemporarySelectors) || quiperFindByText(["Temporary Chat"]);
                }

                if (!quiperFind(temporarySelectors) && (quiperFind(["button[aria-label='Sign in']"]) || quiperFindByText(["Sign in"]))) {
                  throw new Error("Sign in to Gemini before creating a temporary chat");
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  newChatSelectors,
                  ["New chat", "New Chat"]
                );

                await quiperClick(
                  newChatSelectors,
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                await waitFor(() => quiperFind(temporarySelectors) || quiperFindByText(["Temporary chat", "Temporary"]), 2500);

                const temporaryButton = quiperFind(temporarySelectors) || quiperFindByText(["Temporary chat", "Temporary"]);
                if (!temporaryButton) { throw new Error("Temporary chat button not found"); }
                if (!geminiTemporaryActive()) {
                  await quiperClickElement(temporaryButton, "Temporary chat button not found");
                  await waitFor(() => geminiTemporaryActive(), 1500);
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                const shareDirect = quiperFind([
                  "button[aria-label='Share conversation']",
                  "[role='menuitem'][aria-label='Share conversation']",
                  "button[data-test-id='share-button']"
                ]) || quiperFindByText(["Share conversation"]);
                if (shareDirect) {
                  await quiperClickElement(shareDirect, "Share button not found");
                } else {
                  await quiperClick(
                    [
                      "button[aria-label='Open menu for conversation actions.']",
                      "button[aria-label='Open menu for conversation actions']"
                    ],
                    ["Open menu for conversation actions"],
                    "Conversation actions menu button not found"
                  );
                  await waitFor(() =>
                    quiperFind([
                      "button[aria-label='Share conversation']",
                      "[role='menuitem'][aria-label='Share conversation']",
                      "button[data-test-id='share-button']"
                    ]) || quiperFindByText(["Share conversation"])
                  );
                  await quiperClick(
                    [
                      "button[aria-label='Share conversation']",
                      "[role='menuitem'][aria-label='Share conversation']",
                      "button[data-test-id='share-button']"
                    ],
                    ["Share conversation"],
                    "Share button not found"
                  );
                }
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                const closeSidebar = quiperFind(["button[aria-label='Close sidebar']", "button[aria-label='Close navigation menu']"]);
                if (closeSidebar) {
                  await quiperClickElement(closeSidebar, "Close sidebar button not found");
                  return;
                }
                await quiperClick(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  "Sidebar button not found"
                );
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ],
            customCSS: """
            body, mat-sidenav-container, response-container>* {
              background-color: transparent !important;
            }
            input-container, input-container::before {
              background: transparent !important;
            }
            """
        ),
        Service(
            name: "Claude",
            url: "https://claude.ai?referrer=https://github.io/sassanh/quiper",
            focus_selector: "[data-testid='chat-input'] div[contenteditable='true'], div[contenteditable='true'], textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                async function claudeClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                const newChatSelectors = [
                  "a[aria-label='New chat']",
                  "button[aria-label='New chat']",
                  "a[href='/new']"
                ];
                const exitIncognito = quiperFind(["button[aria-label='Exit incognito']"]);
                if (exitIncognito) {
                  await claudeClick(exitIncognito, "Exit incognito button not found");
                }

                const newChat = quiperFind(newChatSelectors) || quiperFindByText(["New chat"]);
                if (newChat) {
                  await claudeClick(newChat, "New chat button not found");
                } else {
                  const target = new URL("/new", window.location.origin);
                  window.location.assign(target.href);
                }
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                async function claudeClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                const newChatSelectors = [
                  "a[aria-label='New chat']",
                  "button[aria-label='New chat']",
                  "a[href='/new']"
                ];
                const incognitoActive = () => location.search.includes("incognito") ||
                  Boolean(quiperFind(["button[aria-label='Exit incognito']"]));

                const newChat = quiperFind(newChatSelectors) || quiperFindByText(["New chat"]);
                if (newChat) {
                  await claudeClick(newChat, "New chat button not found");
                }

                if (!incognitoActive()) {
                  const incognitoButton = quiperFind(["button[aria-label='Use incognito']"]) ||
                    quiperFindByText(["Use incognito", "Incognito"]);
                  if (incognitoButton) {
                    await claudeClick(incognitoButton, "Use incognito button not found");
                  } else {
                    const target = new URL("/new", window.location.origin);
                    target.searchParams.set("incognito", "");
                    window.location.assign(target.href.replace("incognito=", "incognito"));
                  }
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                function claudeShareDialogVisible() {
                  return quiperElements(["[role='dialog']"]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    return /share chat|create public link|create share link/i.test(quiperText(element));
                  });
                }

                const shareButton = quiperFind([
                  "button[data-testid='wiggle-controls-actions-share']",
                  "[data-testid='wiggle-controls-actions-share']",
                  "button[aria-label='Share']"
                ]) || Array.from(document.querySelectorAll("button")).find((button) => {
                  if (!quiperIsVisible(button) || quiperIsDisabled(button)) { return false; }
                  if (button.closest("[role='dialog'], [role='menu'], [data-testid*='action-bar']")) { return false; }
                  const rect = button.getBoundingClientRect();
                  return rect.top <= Math.max(120, window.innerHeight * 0.2) &&
                    rect.left >= window.innerWidth * 0.45 &&
                    quiperNormalize(button.innerText || button.textContent || button.getAttribute("aria-label")) === "Share";
                });

                await quiperClickElement(shareButton, "Share button not found");
                await waitFor(() => claudeShareDialogVisible(), 1500);
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                await quiperClick(
                  [
                    "button[data-testid='pin-sidebar-toggle']",
                    "button[aria-label='Open sidebar']",
                    "button[aria-label='Close sidebar']",
                    "[data-testid='sidebar-toggle']"
                  ],
                  ["Open sidebar", "Close sidebar", "Sidebar", "Menu"],
                  "Sidebar button not found"
                );
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ],
            customCSS: """
            body, .bg-bg-500, .bg-bg-400, .bg-bg-300 {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Grok",
            url: "https://grok.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[aria-label='Ask Grok anything'], textarea, div[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const privateActiveSelectors = [
                  "[aria-label='Switch to Default Chat']",
                  "button[aria-label='Switch to Default Chat']"
                ];
                const privateInactiveSelectors = [
                  "[aria-label='Switch to Private Chat']",
                  "button[aria-label='Switch to Private Chat']",
                  "button[aria-label='Private']"
                ];
                const newChat = quiperFind([
                  "[data-testid='new-chat']",
                  "a[href='/']:not([aria-label='Home page'])",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New Chat", "New chat"]);
                const privateActive = quiperFind(privateActiveSelectors);
                if (privateActive) {
                  await quiperClickElement(privateActive, "Private chat toggle not found");
                  await waitFor(() => quiperFind(privateInactiveSelectors), 1500);
                }
                if (newChat) {
                  await quiperClickElement(newChat, "New Chat button not found");
                } else {
                  window.location.assign("/");
                }
                await waitFor(() => !quiperFind(privateActiveSelectors), 1500);
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const privateActiveSelectors = [
                  "[aria-label='Switch to Default Chat']",
                  "button[aria-label='Switch to Default Chat']"
                ];
                const privateInactiveSelectors = [
                  "[aria-label='Switch to Private Chat']",
                  "button[aria-label='Switch to Private Chat']",
                  "button[aria-label='Private']"
                ];
                const newChat = quiperFind([
                  "[data-testid='new-chat']",
                  "a[href='/']:not([aria-label='Home page'])",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New Chat", "New chat"]);
                if (newChat) {
                  await quiperClickElement(newChat, "New Chat button not found");
                } else {
                  window.history.pushState(null, "", "/");
                }

                await waitFor(() => quiperFind(privateActiveSelectors) || quiperFind(privateInactiveSelectors), 2000);
                if (!quiperFind(privateActiveSelectors)) {
                  await quiperClick(
                    privateInactiveSelectors,
                    ["Private", "Private Chat", "Switch to Private Chat"],
                    "Private chat button not found"
                  );
                  await waitFor(() => quiperFind(privateActiveSelectors), 1500);
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Create share link']", "button[aria-label='Share']", "[aria-label='Share']"],
                  ["Create share link", "Share"],
                  "Share button not found"
                );
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                if (window.innerWidth >= 700) {
                  const historySelectors = ["button[aria-label='History']", "[aria-label='History']"];
                  const historyVisible = () => quiperFind(historySelectors) || quiperFindByText(["History"]);
                  const sidebarToggle = quiperFindByText(["Toggle Sidebar"]) ||
                    quiperFind(["button[aria-label='Toggle sidebar']", "[aria-label='Toggle sidebar']"]);
                  if (!sidebarToggle) { throw new Error("Sidebar toggle button not found"); }

                  if (historyVisible()) {
                    await quiperClickElement(sidebarToggle, "Sidebar toggle button not found");
                    return;
                  }

                  await quiperClickElement(sidebarToggle, "Sidebar toggle button not found");
                  await waitFor(() => historyVisible(), 1500);

                  const historyHeader = quiperFind(historySelectors) || quiperFindByText(["History"]);
                  const expanded = historyHeader?.getAttribute("aria-expanded") === "true" ||
                    historyHeader?.getAttribute("data-state") === "open" ||
                    historyHeader?.closest("[data-state='open'], [aria-expanded='true']");
                  if (historyHeader && !expanded) {
                    await quiperClickElement(historyHeader, "History button not found");
                  }
                  return;
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Toggle sidebar']", "[aria-label='Toggle sidebar']"],
                  ["Toggle sidebar", "Menu"],
                  ["div[role='button'][aria-label='History']", "[aria-label='History']"],
                  ["History"]
                );
                await quiperClick(
                  ["div[role='button'][aria-label='History']", "[aria-label='History']"],
                  ["History"],
                  "History button not found"
                );
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?x\\.com(/|$)",
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ],
            customCSS: """
            body {
              background-color: transparent !important;
            }
            .chat-input-backdrop {
              background-image: none;
            }
            """
        ),
        Service(
            name: "ChatGPT",
            url: "https://chatgpt.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "#prompt-textarea, .ProseMirror[role='textbox'], [aria-label='Chat with ChatGPT'], textarea, div[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                function chatGPTButtonByText(label) {
                  return Array.from(document.querySelectorAll("button")).find((button) =>
                    quiperIsVisible(button) &&
                    !quiperIsDisabled(button) &&
                    quiperNormalize(button.innerText || button.textContent) === label
                  );
                }

                await quiperOpenDisclosure(
                  ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                  ["Open sidebar", "Menu"],
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']"],
                  ["New chat", "New Chat"]
                );
                await quiperClick(
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']", "button[aria-label='New chat']"],
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                const clearChat = chatGPTButtonByText("Clear chat");
                if (clearChat) {
                  await quiperClickElement(clearChat, "Clear chat button not found");
                  await waitFor(() => !chatGPTButtonByText("Clear chat"), 2000);
                }
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                function chatGPTButtonByText(label) {
                  return Array.from(document.querySelectorAll("button")).find((button) =>
                    quiperIsVisible(button) &&
                    !quiperIsDisabled(button) &&
                    quiperNormalize(button.innerText || button.textContent) === label
                  );
                }

                const temporarySelectors = [
                  "[aria-label='Turn on temporary chat']",
                  "[data-testid='temporary-chat-button']"
                ];
                const activeTemporarySelectors = [
                  "[aria-label='Turn off temporary chat']",
                  "[data-testid='temporary-chat-button'][aria-pressed='true']"
                ];
                if (!quiperFind(temporarySelectors) && (quiperFind(["[data-testid='login-button']"]) || quiperFindByText(["Log in"]))) {
                  throw new Error("Sign in to ChatGPT before creating a temporary chat");
                }

                if (quiperFind(activeTemporarySelectors)) {
                  const clearChat = chatGPTButtonByText("Clear chat");
                  if (clearChat) {
                    await quiperClickElement(clearChat, "Clear chat button not found");
                    await waitFor(() => !chatGPTButtonByText("Clear chat"), 2000);
                  }
                  return;
                }

                await quiperOpenDisclosure(
                  ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                  ["Open sidebar", "Menu"],
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']"],
                  ["New chat", "New Chat"]
                );
                await quiperClick(
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']", "button[aria-label='New chat']"],
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );

                await waitFor(() =>
                  quiperFind(temporarySelectors) ||
                  quiperFindByText(["Temporary chat"])
                );
                await quiperClick(
                  temporarySelectors,
                  ["Temporary chat", "Turn on temporary chat"],
                  "Temporary chat button not found"
                );
                await waitFor(() => quiperFind(activeTemporarySelectors), 1500);
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                function chatGPTShareButton() {
                  const candidates = quiperElements([
                    "button[data-testid='share-chat-button']",
                    "button[aria-label='Share'][data-testid='share-chat-button']",
                    "header button[aria-label='Share']",
                    "button[aria-label='Share'][aria-haspopup]",
                    "button[aria-label='Share']"
                  ]).map( quiperClickable ).filter((button) => {
                    if (!button || !quiperIsVisible(button) || quiperIsDisabled(button)) { return false; }
                    if (button.closest("[role='dialog'], [role='menu'], [data-radix-popper-content-wrapper]")) { return false; }
                    const rect = button.getBoundingClientRect();
                    return rect.top <= Math.max(160, window.innerHeight * 0.25) &&
                      rect.left >= window.innerWidth * 0.35;
                  });

                  return candidates
                    .sort((left, right) => {
                      const a = left.getBoundingClientRect();
                      const b = right.getBoundingClientRect();
                      return (a.top - b.top) || (b.right - a.right);
                    })[0] || null;
                }

                function chatGPTShareWidgetVisible() {
                  return quiperElements([
                    "[role='dialog']",
                    "[role='menu']",
                    "[data-radix-popper-content-wrapper]",
                    "[data-testid='share-modal']",
                    "[data-testid='share-dialog']"
                  ]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    const text = quiperText(element);
                    return /share|copy link|create link/i.test(text);
                  });
                }

                await quiperClickElement(chatGPTShareButton(), "Share button not found");
                await waitFor(() => chatGPTShareWidgetVisible(), 1500);
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function chatGPTSearchInput() {
                  return quiperElements([
                    "input[placeholder*='Search chats']",
                    "input[aria-label*='Search chats']",
                    "input[type='search']"
                  ]).find((input) => {
                    if (!quiperIsVisible(input)) { return false; }
                    const label = [
                      input.getAttribute("placeholder"),
                      input.getAttribute("aria-label"),
                      input.getAttribute("type")
                    ].filter(Boolean).join(" ");
                    return /search chats|search chat history|search/i.test(label);
                  }) || null;
                }

                function chatGPTSearchPanel() {
                  const input = chatGPTSearchInput();
                  if (!input) { return null; }
                  return input.closest("[role='dialog'], [data-radix-popper-content-wrapper]") ||
                    input.closest("form") ||
                    input.parentElement;
                }

                const searchInput = chatGPTSearchInput();
                if (searchInput) {
                  const inputRect = searchInput.getBoundingClientRect();
                  const searchPanel = chatGPTSearchPanel();
                  const panelButtons = searchPanel ? Array.from(searchPanel.querySelectorAll("button")) : [];
                  const closeButton = panelButtons.find((button) => {
                    const text = quiperText(button);
                    return quiperIsVisible(button) && !quiperIsDisabled(button) &&
                      /^(close|cancel)$/i.test(text);
                  }) || Array.from(document.querySelectorAll("button")).find((button) => {
                    if (!quiperIsVisible(button) || quiperIsDisabled(button)) { return false; }
                    const rect = button.getBoundingClientRect();
                    const verticallyAligned = rect.top < inputRect.bottom + 24 && rect.bottom > inputRect.top - 24;
                    const rightOfInput = rect.left > inputRect.right - 120;
                    return verticallyAligned && rightOfInput;
                  });
                  if (closeButton) {
                    await quiperClickElement(closeButton, "Close search button not found");
                  } else {
                    document.dispatchEvent(new KeyboardEvent("keydown", {
                      key: "Escape",
                      code: "Escape",
                      keyCode: 27,
                      which: 27,
                      bubbles: true
                    }));
                  }
                  await waitFor(() => !chatGPTSearchInput(), 1500);
                  return;
                }

                await quiperOpenDisclosure(
                  ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                  ["Open sidebar", "Menu"],
                  ["button[aria-label='Search chats']", "[data-testid='sidebar-search-button']"],
                  ["Search chats"]
                );
                await quiperClick(
                  ["button[aria-label='Search chats']", "[data-testid='sidebar-search-button']"],
                  ["Search chats"],
                  "Search chats button not found"
                );
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)",
                "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)"
            ],
            customCSS: """
            html, body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "X",
            url: "https://x.com/i/grok?referrer=https://github.io/sassanh/quiper",
            focus_selector: "div[contenteditable='true'], textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                async function xClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                function xPrivateActive() {
                  return /This chat won.t appear in your history/i.test(document.body.innerText || "") ||
                    Boolean(quiperFind([
                      "button[aria-label='Disable private']",
                      "button[aria-label='Turn off private']",
                      "button[aria-pressed='true'][aria-label*='Private']",
                      "[aria-selected='true'][aria-label*='Private']"
                    ]));
                }

                const privateButton = quiperFind(["button[aria-label='Private']", "[aria-label='Private']"]) ||
                  quiperFindByText(["Private"]);
                if (xPrivateActive() && privateButton) {
                  await xClick(privateButton, "Private button not found");
                }

                const grokHome = quiperFind(["a[href='/i/grok']", "a[aria-label='Grok']"]) ||
                  quiperFindByText(["Grok"]);
                if (grokHome) {
                  await xClick(grokHome, "Grok navigation button not found");
                } else {
                  window.history.pushState(null, "", "/i/grok");
                  window.dispatchEvent(new PopStateEvent("popstate"));
                }
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                async function xClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                function xPrivateActive() {
                  return /This chat won.t appear in your history/i.test(document.body.innerText || "") ||
                    Boolean(quiperFind([
                      "button[aria-label='Disable private']",
                      "button[aria-label='Turn off private']",
                      "button[aria-pressed='true'][aria-label*='Private']",
                      "[aria-selected='true'][aria-label*='Private']"
                    ]));
                }

                const grokHome = quiperFind(["a[href='/i/grok']", "a[aria-label='Grok']"]) ||
                  quiperFindByText(["Grok"]);
                if (grokHome) {
                  await xClick(grokHome, "Grok navigation button not found");
                } else {
                  window.history.pushState(null, "", "/i/grok");
                  window.dispatchEvent(new PopStateEvent("popstate"));
                }

                if (!xPrivateActive()) {
                  const privateButton = quiperFind(["button[aria-label='Private']", "[aria-label='Private']"]) ||
                    quiperFindByText(["Private"]);
                  await xClick(privateButton, "Private button not found");
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Share']", "[aria-label='Share']"],
                  ["Share"],
                  "Share button not found"
                );
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function xVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function xText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function xTopHistoryButton() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return /chat history|history/i.test(xText(element)) &&
                        rect.y < 140 &&
                        rect.width >= 20 &&
                        rect.height >= 20;
                    });
                }

                function xHistoryPanelOpen() {
                  const tablist = [...document.querySelectorAll("[role='tablist']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      const value = xText(element);
                      return /chats/i.test(value) &&
                        /bookmarks|images/i.test(value) &&
                        rect.width > 180 &&
                        rect.height > 30;
                    });
                  const searchInput = [...document.querySelectorAll("input,textarea,[contenteditable='true']")]
                    .filter(xVisible)
                    .find((element) => /search/i.test(xText(element) || element.getAttribute("placeholder") || ""));
                  return Boolean(tablist || searchInput || xHistoryCloseButton());
                }

                function xHistoryCloseButton() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return /^(close|close history)$/i.test(xText(element)) &&
                        rect.x > 70 &&
                        rect.y < 80 &&
                        rect.width >= 20 &&
                        rect.height >= 20;
                    });
                }

                async function xPressEscape() {
                  const eventInit = {
                    key: "Escape",
                    code: "Escape",
                    keyCode: 27,
                    which: 27,
                    bubbles: true,
                    cancelable: true
                  };
                  (document.activeElement || document.body).dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  document.dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  window.dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  await new Promise((resolve) => setTimeout(resolve, 250));
                }

                const historyButton = xTopHistoryButton();
                if (!historyButton) {
                  throw new Error("Chat history button not found");
                }

                if (xHistoryPanelOpen()) {
                  const closeButton = xHistoryCloseButton();
                  await quiperClickElement(closeButton || historyButton, "History close button not found");
                  try {
                    await waitFor(() => !xHistoryPanelOpen(), 1600);
                  } catch {
                    await xPressEscape();
                    await waitFor(() => !xHistoryPanelOpen(), 1600);
                  }
                } else {
                  await quiperClickElement(historyButton, "Chat history button not found");
                  await waitFor(() => xHistoryPanelOpen(), 1600);
                }
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ],
            customCSS: """
            body, div[data-testid="primaryColumn"] {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Open WebUI",
            url: "http://localhost:8080",
            focus_selector: "#chat-input[contenteditable='true'], textarea, div[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                await quiperClick(
                  ["a[href='/']", "button[aria-label='New Chat']", "[aria-label='New Chat']"],
                  ["New Chat", "New chat"],
                  "New chat button not found"
                );
                """,
                Settings.newTemporarySessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                function openWebUIVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function openWebUIText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function openWebUITemporaryActive() {
                  return new URL(location.href).searchParams.get("temporary-chat") === "true";
                }

                function openWebUITemporaryButton() {
                  const labelled = quiperFind([
                    "#temporary-chat-button",
                    "button[aria-label='Temporary Chat']",
                    "[aria-label='Temporary Chat']"
                  ]) || quiperFindByText(["Temporary Chat", "Temporary"]);
                  if (labelled) { return labelled; }

                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(openWebUIVisible)
                    .map((element) => ({ element, rect: element.getBoundingClientRect(), text: openWebUIText(element) }))
                    .filter(({ rect, text }) =>
                      rect.y < 64 &&
                      rect.x > window.innerWidth - 180 &&
                      rect.width >= 28 &&
                      rect.width <= 44 &&
                      rect.height >= 28 &&
                      rect.height <= 44 &&
                      !/Controls|Voice|Model|Add|Share|Menu/i.test(text)
                    )
                    .sort((a, b) => a.rect.x - b.rect.x)[0]?.element;
                }

                const newChat = quiperFind(["a[href='/']", "button[aria-label='New Chat']", "[aria-label='New Chat']"]) ||
                  quiperFindByText(["New Chat", "New chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                await new Promise((resolve) => setTimeout(resolve, 350));

                if (!openWebUITemporaryActive()) {
                  await quiperClickElement(openWebUITemporaryButton(), "Temporary button not found");
                  await waitFor(() => openWebUITemporaryActive(), 1800);
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                const copyButtons = quiperElements(["[aria-label='Copy']", "button[aria-label='Copy']"]).filter( quiperIsVisible );
                const target = quiperClickable(copyButtons.at(-1));
                await quiperClickElement(target, "Copy/share button not found");
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function openWebUIVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function openWebUIText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                const labelledToggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(openWebUIVisible)
                  .find((element) => /^(Open|Close|Toggle) Sidebar$/i.test(openWebUIText(element)));

                const chromeToggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(openWebUIVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) =>
                    rect.y < 64 &&
                    rect.x < 280 &&
                    rect.width >= 28 &&
                    rect.width <= 44 &&
                    rect.height >= 28 &&
                    rect.height <= 44
                  )
                  .sort((a, b) => b.rect.x - a.rect.x)[0]?.element;

                await quiperClickElement(labelledToggle || chromeToggle, "Sidebar/history button not found");
                await new Promise((resolve) => setTimeout(resolve, 250));
                """
            ],
            customCSS: """
            body, div.app>div, div.bg-white:has(form #chat-input-container) {
              background-color: transparent !important;
            }
            """,
        ),
        Service(
            name: "Z.ai",
            url: "https://chat.z.ai?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea, div[contenteditable='true'], [role='textbox']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                function zaiVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function zaiText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function zaiButtonByText(pattern) {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .find((element) => pattern.test(zaiText(element)));
                }

                function zaiSidebarExpanded() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 280 && rect.width > 120 && /New Chat|Chat/i.test(zaiText(element));
                    });
                }

                async function zaiClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                async function zaiEnsureSidebarOpen() {
                  if (zaiSidebarExpanded()) { return; }
                  const toggle = [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 80 && rect.y < 60 && rect.width >= 20 && rect.height >= 20;
                    });
                  await zaiClick(toggle, "Sidebar toggle button not found");
                  await waitFor(() => zaiSidebarExpanded(), 1800);
                }

                await zaiEnsureSidebarOpen();
                const chatButton = zaiButtonByText(/^Chat\\s*Chat$|^Chat$/i);
                if (chatButton) {
                  await zaiClick(chatButton, "Chat button not found");
                }
                const newChat = zaiButtonByText(/New Chat/i);
                await zaiClick(newChat, "New Chat button not found");
                await waitFor(() => quiperFind(["textarea", "[role='textbox']", "div[contenteditable='true']"]), 1800);
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Share']", "[aria-label='Share']", "[data-testid*='share']"],
                  ["Share"],
                  "Share button not found"
                );
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function zaiVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function zaiText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function zaiSidebarExpanded() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 280 && rect.width > 120 && /New Chat|Chat/i.test(zaiText(element));
                    });
                }

                const wasExpanded = zaiSidebarExpanded();
                const toggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(zaiVisible)
                  .find((element) => {
                    const rect = element.getBoundingClientRect();
                    return rect.y < 60 &&
                      rect.width >= 20 &&
                      rect.height >= 20 &&
                      (wasExpanded ? rect.x > 180 && rect.x < 280 : rect.x < 80);
                  });
                await quiperClickElement(toggle, "Sidebar toggle button not found");
                await waitFor(() => zaiSidebarExpanded() !== wasExpanded, 1800);
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ],
            customCSS: """
            body, #app {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "DeepSeek",
            url: "https://chat.deepseek.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea, div[contenteditable='true'], [role='textbox']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function deepseekComposerVisible() {
                  return [...document.querySelectorAll("textarea,[role='textbox'],div[contenteditable='true']")]
                    .some(deepseekVisible);
                }

                function deepseekAtHome() {
                  return new URL(location.href).pathname === "/";
                }

                function deepseekTopControls() {
                  return [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                    .filter(deepseekVisible)
                    .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                    .filter(({ rect }) => rect.y < 90 && rect.width >= 14 && rect.height >= 14)
                    .sort((a, b) => a.rect.x - b.rect.x);
                }

                async function deepseekClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 450));
                  return target;
                }

                const controls = deepseekTopControls();
                const newChat = controls.find(({ rect }, index) =>
                  index === 1 && rect.x < 180
                )?.element || quiperFind([
                  "a[href='/']",
                  "button[aria-label='New chat']",
                  "button[aria-label='New Chat']",
                  "[aria-label='New chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New chat", "New Chat"]);

                if (newChat) {
                  await deepseekClick(newChat, "New chat button not found");
                  try {
                    await waitFor(() => deepseekComposerVisible() && deepseekAtHome(), 1600);
                  } catch {}
                }

                if (!deepseekComposerVisible() || !deepseekAtHome()) {
                  location.assign("/");
                }
                """,
                Settings.shareActionID: """
                \(Settings.defaultActionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                const labelledShare = quiperFind([
                  "button[aria-label='Share']",
                  "[aria-label='Share']",
                  "[data-testid*='share']"
                ]) || quiperFindByText(["Share", "Share chat", "Share conversation"]);

                const topRightShare = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                  .filter(deepseekVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) =>
                    rect.y < 80 &&
                    rect.x > window.innerWidth - 90 &&
                    rect.width >= 20 &&
                    rect.height >= 20
                  )
                  .sort((a, b) => b.rect.x - a.rect.x)[0]?.element;

                await quiperClickElement(labelledShare || topRightShare, "Share button not found");
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function deepseekHistoryOpen() {
                  const hasHistoryLinks = [...document.querySelectorAll("a[href*='/a/chat/s/']")]
                    .filter(deepseekVisible)
                    .some((element) => element.getBoundingClientRect().x < 80);
                  const hasExpandedTopControls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                    .filter(deepseekVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.y < 90 && rect.x > 180 && rect.x < 280 && rect.width >= 14 && rect.height >= 14;
                    });
                  return hasHistoryLinks || hasExpandedTopControls;
                }

                const wasOpen = deepseekHistoryOpen();
                const controls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                  .filter(deepseekVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) => rect.y < 90 && rect.width >= 14 && rect.height >= 14)
                  .sort((a, b) => a.rect.x - b.rect.x);
                const toggle = controls.find(({ rect }) =>
                  wasOpen ? rect.x > 220 && rect.x < 280 : rect.x < 90
                )?.element || quiperFind([
                  "button[aria-label='Open sidebar']",
                  "button[aria-label='Toggle sidebar']",
                  "[aria-label='Open sidebar']",
                  "[aria-label='Toggle sidebar']"
                ]);

                await quiperClickElement(toggle, "Sidebar/history button not found");
                await new Promise((resolve) => setTimeout(resolve, 350));
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)",
                "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)"
            ],
            customCSS: """
            html, body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "llama.cpp",
            url: "http://localhost:8080",
            focus_selector: "[data-slot='input-area'] textarea.text-md, textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const newChat = quiperFind(
                  ["button[aria-label='New chat']", "button[aria-label='New Chat']", "a[href*='new_chat=true']"]
                ) || quiperFindByText(["New chat", "New Chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                const sidebarButton = [...document.querySelectorAll("button")]
                  .find((button) => quiperIsVisible(button) && /sidebar/i.test(quiperText(button)));
                if (!sidebarButton) { throw new Error("Sidebar/history button not found"); }
                sidebarButton.click();
                await new Promise((resolve) => window.requestAnimationFrame(resolve));
                """
            ],
            customCSS: """
            body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "oMLX",
            url: "http://localhost:8480/admin/chat",
            focus_selector: ".input-container textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(Settings.defaultActionScriptHelpers)
                const newChat = quiperFindByText(["New Chat", "New chat"]) ||
                  quiperFind(["button[aria-label='New Chat']", "button[aria-label='New chat']"]);
                if (newChat) {
                  await quiperClickElement(newChat, "New chat button not found");
                } else {
                  window.location.assign("/admin/chat");
                }
                """,
                Settings.historyActionID: """
                \(Settings.defaultActionScriptHelpers)
                function omlxViewportVisible(element) {
                  if (!element) { return false; }
                  const rect = element.getBoundingClientRect();
                  const style = window.getComputedStyle(element);
                  return rect.width > 0 &&
                    rect.height > 0 &&
                    rect.right > 0 &&
                    rect.left < window.innerWidth &&
                    rect.bottom > 0 &&
                    rect.top < window.innerHeight &&
                    style.display !== "none" &&
                    style.visibility !== "hidden";
                }

                function omlxText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                const visibleButtons = [...document.querySelectorAll("button,[role='button']")]
                  .filter(omlxViewportVisible);
                const explicitSidebarToggle = visibleButtons.find((element) =>
                  /chat\\.(open|close)_sidebar/i.test(omlxText(element))
                );
                const expandedNewChat = visibleButtons.find((element) => {
                  const rect = element.getBoundingClientRect();
                  return /New Chat/i.test(omlxText(element)) &&
                    rect.left >= 0 &&
                    rect.width > 100;
                });

                const sidebarToggle = explicitSidebarToggle || (expandedNewChat
                  ? visibleButtons
                    .filter((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.top < 80 &&
                        rect.left > 80 &&
                        rect.left < 280 &&
                        rect.width >= 18 &&
                        rect.height >= 18;
                    })
                    .sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left)[0]
                  : visibleButtons
                    .filter((element) => {
                      const rect = element.getBoundingClientRect();
                      const text = omlxText(element);
                      return rect.top < 80 &&
                        rect.left >= 0 &&
                        rect.left < 100 &&
                        rect.width >= 24 &&
                        rect.height >= 24 &&
                        !/oMLX|GitHub|settings|MODEL|PROFILE/i.test(text);
                    })
                    .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left)[0]);
                await quiperClickElement(sidebarToggle, "Sidebar/history button not found");
                """
            ],
            customCSS: """
            html {
              --bg-primary: transparent !important;
            }

            .right-sidebar-width, .sidebar-width {
              background-color: var(--bg-secondary);
            }
            """
        ),
        Service(
            name: "Google",
            url: "https://www.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[name='q'], input[name='q'], textarea[aria-label='Search'], input[aria-label='Search'], textarea[title='Search'], input[title='Search'], input[type='search']",
            actionScripts: [
                Settings.newSessionActionID: """
                const homeLink = [...document.querySelectorAll("a")].find((link) => {
                  try {
                    const rect = link.getBoundingClientRect();
                    const href = new URL(link.href, location.href);
                    return href.origin === location.origin &&
                      href.pathname === "/webhp" &&
                      rect.width > 0 &&
                      rect.height > 0;
                  } catch {
                    return false;
                  }
                });
                if (homeLink) {
                  homeLink.click();
                } else {
                  window.location.assign("https://www.google.com?referrer=https://github.io/sassanh/quiper");
                }
                """,
            ],
            friendDomains: [
                ".*"
            ],
            customCSS: """
            body, div[style*="max-width:100%;"] {
              background-color: transparent !important;
            }
            """
        )
    ]

    private var isPerformingWipe = false

    init() {
        _ = loadSettings()
        enrichMissingIconsIfNeeded()
    }

    func enrichMissingIconsIfNeeded() {
        var localUpdated = false
        for idx in 0..<services.count {
            if services[idx].iconBase64 == nil && services[idx].iconManuallyUnset != true {
                if let defaultMatch = defaultEngines.first(where: { $0.name.lowercased() == services[idx].name.lowercased() }),
                   let defaultB64 = defaultMatch.iconBase64 {
                    services[idx].iconBase64 = defaultB64
                    localUpdated = true
                }
            }
        }
        
        if localUpdated {
            self.saveSettings()
            NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
        }

        let enginesWithMissingIcons = services.filter { $0.iconBase64 == nil && $0.iconManuallyUnset != true && !$0.url.isEmpty }
        guard !enginesWithMissingIcons.isEmpty else { return }
        
        Task(priority: .background) {
            var fetchedIcons: [UUID: String] = [:]
            for service in enginesWithMissingIcons {
                if let base64 = await FaviconFetcher.fetchFavicon(for: service.url) {
                    fetchedIcons[service.id] = base64
                }
            }
            
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
        let (persisted, loadedFromDisk) = readPersistedSettings()
        
        services = persisted.services
        let useDefaultActions = !CommandLine.arguments.contains("--no-default-actions")
        customActions = loadedFromDisk ? (persisted.customActions ?? []) : (useDefaultActions ? defaultActions : [])
        updatePreferences = persisted.updatePreferences ?? UpdatePreferences()
        if let storedZooms = persisted.serviceZoomLevels {
            serviceZoomLevels = storedZooms.mapValues { CGFloat($0) }
        } else {
            serviceZoomLevels = [:]
        }
        appShortcutBindings = persisted.appShortcuts ?? .defaults
        if let altSessionDigits = persisted.sessionDigitsAlternateModifiers {
            appShortcutBindings.sessionDigitsAlternateModifiers = altSessionDigits
        }
        if dockVisibility != (persisted.dockVisibility ?? .whenVisible) {
            dockVisibility = persisted.dockVisibility ?? .whenVisible
        }
        if selectorDisplayMode != (persisted.selectorDisplayMode ?? .auto) {
            selectorDisplayMode = persisted.selectorDisplayMode ?? .auto
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
        showOnAllSpaces = persisted.showOnAllSpaces ?? false
        tabSurvivalPolicy = persisted.tabSurvivalPolicy ?? .always
        enablePromptHistory = persisted.enablePromptHistory ?? true
        promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit ?? true
        promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace ?? true
        promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear ?? false
        persistedTabState = persisted.persistedTabState
        if loadedFromDisk, let storedHotkey = persisted.hotkey {
            hotkeyConfiguration = storedHotkey
        } else if loadedFromDisk, let legacy = loadLegacyHotkeyConfiguration() {
            hotkeyConfiguration = legacy
            saveSettings()
        } else {
            hotkeyConfiguration = HotkeyManager.defaultConfiguration
        }
        return services
    }

    func defaultActionID(matching name: String) -> UUID? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return defaultActions.first { $0.name.lowercased() == normalized }?.id
    }

    func discardSavedTabs() {
        persistedTabState = nil
        saveSettings()
    }

    func saveSettings() {
        if isPerformingWipe {
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
                                            selectorDisplayMode: selectorDisplayMode,
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
                                            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
                                            promptHistoryRecordOnCmdBackspace: promptHistoryRecordOnCmdBackspace,
                                            promptHistoryRecordOnSelectionClear: promptHistoryRecordOnSelectionClear)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsFile)
        } catch {
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
            selectorDisplayMode: selectorDisplayMode,
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
            promptHistoryRecordOnSubmit: promptHistoryRecordOnSubmit,
            promptHistoryRecordOnCmdBackspace: promptHistoryRecordOnCmdBackspace,
            promptHistoryRecordOnSelectionClear: promptHistoryRecordOnSelectionClear
        )
    }

    func applyPersistedSettings(_ persisted: PersistedSettings) {
        services = persisted.services
        customActions = persisted.customActions ?? []
        updatePreferences = persisted.updatePreferences ?? UpdatePreferences()
        serviceZoomLevels = (persisted.serviceZoomLevels ?? [:]).mapValues { CGFloat($0) }
        appShortcutBindings = persisted.appShortcuts ?? .defaults
        if let altSessionDigits = persisted.sessionDigitsAlternateModifiers {
            appShortcutBindings.sessionDigitsAlternateModifiers = altSessionDigits
        }
        dockVisibility = persisted.dockVisibility ?? .whenVisible
        selectorDisplayMode = persisted.selectorDisplayMode ?? .auto
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
        showOnAllSpaces = persisted.showOnAllSpaces ?? false
        settingsColorStyle = persisted.settingsColorStyle ?? .colorful
        tabSurvivalPolicy = persisted.tabSurvivalPolicy ?? .always
        enablePromptHistory = persisted.enablePromptHistory ?? true
        promptHistoryRecordOnSubmit = persisted.promptHistoryRecordOnSubmit ?? true
        promptHistoryRecordOnCmdBackspace = persisted.promptHistoryRecordOnCmdBackspace ?? true
        promptHistoryRecordOnSelectionClear = persisted.promptHistoryRecordOnSelectionClear ?? false
        persistedTabState = persisted.persistedTabState
        if let storedHotkey = persisted.hotkey {
            hotkeyConfiguration = storedHotkey
        }
    }

    func deleteScripts(for actionID: UUID) {
        for index in services.indices {
            services[index].actionScripts.removeValue(forKey: actionID)
            ActionScriptStorage.deleteScript(serviceID: services[index].id, actionID: actionID)
        }
        saveSettings()
    }

    func storeZoomLevel(_ value: CGFloat, for serviceURL: String) {
        if serviceZoomLevels[serviceURL] == value {
            return
        }
        serviceZoomLevels[serviceURL] = value
        saveSettings()
    }

    func clearZoomLevel(for serviceURL: String) {
        if serviceZoomLevels.removeValue(forKey: serviceURL) != nil {
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
