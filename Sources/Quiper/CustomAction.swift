import AppKit

struct CustomAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var shortcut: HotkeyManager.Configuration?

    init(id: UUID = UUID(), name: String, shortcut: HotkeyManager.Configuration? = nil) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
    }
}

extension CustomAction {
    var displayShortcut: String {
        guard let shortcut else { return "Not assigned" }
        return ShortcutFormatter.string(for: shortcut)
    }
}
