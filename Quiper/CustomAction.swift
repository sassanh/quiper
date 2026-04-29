import AppKit

struct CustomAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var shortcut: HotkeyManager.Configuration?

    enum CodingKeys: String, CodingKey {
        case id, name, shortcut
    }

    init(id: UUID = UUID(), name: String, shortcut: HotkeyManager.Configuration? = nil) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
    }
}

extension CustomAction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        shortcut = try container.decodeIfPresent(HotkeyManager.Configuration.self, forKey: .shortcut)
    }

    var displayShortcut: String {
        guard let shortcut else { return "Not assigned" }
        return ShortcutFormatter.string(for: shortcut)
    }
}
