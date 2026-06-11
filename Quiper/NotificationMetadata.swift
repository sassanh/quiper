enum NotificationMetadata {
    // Current keys using the official app bundle namespace
    static let serviceURLKey = "app.sassanh.quiper.serviceURL"
    static let serviceNameKey = "app.sassanh.quiper.serviceName"
    static let sessionIndexKey = "app.sassanh.quiper.sessionIndex"

    // Legacy keys kept for backward compatibility with notifications already in Notification Center
    // TODO: Clean up and remove these legacy keys and their fallbacks in a future release (e.g., v4.1.0+) once existing notifications have cleared.
    static let legacyServiceURLKey = "com.sassanharadji.quiper.serviceURL"
    static let legacyServiceNameKey = "com.sassanharadji.quiper.serviceName"
    static let legacySessionIndexKey = "com.sassanharadji.quiper.sessionIndex"
}
