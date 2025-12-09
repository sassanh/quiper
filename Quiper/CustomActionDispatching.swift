import Foundation

@MainActor
protocol CustomActionDispatching {
    func startMonitoring(windowController: MainWindowControlling)
    func stopMonitoring()
}
