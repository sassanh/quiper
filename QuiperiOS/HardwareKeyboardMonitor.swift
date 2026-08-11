import Foundation
import GameController

@MainActor
protocol HardwareKeyboardMonitoring: AnyObject {
    var isConnected: Bool { get }
    var onConnectionChanged: ((Bool) -> Void)? { get set }
    func start()
}

@MainActor
final class HardwareKeyboardMonitor: HardwareKeyboardMonitoring {
    private(set) var isConnected = false
    var onConnectionChanged: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard observers.isEmpty else {
            refreshConnectionState()
            return
        }
        let center = NotificationCenter.default
        let names = [
            Notification.Name.GCKeyboardDidConnect,
            Notification.Name.GCKeyboardDidDisconnect
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.refreshConnectionState()
                }
            }
        }
        refreshConnectionState()
    }

    private func refreshConnectionState() {
        let connected = GCKeyboard.coalesced != nil
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChanged?(connected)
    }
}
