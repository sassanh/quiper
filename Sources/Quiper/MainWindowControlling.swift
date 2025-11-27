import Foundation
import AppKit

@MainActor
protocol MainWindowControlling: AnyObject {
    func show()
    func hide()
    func toggleInspector()
    var window: NSWindow? { get }
    func currentWebViewURL() -> URL?
    var activeServiceURL: String? { get }
    func focusInputInActiveWebview()
    func reloadServices()
    func setShortcutsEnabled(_ enabled: Bool)
    func logCustomAction(_ action: CustomAction)
    func selectService(at index: Int)
    func selectService(withURL url: String) -> Bool
    func switchSession(to index: Int)
}

extension MainWindowController: MainWindowControlling {}
