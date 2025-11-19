
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case focus_selector
        case actionScripts
    }

    init(id: UUID = UUID(), name: String, url: String, focus_selector: String, actionScripts: [UUID: String] = [:]) {
        self.id = id
        self.name = name
        self.url = url
        self.focus_selector = focus_selector
        self.actionScripts = actionScripts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        focus_selector = try container.decode(String.self, forKey: .focus_selector)
        actionScripts = try container.decodeIfPresent([UUID: String].self, forKey: .actionScripts) ?? [:]
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
    }
}

extension Service: Equatable {}

struct UpdatePreferences: Codable, Equatable {
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var lastAutomaticCheck: Date?
    var lastNotifiedVersion: String?
}

private struct PersistedSettings: Codable {
    var services: [Service]
    var hotkey: HotkeyManager.Configuration?
    var customActions: [CustomAction]?
    var updatePreferences: UpdatePreferences?
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
                document.querySelector('button[aria-label="New Chat"]').click();
                """,
                Settings.reloadActionID: """
                window.location.reload();
                """,
                Settings.newTemporarySessionActionID: """
                document.querySelector('button[aria-label="New Chat"]').click();

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
                                            updatePreferences: updatePreferences)
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

    func wipeAllData() {
        isPerformingWipe = true
        services.removeAll()
        customActions.removeAll()
        updatePreferences = UpdatePreferences()
        hotkeyConfiguration = HotkeyManager.defaultConfiguration
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
                                          updatePreferences: nil), true)
            }
        }
        return (PersistedSettings(services: defaultEngines,
                                  hotkey: nil,
                                  customActions: nil,
                                  updatePreferences: nil), false)
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
}
