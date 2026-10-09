import AppKit

/// The resident link router: the app macOS opens web links with when Quiper
/// is the system default browser. It never appears in the Dock or the app
/// switcher, never opens a window, and never exits — every link it receives
/// is decided here and handed on: claimed links to the main app through a
/// `quiper://` route, everything else straight to the fallback browser.
final class LinkHelperAppDelegate: NSObject, NSApplicationDelegate {
    /// The host app's bundle identifier — the root of the Quiper family and
    /// the name of the settings folder. Derived from the helper's location
    /// inside the host; nil when the helper runs outside one.
    private let hostBundleIdentifier = LinkHelperRouting.hostBundleIdentifier(
        helperBundleURL: Bundle.main.bundleURL
    )

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard let hostBundleIdentifier else {
            NSLog("[QuiperLinkHelper] No host app for this helper; not opening %@", url.absoluteString)
            return
        }
        let settings = readSettings(hostBundleIdentifier: hostBundleIdentifier)
        let claimView = securedClaimView(of: settings.services, hostBundleIdentifier: hostBundleIdentifier)
        let decision = LinkHelperRouting.decision(
            for: url,
            services: claimView.services,
            isEngineUnlocked: { claimView.unlockedSecureEngineIDs.contains($0) },
            familyRootBundleIdentifier: hostBundleIdentifier,
            recordedFallbackBundleIdentifier: settings.defaultBrowserFallbackBundleIdentifier,
            resolvable: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            defaultOpenerBundleIdentifier: NSWorkspace.shared.urlForApplication(toOpen: url)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
        )
        switch decision {
        case .routeToQuiper(let link):
            guard let route = QuiperLinkRoute.wrapping(link), NSWorkspace.shared.open(route) else {
                NSLog("[QuiperLinkHelper] Routed link could not open in Quiper: %@", link.absoluteString)
                return
            }
        case .openInFallbackBrowser(let link, let bundleIdentifier):
            openExplicitly(link, withBundleIdentifier: bundleIdentifier)
        case .passToSystemDefault(let link):
            NSWorkspace.shared.open(link)
        }
    }

    /// The persisted settings snapshot; an unreadable file degrades every
    /// link to unclaimed rather than blocking it.
    private func readSettings(hostBundleIdentifier: String) -> PersistedSettings {
        let file = LinkHelperRouting.settingsFileURL(hostBundleIdentifier: hostBundleIdentifier)
        guard let data = try? Data(contentsOf: file),
              let snapshot = SettingsCodec.decodePersistedSettings(from: data) else {
            NSLog("[QuiperLinkHelper] Settings unreadable at %@; links open in the fallback browser", file.path)
            return PersistedSettings(
                services: [],
                hotkey: nil,
                customActions: nil,
                updatePreferences: nil,
                serviceZoomLevels: nil
            )
        }
        return snapshot
    }

    /// The services as the router may see them: a secure engine's routing
    /// records live inside its encrypted volume, so the helper sees them
    /// only while the volume is mounted — which is the engine's unlocked
    /// state, and exactly what it may claim for. A locked engine's view
    /// never leaves the plaintext settings, which carry no routing records
    /// for a migrated engine.
    private func securedClaimView(
        of services: [Service],
        hostBundleIdentifier: String
    ) -> (services: [Service], unlockedSecureEngineIDs: Set<UUID>) {
        var services = services
        var unlockedSecureEngineIDs = Set<UUID>()
        for index in services.indices where services[index].isEncrypted {
            let serviceID = services[index].id
            let mountPoint = SecureEngineStorage.mountPointURL(
                bundleIdentifier: hostBundleIdentifier,
                serviceID: serviceID
            )
            guard SecureEngineStorage.isMounted(at: mountPoint) else { continue }
            unlockedSecureEngineIDs.insert(serviceID)
            guard services[index].hasMigratedMetadata,
                  let metadata = readSecuredMetadata(at: mountPoint) else { continue }
            metadata.apply(to: &services[index])
        }
        return (services, unlockedSecureEngineIDs)
    }

    /// The secured metadata inside a mounted volume; an unreadable file
    /// leaves the plaintext view untouched.
    private func readSecuredMetadata(at mountPoint: URL) -> SecuredEngineMetadata? {
        let file = mountPoint.appendingPathComponent(SecureEngineStorage.metadataFileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SecuredEngineMetadata.self, from: data)
    }

    /// Opens the link in one named app. The explicit target keeps the open
    /// from routing back through the default — the helper — in a loop.
    private func openExplicitly(_ link: URL, withBundleIdentifier bundleIdentifier: String) {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("[QuiperLinkHelper] No application for %@; link not opened: %@", bundleIdentifier, link.absoluteString)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [link],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                )
            } catch {
                NSLog("[QuiperLinkHelper] Link could not open in %@: %@", bundleIdentifier, error.localizedDescription)
            }
        }
    }
}

@main
struct LinkHelperMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = LinkHelperAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
