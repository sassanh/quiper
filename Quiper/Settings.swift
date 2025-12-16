import Combine
import Foundation
import AppKit
import SwiftUI
import Carbon

struct Service: Codable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var focus_selector: String
    var actionScripts: [UUID: String] = [:]
    var activationShortcut: HotkeyManager.Configuration?
    var friendDomains: [String] = []

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case focus_selector
        case actionScripts
        case activationShortcut
        case friendDomains
    }

    init(id: UUID = UUID(),
         name: String,
         url: String,
         focus_selector: String,
         actionScripts: [UUID: String] = [:],
         activationShortcut: HotkeyManager.Configuration? = nil,
         friendDomains: [String] = []) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
        self.activationShortcut = activationShortcut
        self.friendDomains = friendDomains
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        focus_selector = try container.decode(String.self, forKey: .focus_selector)
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
        activationShortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .activationShortcut)
        friendDomains = try container.decodeIfPresent([String].self, forKey: .friendDomains) ?? []
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
    }
}

extension Service: Equatable {}

enum DockVisibility: String, Codable, Equatable, CaseIterable, Identifiable {
    case never = "Never"
    case whenVisible = "When Visible"
    case always = "Always"
    
    var id: String { rawValue }
}

struct UpdatePreferences: Codable, Equatable {
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var lastAutomaticCheck: Date?
    var lastNotifiedVersion: String?
}

struct AppShortcutBindings: Codable, Equatable {
    enum Key: String, CaseIterable, Codable, Identifiable {
        case nextSession
        case previousSession
        case nextService
        case previousService

        var id: String { rawValue }
    }

    enum ModifierGroup {
        case sessionDigits
        case serviceDigitsPrimary
        case serviceDigitsSecondary
    }

    var nextSession: HotkeyManager.Configuration
    var previousSession: HotkeyManager.Configuration
    var nextService: HotkeyManager.Configuration
    var previousService: HotkeyManager.Configuration
    var alternateNextSession: HotkeyManager.Configuration?
    var alternatePreviousSession: HotkeyManager.Configuration?
    var alternateNextService: HotkeyManager.Configuration?
    var alternatePreviousService: HotkeyManager.Configuration?
    var sessionDigitsModifiers: UInt
    var sessionDigitsAlternateModifiers: UInt?
    var serviceDigitsPrimaryModifiers: UInt
    var serviceDigitsSecondaryModifiers: UInt?

    static let defaults = AppShortcutBindings(
        nextSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        previousSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        nextService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        previousService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        alternateNextSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_L),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        ),
        alternatePreviousSession: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_H),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        ),
        alternateNextService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_L),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        alternatePreviousService: HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_H),
            modifierFlags: NSEvent.ModifierFlags([.command, .control]).rawValue
        ),
        sessionDigitsModifiers: NSEvent.ModifierFlags.command.rawValue,
        sessionDigitsAlternateModifiers: nil,
        serviceDigitsPrimaryModifiers: NSEvent.ModifierFlags([.command, .control]).rawValue,
        serviceDigitsSecondaryModifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
    )

    func configuration(for key: Key) -> HotkeyManager.Configuration {
        switch key {
        case .nextSession: return nextSession
        case .previousSession: return previousSession
        case .nextService: return nextService
        case .previousService: return previousService
        }
    }

    func alternateConfiguration(for key: Key) -> HotkeyManager.Configuration? {
        switch key {
        case .nextSession: return alternateNextSession
        case .previousSession: return alternatePreviousSession
        case .nextService: return alternateNextService
        case .previousService: return alternatePreviousService
        }
    }

    func defaultConfiguration(for key: Key) -> HotkeyManager.Configuration {
        AppShortcutBindings.defaults.configuration(for: key)
    }

    mutating func setConfiguration(_ configuration: HotkeyManager.Configuration, for key: Key) {
        switch key {
        case .nextSession: nextSession = configuration
        case .previousSession: previousSession = configuration
        case .nextService: nextService = configuration
        case .previousService: previousService = configuration
        }
    }

    mutating func setAlternateConfiguration(_ configuration: HotkeyManager.Configuration?, for key: Key) {
        switch key {
        case .nextSession: alternateNextSession = configuration
        case .previousSession: alternatePreviousSession = configuration
        case .nextService: alternateNextService = configuration
        case .previousService: alternatePreviousService = configuration
        }
    }
}

private struct PersistedSettings: Codable {
    var services: [Service]
    var hotkey: HotkeyManager.Configuration?
    var customActions: [CustomAction]?
    var updatePreferences: UpdatePreferences?
    var serviceZoomLevels: [String: Double]?
    var appShortcuts: AppShortcutBindings?
    var sessionDigitsAlternateModifiers: UInt?
    var dockVisibility: DockVisibility?
}

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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        setFrameAutosaveName("SettingsWindow")
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        title = "Settings"
        center()

        configureContentForGlass()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            contentViewController = hostingController
        } else {
            contentViewController = hostingController
        }
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
    
    func reset() {
        services = []
        hotkeyConfiguration = HotkeyManager.defaultConfiguration
        customActions = []
        updatePreferences = UpdatePreferences()
        serviceZoomLevels = [:]
        appShortcutBindings = .defaults
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
                .appendingPathComponent("Quiper")
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

    private let defaultEngines: [Service] = [
        Service(
            name: "ChatGPT",
            url: "https://chat.openai.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "#prompt-textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                if (!document.querySelector('[href="/"]')) {
                  document.querySelector('button[data-testid="open-sidebar-button"]').click();
                  await waitFor(() => document.querySelector('[href="/"]'), 300);
                  document.querySelector('[href="/"]').click();
                  document.querySelector('button[aria-label="Close sidebar"]').click();
                } else {
                  document.querySelector('[href="/"]').click();
                }

                """,
                Settings.newTemporarySessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                if (!document.querySelector('[href="/"]')) {
                  document.querySelector('button[data-testid="open-sidebar-button"]').click();
                  await waitFor(() => document.querySelector('[href="/"]'), 300);
                  document.querySelector('[href="/"]').click();
                  document.querySelector('button[aria-label="Close sidebar"]').click();
                } else {
                  document.querySelector('[href="/"]').click();
                }
                
                await waitFor(() =>
                  document.querySelector('[aria-label="Turn on temporary chat"]')
                );
                const button = document.querySelector(
                  '[aria-label="Turn on temporary chat"]'
                );
                if (!button) { throw new Error("Turn on temporary chat button not found"); }
                button.click();
                """,
                Settings.shareActionID: """
                const share = document.querySelector('[aria-label="Share"]');
                if (!share) { throw new Error("Share button not found"); }
                share.click();
                """,
                Settings.historyActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                function getHistoryButton() {
                  return [
                    ...document
                      .querySelector('nav div[data-sidebar-item="true"]')
                      ?.querySelectorAll("div") || [],
                  ].find((div) => (div.textContent || "").trim() === "Search chats");
                }

                if (!getHistoryButton()) {
                  document.querySelector('button[data-testid="open-sidebar-button"]').click();
                  await waitFor(() => getHistoryButton(), 300);
                  getHistoryButton().click();
                } else {
                  getHistoryButton().click();
                }
                """
            ], friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)",
                "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)"
            ]
        ),
        Service(
            name: "Gemini",
            url: "https://gemini.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: ".textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                const newChat = document.querySelector('button[aria-label="New chat"]');
                if (!newChat || newChat.disabled) { throw new Error("New chat button not found"); }
                newChat.click();
                """,
                Settings.newTemporarySessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");

                const mainMenuButton = document.querySelector('button[aria-label="Main menu"]');
                if (!mainMenuButton) {
                  throw new Error("Main menu button not found");
                }

                async function openMenu() {
                  if (document.querySelector("mat-sidenav")) {
                    if (document.querySelector("mat-sidenav.mat-drawer-opened")) {
                      return;
                    } else if (
                      document.querySelector('button[aria-label="Temporary chat"]')?.offsetWidth
                    ) {
                      return;
                    }
                  }

                  async function open() {
                    mainMenuButton.click();
                    if (document.querySelector("mat-sidenav")) {
                      await waitFor(() =>
                        document.querySelector("mat-sidenav.mat-drawer-opened"),
                      );
                    }
                    await waitFor(
                      () =>
                        document.querySelector('button[aria-label="Temporary chat"]')
                          ?.offsetWidth,
                    );
                  }

                  for (let i = 0; i < 5; i++) {
                    try {
                      await open();
                      await new Promise((resolve) => requestAnimationFrame(resolve));
                      return;
                    } catch {}
                  }
                  throw new Error("Failed to open menu");
                }

                async function closeMenu() {
                  if (document.querySelector("mat-sidenav")) {
                    if (
                      document.querySelector(
                        "mat-sidenav:not(.mat-drawer-opened,.mat-drawer-animating)",
                      )
                    ) {
                      return;
                    } else if (
                      !document.querySelector('button[aria-label="Temporary chat"]')
                        ?.offsetWidth
                    ) {
                      return;
                    }
                  }

                  async function close() {
                    if (document.querySelector("mat-sidenav")) {
                      if (!document.querySelector("mat-sidenav.mat-drawer-animating")) {
                        mainMenuButton.click();
                      }
                      await waitFor(() =>
                        document.querySelector("mat-sidenav:not(.mat-drawer-opened)"),
                      );
                    } else {
                      mainMenuButton.click();
                    }
                    await waitFor(
                      () =>
                        !document.querySelector('button[aria-label="Temporary chat"]')
                          ?.offsetWidth,
                      timeoutMs=300,
                    );
                  }

                  for (let i = 0; i < 5; i++) {
                    try {
                      await close();
                      await new Promise((resolve) => requestAnimationFrame(resolve));
                      return;
                    } catch {}
                  }
                  throw new Error("Failed to close menu");
                }

                async function newSession() {
                  const newChatButton = document.querySelector('button[aria-label="New chat"]');
                  if (!newChatButton) {
                    mainMenuButton.click();
                    throw new Error("New chat button not found");
                  }
                  if (newChatButton.disabled) {
                    mainMenuButton.click();
                    throw new Error("New chat button is disabled");
                  }
                  newChatButton.click();

                  await closeMenu();
                }

                await openMenu();
                if (
                  document.querySelector('button[aria-label="Temporary chat"].temp-chat-on')
                ) {
                  await newSession();
                  await openMenu();
                }

                await waitFor(
                  () =>
                    document.querySelector(
                      'button[aria-label="Temporary chat"]:not(.temp-chat-on)',
                    ).offsetWidth,
                );
                await new Promise((resolve) => requestAnimationFrame(resolve));
                document
                  .querySelector('button[aria-label="Temporary chat"]:not(.temp-chat-on)')
                  .click();
                if (!document.querySelector("mat-sidenav")) {
                  await new Promise((resolve) => requestAnimationFrame(resolve));
                  mainMenuButton.click();
                }
                """,
                Settings.shareActionID: """
                const shareAndExportButtons = [...document.querySelectorAll('button[aria-label="Share & export"]')];
                let shareButton = null;
                if (shareAndExportButtons.length > 0) {
                  shareAndExportButtons.at(-1).click();
                  shareButton = document.querySelector('button[aria-label="Share conversation"]');
                }
                else {
                  const buttons = [...document.querySelectorAll('button[aria-label="Show more options"]')];
                  const target = buttons.at(-1);
                  if (!target) { throw new Error("Show more options button not found"); }
                  target.click();
                  shareButton = document.querySelector('button[data-test-id="share-button"]');
                }
                if (!shareButton) { throw new Error("Share button not found"); }
                shareButton.click();
                """,
                Settings.historyActionID: """
                const mainMenuButton = document.querySelector('button[aria-label="Main menu"]');
                if (!mainMenuButton) {
                  throw new Error("Main menu button not found");
                }
                mainMenuButton.click();
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ]
        ),
        Service(
            name: "Grok",
            url: "https://grok.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[aria-label='Ask Grok anything'],div[contenteditable=true]",
            actionScripts: [
                Settings.newSessionActionID: """
                const newChatButton = document
                  .querySelector('[href="/"]:not([aria-label="Home page"])');
                if (!newChatButton) {
                  throw new Error("New Chat button not found");
                }
                newChatButton.click();
                """,
                Settings.newTemporarySessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                document
                  .querySelector('[href="/"]:not([aria-label="Home page"])')
                  ?.click();

                await waitFor(() =>
                  document.querySelector('[aria-label="Switch to Private Chat"]')
                );
                const button = document.querySelector(
                  '[aria-label="Switch to Private Chat"]'
                );
                if (!button) { throw new Error("Switch to Private Chat button not found"); }
                button.click();
                """,
                Settings.shareActionID: """
                const share = document.querySelector('button[aria-label="Create share link"]');
                if (!share) { throw new Error("Create share link button not found"); }
                share.click();
                """,
                Settings.historyActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                if (!document.querySelector('div[role="button"][aria-label="History"]')) {
                  document.querySelector('button[aria-label="Toggle sidebar"]').click();
                  await waitFor(() =>
                    document.querySelector('div[role="button"][aria-label="History"]')
                  );
                }
                document.querySelector('div[role="button"][aria-label="History"]').click();
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?x\\.com(/|$)",
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ]
        ),
        Service(
            name: "X",
            url: "https://x.com/i/grok?referrer=https://github.io/sassanh/quiper",
            focus_selector: "div[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                const newChatButton = document.querySelector('button[aria-label="New Chat"]');
                if (!newChatButton) { throw new Error("New Chat button not found"); }
                newChatButton.click();
                """,
                Settings.newTemporarySessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                document.querySelector('button[aria-label="New Chat"]')?.click();

                await waitFor(() =>
                  document.querySelector('button[aria-label="Private"]')
                );
                const button = document.querySelector('button[aria-label="Private"]');
                if (!button) { throw new Error("Private button not found"); }
                button.click();
                """,
                Settings.shareActionID: """
                const buttons = [...document.querySelectorAll('button[aria-label="Share"]')];
                const target = buttons.at(-1);
                if (!target) { throw new Error("Share button not found"); }
                target.click();
                """,
                Settings.historyActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                document.querySelector('button[aria-label="Chat history"]').click();
                """
            ],
            friendDomains: [
                "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)"
            ]
        ),
        Service(
            name: "Ollama",
            url: "http://localhost:8080",
            focus_selector: "#chat-input[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                const home = document.querySelector('[href="/"]');
                if (!home) { throw new Error("Home link not found"); }
                home.click();

                const modelButton = document.querySelector('button[aria-label="Select a model"]');
                if (modelButton && modelButton.getAttribute("data-state") === "closed") {
                  modelButton.click();
                }

                await waitFor(() =>
                  document.querySelector("[aria-labelledby='model-selector-0-button']")
                );

                const container = document.querySelector(
                  "[aria-labelledby='model-selector-0-button']"
                );
                const buttons = container
                  ? [...container.querySelectorAll("button")]
                  : [];

                const target = buttons.find((button) => {
                  const hasLabel = [...button.querySelectorAll("div")].some((div) =>
                    (div.textContent || "").trim().endsWith("Temporary Chat")
                  );
                  if (!hasLabel) { return false; }

                  const nestedToggle = [...button.querySelectorAll("button")].find(
                    (nested) => nested !== button
                  );
                  return nestedToggle && nestedToggle.getAttribute("data-state") === "checked";
                });

                if (target) {
                  target.click();
                } else if (modelButton && modelButton.getAttribute("data-state") === "open") {
                  modelButton.click();
                }
                """,
                Settings.newTemporarySessionActionID: """
                \(MainWindowController.jsTools["waitFor"] ?? "undefined");
                const home = document.querySelector('[href="/"]');
                if (!home) { throw new Error("Home link not found"); }
                home.click();

                const modelButton = document.querySelector('button[aria-label="Select a model"]');
                if (modelButton && modelButton.getAttribute("data-state") === "closed") {
                  modelButton.click();
                }

                await waitFor(() =>
                  document.querySelector("[aria-labelledby='model-selector-0-button']")
                );

                const container = document.querySelector(
                  "[aria-labelledby='model-selector-0-button']"
                );
                const buttons = container
                  ? [...container.querySelectorAll("button")]
                  : [];

                const target = buttons.find((button) => {
                  const hasLabel = [...button.querySelectorAll("div")].some((div) =>
                    (div.textContent || "").trim().endsWith("Temporary Chat")
                  );
                  if (!hasLabel) { return false; }

                  const nestedToggle = [...button.querySelectorAll("button")].find(
                    (nested) => nested !== button
                  );
                  return !nestedToggle || nestedToggle.getAttribute("data-state") !== "checked";
                });

                if (target) {
                  target.click();
                } else if (modelButton && modelButton.getAttribute("data-state") === "open") {
                  modelButton.click();
                }
                """,
                Settings.shareActionID: """
                const shareButton = [...document.querySelectorAll('[aria-label="Copy"]')].at(-1).querySelector("button");
                if (!shareButton) { throw new Error("Share button not found"); }
                shareButton.click();
                """,
                Settings.historyActionID: """
                document.querySelector('[aria-label="Toggle Sidebar"]').click();
                """
            ]
        ),
        Service(
            name: "Google",
            url: "https://www.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea, input[type='search']",
            actionScripts: [
                Settings.newSessionActionID: """
                window.location = "/";
                """,
            ]
        )
    ]

    private var isPerformingWipe = false

    init() {
        _ = loadSettings()
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
        dockVisibility = persisted.dockVisibility ?? .whenVisible
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

    func saveSettings() {
        if isPerformingWipe {
            isPerformingWipe = false
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
                                            dockVisibility: dockVisibility)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsFile)
        } catch {
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
        services.removeAll()
        customActions.removeAll()
        updatePreferences = UpdatePreferences()
        hotkeyConfiguration = HotkeyManager.defaultConfiguration
        serviceZoomLevels.removeAll()
        try? FileManager.default.removeItem(at: settingsFile)
        ActionScriptStorage.deleteAllScripts()
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
                 
                 let html: String
                 if fileManager.fileExists(atPath: overrideFileObj.path) {
                     if let content = try? String(contentsOf: overrideFileObj, encoding: .utf8) {
                         html = content
                     } else {
                         html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                     }
                 } else {
                     // Use "Content X" to distinguish from Service Name "Engine X" in UI tests
                     // Add <title> for robust accessibility-based verification
                     html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                 }
                 
                 let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                 return Service(name: "Engine \(index)", url: dataURL, focus_selector: "")
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
                 
                 let html: String
                 if fileManager.fileExists(atPath: overrideFileObj.path) {
                     if let content = try? String(contentsOf: overrideFileObj, encoding: .utf8) {
                         html = content
                     } else {
                         html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                     }
                 } else {
                     html = "<html><head><title>Content \(index)</title></head><body><h1>Content \(index)</h1></body></html>"
                 }
                 
                 let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                 return Service(name: "Engine \(index)", url: dataURL, focus_selector: "")
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
