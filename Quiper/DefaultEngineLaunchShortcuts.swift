import AppKit
import Carbon

/// Single source of truth for the bundled engines' default global launch shortcuts.
///
/// Every macOS seeding path (fresh-install defaults, engine templates) delegates
/// here so Option+letter assignments stay consistent. Matching is by engine name,
/// case-insensitive, so reordered or renamed stored copies still resolve.
enum DefaultEngineLaunchShortcuts {
    static func configuration(forEngineNamed name: String) -> HotkeyManager.Configuration? {
        let keyCode: Int
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "qwen":
            keyCode = kVK_ANSI_Q
        case "open webui", "open-webui", "openwebui":
            keyCode = kVK_ANSI_W
        case "z.ai", "zai":
            keyCode = kVK_ANSI_Z
        case "x":
            keyCode = kVK_ANSI_X
        case "opencode":
            keyCode = kVK_ANSI_C
        case "deepseek":
            keyCode = kVK_ANSI_D
        case "chatgpt", "chat gpt":
            keyCode = kVK_ANSI_T
        case "gemini":
            keyCode = kVK_ANSI_G
        case "google":
            keyCode = kVK_ANSI_S
        case "claude":
            keyCode = kVK_ANSI_A
        case "grok":
            keyCode = kVK_ANSI_R
        case "kimi":
            keyCode = kVK_ANSI_K
        case "omlx":
            keyCode = kVK_ANSI_M
        case "llama.cpp", "llama":
            keyCode = kVK_ANSI_L
        case "openclaw", "open claw":
            keyCode = kVK_ANSI_N
        default:
            return nil
        }
        return HotkeyManager.Configuration(
            keyCode: UInt32(keyCode),
            modifierFlags: NSEvent.ModifierFlags.option.rawValue
        )
    }

    /// Fills missing launch shortcuts on bundled engines without touching
    /// user-recorded or user-cleared values. Idempotent.
    static func apply(to services: [Service]) -> [Service] {
        services.map { service in
            guard service.activationShortcut == nil,
                  let configuration = configuration(forEngineNamed: service.name) else {
                return service
            }
            var copy = service
            copy.activationShortcut = configuration
            return copy
        }
    }

    /// Bundled engines in display order (cloud first, alphabetical) with
    /// default shortcuts applied. The single gate for fresh-install seeding.
    static var sortedDefaultEngines: [Service] {
        apply(to: DefaultEngineDefinitions.definitions.sorted { lhs, rhs in
            let lhsIsLocal = isLocalEngine(lhs)
            let rhsIsLocal = isLocalEngine(rhs)
            if lhsIsLocal != rhsIsLocal { return !lhsIsLocal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })
    }

    private static func isLocalEngine(_ service: Service) -> Bool {
        guard let host = URL(string: service.url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
