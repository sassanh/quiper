import Foundation

extension Notification.Name {
    static let shortcutRecordingDidTriggerReserved = Notification.Name("shortcutRecordingDidTriggerReserved")
    static let webDataCleared = Notification.Name("QuiperWebDataCleared")
    static let promptHistoryLimitChanged = Notification.Name("QuiperPromptHistoryLimitChanged")
    /// Posted with the service ID as object whenever an engine stylesheet
    /// changes for any reason (user edit, Hide, template sync toggle).
    static let engineCustomCSSChanged = Notification.Name("QuiperEngineCustomCSSChanged")
}
