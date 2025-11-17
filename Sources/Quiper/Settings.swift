
import Foundation
import AppKit
import SwiftUI

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

private struct PersistedSettings: Codable {
    var services: [Service]
    var hotkey: HotkeyManager.Configuration?
    var customActions: [CustomAction]?
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

    private let defaultEngines: [Service] = [
        Service(name: "ChatGPT", url: "https://chat.openai.com", focus_selector: "#prompt-textarea"),
        Service(name: "Gemini", url: "https://gemini.google.com", focus_selector: ".textarea"),
        Service(name: "Grok", url: "https://grok.com", focus_selector: "textarea[aria-label='Ask Grok anything'],div[contenteditable=true]")
    ]

    init() {
        _ = loadSettings()
    }

    func loadSettings() -> [Service] {
        let persisted = readPersistedSettings()
        services = persisted.services
        customActions = persisted.customActions ?? []
        if let storedHotkey = persisted.hotkey {
            hotkeyConfiguration = storedHotkey
        } else if let legacy = loadLegacyHotkeyConfiguration() {
            hotkeyConfiguration = legacy
            saveSettings()
        } else {
            hotkeyConfiguration = HotkeyManager.defaultConfiguration
        }
        return services
    }

    func saveSettings() {
        do {
            let payload = PersistedSettings(services: services, hotkey: hotkeyConfiguration, customActions: customActions)
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

    private func readPersistedSettings() -> PersistedSettings {
        if let data = try? Data(contentsOf: settingsFile) {
            if let payload = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
                return payload
            }
            if let legacyServices = try? JSONDecoder().decode([Service].self, from: data) {
                return PersistedSettings(services: legacyServices, hotkey: nil)
            }
        }
        return PersistedSettings(services: defaultEngines, hotkey: nil)
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
