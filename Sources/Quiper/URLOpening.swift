import AppKit

protocol URLOpening {
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: URLOpening {}
