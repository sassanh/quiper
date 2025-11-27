
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case focus_selector
        case actionScripts
        case activationShortcut
    }

    init(id: UUID = UUID(),
         name: String,
         url: String,
         focus_selector: String,
         actionScripts: [UUID: String] = [:],
         activationShortcut: HotkeyManager.Configuration? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
        self.activationShortcut = activationShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        focus_selector = try container.decode(String.self, forKey: .focus_selector)
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
        activationShortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .activationShortcut)
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
    }
}

extension Service: Equatable {}

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
class Settings: ObservableObject, CustomActionProvider {
    static let shared = Settings()

    @Published var services: [Service] = []
    @Published var hotkeyConfiguration: HotkeyManager.Configuration = HotkeyManager.defaultConfiguration
    @Published var customActions: [CustomAction] = []
    @Published var updatePreferences: UpdatePreferences = UpdatePreferences()
    @Published var serviceZoomLevels: [String: CGFloat] = [:]
    @Published var appShortcutBindings: AppShortcutBindings = .defaults

    private let settingsFile: URL = {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Quiper")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir.appendingPathComponent("settings.json")
    }()

    private let legacyHotkeyFile: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/quiper/hotkey_config.json")
    }()

    private static let newSessionActionID = UUID()
    private static let newTemporarySessionActionID = UUID()
    private static let reloadActionID = UUID()

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
            id: Settings.reloadActionID,
            name: "Reload",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_R),
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            )
        )
    ]

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
                document.querySelector('[href="/"]').click();
                """,
                Settings.reloadActionID: """
                window.location.reload();
                """,
                Settings.newTemporarySessionActionID: """
                document.querySelector('[href="/"]').click();

                async function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;

                    function task() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(task, 20);
                      }
                    }

                    setTimeout(task, 20);
                  });
                }

                (async () => {
                  await waitFor(() =>
                    document.querySelector('[aria-label="Turn on temporary chat"]')
                  );
                  const button = document.querySelector(
                    '[aria-label="Turn on temporary chat"]'
                  );
                  if (button) {
                    button.click();
                  }
                })();
                """
            ]
        ),
        Service(
            name: "Gemini",
            url: "https://gemini.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: ".textarea",
            actionScripts: [
                Settings.newSessionActionID: """
                document.querySelector('button[aria-label="New chat"]').click();
                """,
                Settings.reloadActionID: """
                window.location.reload();
                """,
                Settings.newTemporarySessionActionID: """
                async function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;

                    function task() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(task, 20);
                      }
                    }

                    setTimeout(task, 20);
                  });
                }

                async function openMenu() {
                  if (document.querySelector('mat-sidenav.mat-drawer-opened')) {
                    return;
                  } else {
                    document.querySelector('button[aria-label="Main menu"]').click();
                    await waitFor(() =>
                      document.querySelector('mat-sidenav.mat-drawer-opened')
                    );
                  }
                }

                async function newSession() {
                  document.querySelector('button[aria-label="New chat"]').click();
                  await waitFor(() =>
                    !document.querySelector('mat-sidenav.mat-drawer-opened')
                  );
                }

                async function run() {
                  await openMenu();
                  if (
                    document.querySelector('button[aria-label="Temporary chat"].temp-chat-on')
                  ) {
                    await newSession();
                  }
                  await openMenu();
                  document.querySelector('button[aria-label="Temporary chat"]').click();
                }

                run();
                """
            ]
        ),
        Service(
            name: "Grok",
            url: "https://grok.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[aria-label='Ask Grok anything'],div[contenteditable=true]",
            actionScripts: [
                Settings.newSessionActionID: """
                document
                  .querySelector('[href="/"]:not([aria-label="Home page"])')
                  .click();
                """,
                Settings.reloadActionID: """
                window.location.reload();
                """,
                Settings.newTemporarySessionActionID: """
                document
                  .querySelector('[href="/"]:not([aria-label="Home page"])')
                  .click();

                async function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;

                    function task() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(task, 20);
                      }
                    }

                    setTimeout(task, 20);
                  });
                }

                (async () => {
                  await waitFor(() =>
                    document.querySelector('[aria-label="Switch to Private Chat"]')
                  );
                  const button = document.querySelector(
                    '[aria-label="Switch to Private Chat"]'
                  );
                  if (button) {
                    button.click();
                  }
                })();
                """
            ]
        ),
        Service(
            name: "X",
            url: "https://x.com/i/grok?referrer=https://github.io/sassanh/quiper",
            focus_selector: "div[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                document.querySelector('button[aria-label="New Chat"]')?.click();
                """,
                Settings.reloadActionID: """
                window.location.reload();
                """,
                Settings.newTemporarySessionActionID: """
                document.querySelector('button[aria-label="New Chat"]')?.click();

                async function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;

                    function task() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(task, 20);
                      }
                    }

                    setTimeout(task, 20);
                  });
                }

                (async () => {
                  await waitFor(() =>
                    document.querySelector('button[aria-label="Private"]')
                  );
                  const button = document.querySelector('button[aria-label="Private"]');
                  if (button) {
                    button.click();
                  }
                })();
                """
            ]
        ),
        Service(
            name: "Ollama",
            url: "http://localhost:8080",
            focus_selector: "#chat-input[contenteditable='true']",
            actionScripts: [
                Settings.newSessionActionID: """
                document.querySelector('[href="/"]').click();

                function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;
                    function tick() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(tick, 20);
                      }
                    }
                    setTimeout(tick, 20);
                  });
                }

                (async () => {
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
                    ? Array.from(container.querySelectorAll("button"))
                    : [];

                  const target = buttons.find((button) => {
                    const hasLabel = Array.from(button.querySelectorAll("div")).some((div) =>
                      (div.textContent || "").trim().endsWith("Temporary Chat")
                    );
                    if (!hasLabel) { return false; }

                    const nestedToggle = Array.from(button.querySelectorAll("button")).find(
                      (nested) => nested !== button
                    );
                    return nestedToggle && nestedToggle.getAttribute("data-state") === "checked";
                  });

                  if (target) {
                    target.click();
                  } else if (modelButton && modelButton.getAttribute("data-state") === "open") {
                    modelButton.click();
                  }
                })();
                """,
                Settings.newTemporarySessionActionID: """
                document.querySelector('[href="/"]').click();

                function waitFor(check) {
                  return new Promise((resolve) => {
                    let iterations = 0;
                    function tick() {
                      iterations += 1;
                      if (check()) {
                        resolve();
                        return;
                      }
                      if (iterations < 250) {
                        setTimeout(tick, 20);
                      }
                    }
                    setTimeout(tick, 20);
                  });
                }

                (async () => {
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
                    ? Array.from(container.querySelectorAll("button"))
                    : [];

                  const target = buttons.find((button) => {
                    const hasLabel = Array.from(button.querySelectorAll("div")).some((div) =>
                      (div.textContent || "").trim().endsWith("Temporary Chat")
                    );
                    if (!hasLabel) { return false; }

                    const nestedToggle = Array.from(button.querySelectorAll("button")).find(
                      (nested) => nested !== button
                    );
                    return !nestedToggle || nestedToggle.getAttribute("data-state") !== "checked";
                  });

                  if (target) {
                    target.click();
                  } else if (modelButton && modelButton.getAttribute("data-state") === "open") {
                    modelButton.click();
                  }
                })();
                """,
                Settings.reloadActionID: """
                window.location.reload();
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
                Settings.reloadActionID: """
                window.location.reload();
                """
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
        customActions = loadedFromDisk ? (persisted.customActions ?? []) : defaultActions
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
                                            sessionDigitsAlternateModifiers: appShortcutBindings.sessionDigitsAlternateModifiers)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsFile)
        } catch {
            print("Error saving settings: \(error)")
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
        return (PersistedSettings(services: defaultEngines,
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
    
    func getReservedActionName(for config: HotkeyManager.Configuration) -> String? {
        if config == hotkeyConfiguration {
            return "Global Shortcut"
        }
        
        if let service = services.first(where: { $0.activationShortcut == config }) {
            return "Activate \(service.name)"
        }
        
        if let action = customActions.first(where: { $0.shortcut == config }) {
            return action.name
        }
        
        // Check App Shortcuts
        if appShortcutBindings.nextSession == config { return "Next Session" }
        if appShortcutBindings.previousSession == config { return "Previous Session" }
        if appShortcutBindings.nextService == config { return "Next Engine" }
        if appShortcutBindings.previousService == config { return "Previous Engine" }
        if appShortcutBindings.alternateNextSession == config { return "Next Session (Alternate)" }
        if appShortcutBindings.alternatePreviousSession == config { return "Previous Session (Alternate)" }
        if appShortcutBindings.alternateNextService == config { return "Next Engine (Alternate)" }
        if appShortcutBindings.alternatePreviousService == config { return "Previous Engine (Alternate)" }
        
        // Check session digit shortcuts (e.g., Cmd+1 for "Go to Session 1")
        let modifiers = NSEvent.ModifierFlags(rawValue: config.modifierFlags)
        let keyCode = UInt16(config.keyCode)
        if ShortcutValidator.isDigitKey(keyCode) {
            let primaryModifiers = modifiers.intersection([.command, .option, .control, .shift])
            let sessionMods = NSEvent.ModifierFlags(rawValue: appShortcutBindings.sessionDigitsModifiers)
            let sessionAltMods = appShortcutBindings.sessionDigitsAlternateModifiers.map { NSEvent.ModifierFlags(rawValue: $0) }
            let servicePrimaryMods = NSEvent.ModifierFlags(rawValue: appShortcutBindings.serviceDigitsPrimaryModifiers)
            let serviceSecondaryMods = appShortcutBindings.serviceDigitsSecondaryModifiers.map { NSEvent.ModifierFlags(rawValue: $0) }
            
            if primaryModifiers == sessionMods { return "Go to Session \(digitValue(for: keyCode))" }
            if let altMods = sessionAltMods, primaryModifiers == altMods { return "Go to Session \(digitValue(for: keyCode)) (Alternate)" }
            if primaryModifiers == servicePrimaryMods { return "Go to Engine \(digitValue(for: keyCode))" }
            if let secMods = serviceSecondaryMods, primaryModifiers == secMods { return "Go to Engine \(digitValue(for: keyCode)) (Secondary)" }
        }
        
        return nil
    }
    
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
