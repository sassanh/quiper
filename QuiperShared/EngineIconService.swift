import Foundation

/// Shared engine-icon logic: filling missing icons from the bundled defaults and
/// fetching favicons for the rest. Keeps macOS and iOS icon handling in sync.
enum EngineIconService {
    /// True when the service has no icon and the user hasn't intentionally removed it.
    static func isMissingIcon(_ service: Service) -> Bool {
        service.iconBase64 == nil && service.iconManuallyUnset != true
    }

    /// The bundled default engine's icon for a service whose name matches a default
    /// engine name (case-insensitive), or nil.
    static func defaultIcon(for service: Service, defaults: [Service]) -> String? {
        guard isMissingIcon(service) else { return nil }
        guard let match = defaults.first(where: { $0.name.lowercased() == service.name.lowercased() }) else {
            return nil
        }
        return match.iconBase64
    }

    /// Services that are eligible for automatic favicon fetching.
    static func servicesMissingIcons(in services: [Service]) -> [Service] {
        services.filter { isMissingIcon($0) && !$0.url.isEmpty }
    }

    /// Fetches favicons for the given services; returns serviceID -> base64 for the
    /// ones that succeeded.
    static func fetchFavicons(for services: [Service]) async -> [UUID: String] {
        var fetched: [UUID: String] = [:]
        for service in services {
            if let base64 = await FaviconFetcher.fetchFavicon(for: service.url) {
                fetched[service.id] = base64
            }
        }
        return fetched
    }
}
