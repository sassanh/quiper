import Foundation

@MainActor
protocol HotkeyManaging {
    func registerCurrentHotkey(_ callback: @escaping () -> Void)
    func updateConfiguration(_ configuration: HotkeyManager.Configuration)
}

@MainActor
protocol EngineHotkeyManaging {
    func register(entries: [EngineHotkeyManager.Entry], onTrigger: @escaping (UUID) -> Void)
    func disable()
    func update(configuration: HotkeyManager.Configuration, for serviceID: UUID)
    func unregister(serviceID: UUID)
}

extension HotkeyManager: HotkeyManaging {}
extension EngineHotkeyManager: EngineHotkeyManaging {}
