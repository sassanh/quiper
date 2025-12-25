import Foundation
import AppKit
import WebKit

@MainActor
protocol MainWindowControlling: AnyObject {
    func show()
    func hide()
    func toggleInspector()
    var window: NSWindow? { get }
    var activeServiceURL: String? { get }
    var activeWebView: WKWebView? { get }
    func focusInputInActiveWebview()
    func reloadServices()
    func setShortcutsEnabled(_ enabled: Bool)
    func performCustomAction(_ action: CustomAction)
    func selectService(at index: Int)
    func selectService(withURL url: String) -> Bool
    func switchSession(to index: Int)
}

extension MainWindowController: MainWindowControlling {}
