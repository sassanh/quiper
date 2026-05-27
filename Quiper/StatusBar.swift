import AppKit
import Foundation
import Carbon
import UserNotifications

// MARK: - Status Bar Controller
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let iconProvider: StatusIconProvider
    private let menuBuilder: StatusMenuBuilder
    private let buttonFactory: StatusButtonFactory
    
    let appController = AppController()
    
    init(statusItemLength: CGFloat = NSStatusItem.squareLength,
         iconProvider: StatusIconProvider? = nil,
         menuBuilder: StatusMenuBuilder? = nil,
         buttonFactory: StatusButtonFactory? = nil) {
        
        self.statusItem = NSStatusBar.system.statusItem(withLength: statusItemLength)
        
        // Instantiate defaults safely inside the MainActor-isolated body
        self.iconProvider = iconProvider ?? StatusIconProvider()
        self.menuBuilder = menuBuilder ?? StatusMenuBuilder()
        self.buttonFactory = buttonFactory ?? StatusButtonFactory()
    }
    
    func install() {
        configureStatusItem()
        appController.start()
    }
    
    private func configureStatusItem() {
        statusItem.isVisible = true
        statusItem.behavior = [.removalAllowed]
        
        guard let button = statusItem.button else {
            assertionFailure("Expected NSStatusItem.button to be available")
            return
        }
        
        let size = NSStatusBar.system.thickness
        button.frame = NSRect(x: 0, y: 0, width: size, height: size)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.focusRingType = .none
        
        if let logo = iconProvider.loadStatusBarIcon() {
            logo.isTemplate = true
            button.imagePosition = .imageOnly
            button.image = logo
            button.title = ""
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "🔍"
            button.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        }
        
        if statusItem.menu == nil {
            rebuildStatusMenu()
            NotificationCenter.default.addObserver(forName: .inspectorVisibilityChanged, object: nil, queue: .main) { [weak self] note in
                let visible = (note.object as? Bool) ?? false
                Task { @MainActor [weak self] in
                    guard let self, let menu = self.statusItem.menu else { return }
                    let title = visible ? "Hide Inspector" : "Show Inspector"
                    if let item = menu.items.first(where: { $0.action == #selector(AppController.toggleInspector(_:)) }) {
                        item.title = title
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: .appVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
            NotificationCenter.default.addObserver(forName: .hotkeyConfigurationChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
            NotificationCenter.default.addObserver(forName: .notificationPermissionChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildStatusMenu()
                }
            }
        }
    }

    private func rebuildStatusMenu() {
        statusItem.menu = menuBuilder.buildStatusMenu(controller: appController)
    }
}

// MARK: - Status Button Factory
@MainActor
struct StatusButtonFactory {
    func makeCustomStatusButton(for statusItem: NSStatusItem) -> NSButton {
        guard let button = statusItem.button else {
            assertionFailure("Expected NSStatusItem.button to be available")
            return NSButton()
        }
        return button
    }
}

// MARK: - Icon Provider
@MainActor
struct StatusIconProvider {
    private let targetSize = NSSize(width: 18, height: 18)
    
    func loadStatusBarIcon() -> NSImage? {
        for url in statusIconCandidateURLs() {
            if let image = NSImage(contentsOf: url) {
                return resizedTemplateIcon(from: image)
            }
        }
        
        if let namedImage = NSImage(named: "logo") ?? NSImage(named: "logo_dark") {
            return resizedTemplateIcon(from: namedImage)
        }
        
        return nil
    }
    
    private func statusIconCandidateURLs() -> [URL] {
        var urls: [URL] = []
        
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
            urls.append(url)
        }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "logo") {
            urls.append(url)
        }
        
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("logo/logo.png", isDirectory: false),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            urls.append(resourceURL)
        }
        
        urls.append(contentsOf: developmentResourceCandidates())
        
        return urls
    }
    
    private func developmentResourceCandidates() -> [URL] {
        var candidates: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Sources/Quiper/logo/logo.png", isDirectory: false)
        if FileManager.default.fileExists(atPath: cwd.path) {
            candidates.append(cwd)
        }
        
        let sourceFileURL = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent("logo/logo.png", isDirectory: false)
        if FileManager.default.fileExists(atPath: sourceFileURL.path) {
            candidates.append(sourceFileURL)
        }
        
        return candidates
    }
    
    private func resizedTemplateIcon(from image: NSImage) -> NSImage {
        let icon = NSImage(size: targetSize)
        icon.lockFocus()
        defer { icon.unlockFocus() }
        
        let rect = NSRect(origin: .zero, size: targetSize)
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        icon.isTemplate = true
        return icon
    }
}

// MARK: - Menu Builder
@MainActor
struct StatusMenuBuilder {
    func buildStatusMenu(controller: AnyObject) -> NSMenu {
        let menu = NSMenu()
        
        func addItem(_ title: String, _ action: Selector?, _ keyEquivalent: String = "", _ modifiers: NSEvent.ModifierFlags = [], _ target: AnyObject?) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }
        
        let isVisible = (controller as? AppController)?.isWindowVisible ?? false
        let showHideTitle = isVisible ? "Hide Quiper" : "Show Quiper"
        let showHideAction = isVisible ? #selector(AppController.hideWindow(_:)) : #selector(AppController.showWindow(_:))
        let showHideItem = NSMenuItem(title: showHideTitle, action: showHideAction, keyEquivalent: "")
        showHideItem.target = controller
        if let hotkey = keyEquivalent(for: Settings.shared.hotkeyConfiguration) {
            showHideItem.keyEquivalent = hotkey.key
            showHideItem.keyEquivalentModifierMask = hotkey.modifiers
        }
        menu.addItem(showHideItem)
        menu.addItem(.separator())
        addItem("Settings", #selector(AppController.showSettings(_:)), ",", [.command], controller)
        addItem("Show Inspector", #selector(AppController.toggleInspector(_:)), "i", [.command, .option], controller)
        addItem("Set New Hotkey", #selector(AppController.setHotkey(_:)), "", [], controller)
        
        let notifStatus = NotificationDispatcher.shared.authorizationStatus
        let notifTitle: String
        switch notifStatus {
        case .authorized, .provisional: notifTitle = "Notifications: Authorized"
        case .denied: notifTitle = "Notifications: Denied"
        case .notDetermined: notifTitle = "Notifications: Not Enabled"
        #if os(iOS)
        case .ephemeral: notifTitle = "Notifications: Authorized"
        #endif
        @unknown default: notifTitle = "Notifications: Unknown"
        }
        addItem(notifTitle, #selector(AppController.openNotificationSettings(_:)), "", [], controller)
        
        addItem("Check for Updates…", #selector(AppController.checkForUpdates(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Install at Login", #selector(AppController.installAtLogin(_:)), "", [], controller)
        addItem("Uninstall from Login", #selector(AppController.uninstallFromLogin(_:)), "", [], controller)
        menu.addItem(.separator())
        addItem("Quit", #selector(NSApplication.terminate(_:)), "q", [.command, .shift, .control], NSApp)
        
        return menu
    }

    private func keyEquivalent(for configuration: HotkeyManager.Configuration) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard !configuration.isDisabled else { return nil }
        let modifiers = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags).intersection([.command, .option, .control, .shift])
        guard let key = character(for: UInt16(configuration.keyCode)) else { return nil }
        let normalizedKey = key.count == 1 ? key.lowercased() : key
        return (normalizedKey, modifiers)
    }

    private func character(for keyCode: UInt16) -> String? {
        if keyCode == UInt16(kVK_Delete) {
            return statusDeleteKeyEquivalent
        }
        if keyCode == UInt16(kVK_Space) {
            return " "
        }
        return statusKeyEquivalentMap[keyCode]
    }
}

private let statusDeleteKeyEquivalent: String = {
    guard let scalar = UnicodeScalar(NSDeleteCharacter) else { return "" }
    return String(Character(scalar))
}()

private let statusKeyEquivalentMap: [UInt16: String] = [
    UInt16(kVK_ANSI_A): "a",
    UInt16(kVK_ANSI_B): "b",
    UInt16(kVK_ANSI_C): "c",
    UInt16(kVK_ANSI_D): "d",
    UInt16(kVK_ANSI_E): "e",
    UInt16(kVK_ANSI_F): "f",
    UInt16(kVK_ANSI_G): "g",
    UInt16(kVK_ANSI_H): "h",
    UInt16(kVK_ANSI_I): "i",
    UInt16(kVK_ANSI_J): "j",
    UInt16(kVK_ANSI_K): "k",
    UInt16(kVK_ANSI_L): "l",
    UInt16(kVK_ANSI_M): "m",
    UInt16(kVK_ANSI_N): "n",
    UInt16(kVK_ANSI_O): "o",
    UInt16(kVK_ANSI_P): "p",
    UInt16(kVK_ANSI_Q): "q",
    UInt16(kVK_ANSI_R): "r",
    UInt16(kVK_ANSI_S): "s",
    UInt16(kVK_ANSI_T): "t",
    UInt16(kVK_ANSI_U): "u",
    UInt16(kVK_ANSI_V): "v",
    UInt16(kVK_ANSI_W): "w",
    UInt16(kVK_ANSI_X): "x",
    UInt16(kVK_ANSI_Y): "y",
    UInt16(kVK_ANSI_Z): "z",
    UInt16(kVK_ANSI_0): "0",
    UInt16(kVK_ANSI_1): "1",
    UInt16(kVK_ANSI_2): "2",
    UInt16(kVK_ANSI_3): "3",
    UInt16(kVK_ANSI_4): "4",
    UInt16(kVK_ANSI_5): "5",
    UInt16(kVK_ANSI_6): "6",
    UInt16(kVK_ANSI_7): "7",
    UInt16(kVK_ANSI_8): "8",
    UInt16(kVK_ANSI_9): "9",
    UInt16(kVK_ANSI_Grave): "`",
    UInt16(kVK_ANSI_Minus): "-",
    UInt16(kVK_ANSI_Equal): "=",
    UInt16(kVK_ANSI_LeftBracket): "[",
    UInt16(kVK_ANSI_RightBracket): "]",
    UInt16(kVK_ANSI_Semicolon): ";",
    UInt16(kVK_ANSI_Quote): "'",
    UInt16(kVK_ANSI_Comma): ",",
    UInt16(kVK_ANSI_Period): ".",
    UInt16(kVK_ANSI_Slash): "/",
    UInt16(kVK_ANSI_Backslash): "\\",
    UInt16(kVK_ISO_Section): "§",
    UInt16(kVK_F1): String(UnicodeScalar(NSF1FunctionKey)!),
    UInt16(kVK_F2): String(UnicodeScalar(NSF2FunctionKey)!),
    UInt16(kVK_F3): String(UnicodeScalar(NSF3FunctionKey)!),
    UInt16(kVK_F4): String(UnicodeScalar(NSF4FunctionKey)!),
    UInt16(kVK_F5): String(UnicodeScalar(NSF5FunctionKey)!),
    UInt16(kVK_F6): String(UnicodeScalar(NSF6FunctionKey)!),
    UInt16(kVK_F7): String(UnicodeScalar(NSF7FunctionKey)!),
    UInt16(kVK_F8): String(UnicodeScalar(NSF8FunctionKey)!),
    UInt16(kVK_F9): String(UnicodeScalar(NSF9FunctionKey)!),
    UInt16(kVK_F10): String(UnicodeScalar(NSF10FunctionKey)!),
    UInt16(kVK_F11): String(UnicodeScalar(NSF11FunctionKey)!),
    UInt16(kVK_F12): String(UnicodeScalar(NSF12FunctionKey)!),
    UInt16(kVK_UpArrow): String(UnicodeScalar(NSUpArrowFunctionKey)!),
    UInt16(kVK_DownArrow): String(UnicodeScalar(NSDownArrowFunctionKey)!),
    UInt16(kVK_LeftArrow): String(UnicodeScalar(NSLeftArrowFunctionKey)!),
    UInt16(kVK_RightArrow): String(UnicodeScalar(NSRightArrowFunctionKey)!),
    UInt16(kVK_Help): String(UnicodeScalar(NSHelpFunctionKey)!),
    UInt16(kVK_ForwardDelete): String(UnicodeScalar(NSDeleteFunctionKey)!),
    UInt16(kVK_Tab): "\t",
    UInt16(kVK_Return): "\r",
    UInt16(kVK_Escape): "\u{001B}",
    UInt16(kVK_PageUp): String(UnicodeScalar(NSPageUpFunctionKey)!),
    UInt16(kVK_PageDown): String(UnicodeScalar(NSPageDownFunctionKey)!),
    UInt16(kVK_End): String(UnicodeScalar(NSEndFunctionKey)!),
    UInt16(kVK_Home): String(UnicodeScalar(NSHomeFunctionKey)!),
    UInt16(kVK_ANSI_Keypad0): "0",
    UInt16(kVK_ANSI_Keypad1): "1",
    UInt16(kVK_ANSI_Keypad2): "2",
    UInt16(kVK_ANSI_Keypad3): "3",
    UInt16(kVK_ANSI_Keypad4): "4",
    UInt16(kVK_ANSI_Keypad5): "5",
    UInt16(kVK_ANSI_Keypad6): "6",
    UInt16(kVK_ANSI_Keypad7): "7",
    UInt16(kVK_ANSI_Keypad8): "8",
    UInt16(kVK_ANSI_Keypad9): "9",
    UInt16(kVK_ANSI_KeypadDecimal): ".",
    UInt16(kVK_ANSI_KeypadMultiply): "*",
    UInt16(kVK_ANSI_KeypadPlus): "+",
    UInt16(kVK_ANSI_KeypadClear): String(UnicodeScalar(NSClearDisplayFunctionKey)!),
    UInt16(kVK_ANSI_KeypadDivide): "/",
    UInt16(kVK_ANSI_KeypadEnter): "\r",
    UInt16(kVK_ANSI_KeypadMinus): "-",
    UInt16(kVK_ANSI_KeypadEquals): "="
]
