import Foundation

/// The private `quiper://` handoff between the resident link helper and the
/// main app. The helper claims web links in Quiper's place, decides each one
/// itself, and wraps the claimed ones in this route — opening it activates
/// the main app exactly like a direct URL handoff would.
enum QuiperLinkRoute {
    static let scheme = "quiper"
    private static let host = "route"
    private static let linkQueryItem = "url"

    /// The route URL that carries `link` to the main app:
    /// `quiper://route?url=<percent-encoded link>`.
    static func wrapping(_ link: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: linkQueryItem, value: link.absoluteString)]
        return components.url
    }

    /// The link a route carries; nil when the URL is not a well-formed route.
    static func link(in routeURL: URL) -> URL? {
        guard routeURL.scheme?.lowercased() == scheme,
              routeURL.host?.lowercased() == host,
              let components = URLComponents(url: routeURL, resolvingAgainstBaseURL: false),
              let linkString = components.queryItems?.first(where: { $0.name == linkQueryItem })?.value,
              let link = URL(string: linkString) else {
            return nil
        }
        return link
    }
}

/// Where the link helper opens a URL Launch Services delivered to it.
nonisolated enum LinkHelperDecision: Equatable {
    /// A claimed link: opened in the main app through a `quiper://` route.
    case routeToQuiper(link: URL)
    /// An unclaimed web link: opened straight in the fallback browser, with
    /// an explicit target so it never routes back through the helper.
    case openInFallbackBrowser(link: URL, bundleIdentifier: String)
    /// A file or foreign scheme: handed to the system's own opener.
    case passToSystemDefault(link: URL)
}

/// The single decision the link helper makes for a delivered URL, and the
/// bundle locations both apps derive from. Pure: every system lookup
/// arrives as a parameter, so the whole matrix is unit-testable and the
/// helper and main app share one implementation.
enum LinkHelperRouting {
    /// The helper's app bundle name inside the host's LoginItems folder.
    static let helperAppName = "QuiperLinkHelper.app"

    /// - Parameters:
    ///   - link: the URL Launch Services delivered to the helper.
    ///   - services: the engines and their claims, read at receipt, with
    ///     the secured metadata of every unlocked secure engine applied.
    ///   - isEngineUnlocked: whether a secure engine's volume is mounted —
    ///     only such engines may claim; the helper never unlocks one.
    ///   - familyRootBundleIdentifier: the host app's bundle identifier —
    ///     the root every Quiper-family identifier shares.
    ///   - recordedFallbackBundleIdentifier: the fallback recorded in settings.
    ///   - resolvable: whether a bundle identifier still resolves on disk.
    ///   - defaultOpenerBundleIdentifier: the system default opener for
    ///     `link`, nil when the system has none.
    static func decision(
        for link: URL,
        services: [Service],
        isEngineUnlocked: (UUID) -> Bool,
        familyRootBundleIdentifier: String,
        recordedFallbackBundleIdentifier: String?,
        resolvable: (String) -> Bool,
        defaultOpenerBundleIdentifier: String?
    ) -> LinkHelperDecision {
        if link.scheme == "http" || link.scheme == "https" {
            if ExternalLinkRouting.claimedService(for: link, in: services, isEngineUnlocked: isEngineUnlocked) != nil {
                return .routeToQuiper(link: link)
            }
            // The helper is the system default for web links; opening the
            // link "normally" would deliver it straight back. The explicit
            // fallback target ends the chain.
            return .openInFallbackBrowser(
                link: link,
                bundleIdentifier: DefaultBrowserRouting.fallbackBundleIdentifier(
                    recorded: recordedFallbackBundleIdentifier,
                    quiperBundleIdentifier: familyRootBundleIdentifier,
                    resolvable: resolvable
                )
            )
        }
        // A file or foreign scheme reached the helper (a document-type open).
        // Never bounce it into the Quiper family; anything else is the
        // system's to route.
        if let opener = defaultOpenerBundleIdentifier,
           DefaultBrowserRouting.isQuiperBundleIdentifier(opener, quiperBundleIdentifier: familyRootBundleIdentifier) {
            return .openInFallbackBrowser(
                link: link,
                bundleIdentifier: DefaultBrowserRouting.fallbackBundleIdentifier(
                    recorded: recordedFallbackBundleIdentifier,
                    quiperBundleIdentifier: familyRootBundleIdentifier,
                    resolvable: resolvable
                )
            )
        }
        return .passToSystemDefault(link: link)
    }

    /// The nested helper bundle inside the host app: the app URL the main
    /// app opens to keep the helper resident, and the app
    /// `setDefaultApplication` points web links at.
    static func helperBundleURL(hostBundleURL: URL) -> URL {
        hostBundleURL
            .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
            .appendingPathComponent(helperAppName)
    }

    /// The host app's bundle identifier, derived from the helper's own
    /// location at `<Host>.app/Contents/Library/LoginItems/<Helper>.app`;
    /// nil when the helper runs outside a host. The settings folder is named
    /// after the host's bundle identifier, so the helper must never derive
    /// it from its own.
    static func hostBundleIdentifier(helperBundleURL: URL) -> String? {
        let loginItemsDirectory = helperBundleURL.deletingLastPathComponent()
        let libraryDirectory = loginItemsDirectory.deletingLastPathComponent()
        let contentsDirectory = libraryDirectory.deletingLastPathComponent()
        let hostBundleURL = contentsDirectory.deletingLastPathComponent()
        guard loginItemsDirectory.lastPathComponent == "LoginItems",
              libraryDirectory.lastPathComponent == "Library",
              contentsDirectory.lastPathComponent == "Contents",
              hostBundleURL.pathExtension == "app" else {
            return nil
        }
        return Bundle(url: hostBundleURL)?.bundleIdentifier
    }

    /// The settings file of a host app: the same location the host's own
    /// persistence gate reads, named after the host's bundle identifier.
    static func settingsFileURL(hostBundleIdentifier: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(hostBundleIdentifier, isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
