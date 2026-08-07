import Foundation

/// A single tab that should be re-instantiated when persisted session state is
/// restored, carrying the session's saved URL rather than falling back to the
/// engine home page.
struct RestoredTab: Identifiable, Equatable {
    var id: String { "\(serviceID.uuidString)-\(sessionIndex)" }

    let serviceID: UUID
    let sessionIndex: Int
    let url: URL
    let title: String?
    /// Whether the tab should load immediately (the active session) or lazily
    /// when it is next shown.
    let loadImmediately: Bool
}

extension PersistedTabState {
    /// Builds the ordered restore plan from persisted open tabs, matching the
    /// macOS restore semantics: every persisted tab is restored with its saved
    /// URL, and only the active session is marked to load immediately.
    func restoredTabs(
        services: [Service],
        activeIndexProvider: (UUID) -> Int
    ) -> [RestoredTab] {
        var result: [RestoredTab] = []
        for (svcID, sessions) in openTabs {
            guard services.contains(where: { $0.id == svcID }) else { continue }
            let activeIndex = activeIndexProvider(svcID)
            let titles = tabTitles[svcID] ?? [:]
            for (sessionIndex, urlString) in sessions {
                guard !urlString.isEmpty, let url = URL(string: urlString) else { continue }
                result.append(RestoredTab(
                    serviceID: svcID,
                    sessionIndex: sessionIndex,
                    url: url,
                    title: titles[sessionIndex],
                    loadImmediately: sessionIndex == activeIndex
                ))
            }
        }
        return result
    }
}
