import AppKit

enum MenuFactory {
    
    // MARK: - Menu Creation
    
    static func createEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.autoenablesItems = true 
        
        let undoItem = createMenuItem(title: "Undo", iconName: nil, action: #selector(StandardEditActions.undo(_:)), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command]
        menu.addItem(undoItem)
        
        let redoItem = createMenuItem(title: "Redo", iconName: nil, action: #selector(StandardEditActions.redo(_:)), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)
        
        menu.addItem(.separator())
        
        menu.addItem(createMenuItem(title: "Cut", iconName: nil, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(createMenuItem(title: "Copy", iconName: nil, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(createMenuItem(title: "Paste", iconName: nil, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(createMenuItem(title: "Select All", iconName: nil, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        menu.addItem(.separator())
        
        // Find has an icon manually specified
        let findItem = createMenuItem(title: "Find...", iconName: "magnifyingglass", action: #selector(MainWindowController.presentFindPanelFromMenu(_:)), keyEquivalent: "f")
        menu.addItem(findItem)
        
        return menu
    }
    
    static func createViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.autoenablesItems = true
        
        let reloadItem = createMenuItem(title: "Reload", iconName: "arrow.clockwise", action: #selector(MainWindowController.reloadActiveWebView(_:)), keyEquivalent: "r")
        menu.addItem(reloadItem)
        
        let inspectorItem = createMenuItem(title: "Toggle Inspector", iconName: "ladybug", action: #selector(MainWindowController.performMenuToggleInspector(_:)), keyEquivalent: "i")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(inspectorItem)
        
        menu.addItem(.separator())
        
        let zoomInItem = createMenuItem(title: "Zoom In", iconName: "plus.magnifyingglass", action: #selector(MainWindowController.performMenuZoomIn(_:)), keyEquivalent: "+")
        menu.addItem(zoomInItem)
        
        let zoomOutItem = createMenuItem(title: "Zoom Out", iconName: "minus.magnifyingglass", action: #selector(MainWindowController.performMenuZoomOut(_:)), keyEquivalent: "-")
        menu.addItem(zoomOutItem)
        
        let resetZoomItem = createMenuItem(title: "Reset Zoom", iconName: "arrow.uturn.backward", action: #selector(MainWindowController.performMenuResetZoom(_:)), keyEquivalent: "0")
        menu.addItem(resetZoomItem)
        
        return menu
    }
    
    static func createWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.autoenablesItems = true
        
        let hideItem = createMenuItem(title: "Hide", iconName: "eye.slash", action: #selector(AppController.closeSettingsOrHide(_:)), keyEquivalent: "w")
        menu.addItem(hideItem)
        
        return menu
    }
    
    static func createActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Actions")
        menu.delegate = ActionMenuDelegate.shared
        return menu
    }
    
    static func populateActionsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let actions = Settings.shared.customActions
        if actions.isEmpty {
            let item = createMenuItem(title: "No Custom Actions", iconName: nil, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        
        for action in actions {
            let item = createMenuItem(title: action.name.isEmpty ? "Action" : action.name, 
                                      iconName: "bolt.fill", 
                                      action: #selector(MainWindowController.performCustomActionFromMenu(_:)), 
                                      keyEquivalent: "")
            item.representedObject = action
            menu.addItem(item)
        }
    }
    
    static func createSettingsItem() -> NSMenuItem {
        let item = createMenuItem(title: "Settings...", iconName: "gearshape", action: #selector(AppController.showSettings(_:)), keyEquivalent: ",")
        return item
    }
    
    static func createQuitItem() -> NSMenuItem {
        let item = createMenuItem(title: "Quit Quiper", iconName: "power", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.keyEquivalentModifierMask = [.command, .control, .shift]
        return item
    }
    
    // MARK: - Helpers
    
    static func createMenuItem(title: String, iconName: String?, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let iconName = iconName {
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
                image.isTemplate = true
                item.image = image
            }
        }
        return item
    }
}

class ActionMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = ActionMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        MenuFactory.populateActionsMenu(menu)
    }
}
