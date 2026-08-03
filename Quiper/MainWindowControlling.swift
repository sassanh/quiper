import Foundation
import AppKit
import WebKit

@MainActor
protocol MainWindowControlling: AnyObject {
    func show()
    func hide()
    func toggleInspector()
    var window: NSWindow? { get }
    var activeServiceID: UUID? { get }
    var activeWebView: WKWebView? { get }
    var isWebContentFullscreen: Bool { get }
    var isActiveSpaceWebFullscreen: Bool { get }
    func showWebFullScreenBanner()
    func focusInputInActiveWebview()
    func focusInputInActiveWebviewWithFallback()
    func reloadServices()
    func setShortcutsEnabled(_ enabled: Bool)
    func performCustomAction(_ action: CustomAction)
    func selectService(at index: Int)
    func selectService(withID id: UUID) -> Bool
    func switchSession(to index: Int)
    func showQuitOverlay()
    func saveTabsState()
}

extension MainWindowController: MainWindowControlling {}
