import Combine
import Foundation

/// Session-level cache of template favicons so the Add Engine sheet can show a
/// template's icon the moment its own download finishes instead of waiting for
/// the whole batch. Downloads go through the shared `FaviconFetcher`, the same
/// fetcher that fills in icons for added engines.
@MainActor
final class EngineTemplateIconStore: ObservableObject {
    static let shared = EngineTemplateIconStore()

    /// Lowercased template name -> base64 PNG.
    @Published private(set) var icons: [String: String] = [:]

    private var inFlight: Set<String> = []

    /// The cached favicon for the template, falling back to the icon bundled
    /// with the template definition itself.
    func icon(for template: Service) -> String? {
        icons[template.name.lowercased()] ?? template.iconBase64
    }

    /// Starts a download for every template that has no icon yet. Each template
    /// publishes as soon as its own favicon is ready; templates already cached
    /// or downloading are skipped, and a failed download retries the next time
    /// the sheet opens.
    func loadIcons(for templates: [Service]) {
        for template in templates {
            let key = template.name.lowercased()
            guard icon(for: template) == nil,
                  !inFlight.contains(key),
                  !template.url.isEmpty else {
                continue
            }
            inFlight.insert(key)
            Task {
                let fetched = await FaviconFetcher.fetchFavicon(for: template.url)
                self.inFlight.remove(key)
                if let fetched {
                    self.icons[key] = fetched
                }
            }
        }
    }
}
