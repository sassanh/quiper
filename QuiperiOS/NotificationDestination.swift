import Foundation

struct NotificationDestination: Equatable, Sendable {
    let serviceID: UUID?
    let serviceURL: String?
    let sessionIndex: Int?

    init(userInfo: [AnyHashable: Any]) {
        serviceID = (userInfo[NotificationMetadata.serviceIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        serviceURL = (userInfo[NotificationMetadata.serviceURLKey]
            ?? userInfo[NotificationMetadata.legacyServiceURLKey]) as? String
        sessionIndex = Self.integerValue(
            userInfo[NotificationMetadata.sessionIndexKey]
                ?? userInfo[NotificationMetadata.legacySessionIndexKey]
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
