import XCTest
@testable import Quiper

final class LinkHelperRoutingTests: XCTestCase {
    private let hostIdentifier = "app.sassanh.quiper.Quiper"

    private func claiming(_ domains: String...) -> [Service] {
        var engine = Service(name: "Engine", url: "https://engine.example.com", focus_selector: "")
        engine.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: domains)
        return [engine]
    }

    private func decision(
        for link: String,
        services: [Service] = [],
        unlocked: Set<UUID> = [],
        recorded: String? = nil,
        resolvable: @escaping (String) -> Bool = { _ in true },
        defaultOpener: String? = nil
    ) -> LinkHelperDecision {
        LinkHelperRouting.decision(
            for: URL(string: link)!,
            services: services,
            isEngineUnlocked: { unlocked.contains($0) },
            familyRootBundleIdentifier: hostIdentifier,
            recordedFallbackBundleIdentifier: recorded,
            resolvable: resolvable,
            defaultOpenerBundleIdentifier: defaultOpener
        )
    }

    // MARK: - quiper:// route

    func testRouteRoundTripsALink() throws {
        let link = try XCTUnwrap(URL(string: "https://chatgpt.com/c/abc?q=a%20b&next=1"))
        let route = try XCTUnwrap(QuiperLinkRoute.wrapping(link))
        XCTAssertEqual(route.scheme, "quiper")
        XCTAssertEqual(route.host, "route")
        XCTAssertEqual(QuiperLinkRoute.link(in: route), link)
    }

    func testRouteRejectsMalformedURLs() {
        XCTAssertNil(QuiperLinkRoute.link(in: URL(string: "https://chatgpt.com/")!))
        XCTAssertNil(QuiperLinkRoute.link(in: URL(string: "quiper://elsewhere?url=https://example.com")!))
        XCTAssertNil(QuiperLinkRoute.link(in: URL(string: "quiper://route")!))
        XCTAssertNil(QuiperLinkRoute.link(in: URL(string: "quiper://route?other=https://example.com")!))
    }

    // MARK: - The decision matrix

    func testClaimedLinkRoutesToQuiper() {
        let link = "https://chatgpt.com/c/abc"
        XCTAssertEqual(
            decision(for: link, services: claiming("chatgpt.com")),
            .routeToQuiper(link: URL(string: link)!)
        )
    }

    func testUnclaimedLinkOpensInRecordedFallback() {
        let link = "https://example.com/docs"
        XCTAssertEqual(
            decision(for: link, recorded: "org.mozilla.firefox"),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: "org.mozilla.firefox")
        )
    }

    func testUnclaimedLinkUsesSafariWhenRecordedFallbackIsGone() {
        let link = "https://example.com/docs"
        XCTAssertEqual(
            decision(
                for: link,
                recorded: "com.example.uninstalled",
                resolvable: { _ in false }
            ),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: DefaultBrowserRouting.safariBundleIdentifier)
        )
    }

    func testUnclaimedLinkNeverFallsBackIntoQuiper() {
        // The helper is the system default for web links; a fallback that
        // named Quiper would hand the link straight back.
        let link = "https://example.com/docs"
        XCTAssertEqual(
            decision(for: link, recorded: hostIdentifier),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: DefaultBrowserRouting.safariBundleIdentifier)
        )
    }

    func testUnclaimedLinkUsesExplicitFallbackEvenWhileQuiperIsDefault() {
        // The default opener for this link is the helper itself: opening
        // "normally" would deliver the link back to the helper forever.
        let link = "https://example.com/docs"
        XCTAssertEqual(
            decision(for: link, recorded: "org.mozilla.firefox", defaultOpener: hostIdentifier + ".LinkHelper"),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: "org.mozilla.firefox")
        )
    }

    func testNonWebLinkPassesToSystemDefault() {
        let link = "file:///Users/shared/notes.html"
        XCTAssertEqual(
            decision(for: link, defaultOpener: "com.apple.Safari"),
            .passToSystemDefault(link: URL(string: link)!)
        )
    }

    func testNonWebLinkWithFamilyOpenerOpensInFallback() {
        // A document the helper received from a Quiper-family opener must
        // not be handed back into the family.
        let link = "file:///Users/shared/notes.html"
        XCTAssertEqual(
            decision(for: link, recorded: "org.mozilla.firefox", defaultOpener: hostIdentifier + ".LinkHelper"),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: "org.mozilla.firefox")
        )
    }

    // MARK: - Secure engines

    private func secureClaiming(_ domains: String...) -> [Service] {
        var engine = Service(name: "Secure", url: "https://secure.example.com", focus_selector: "")
        engine.isEncrypted = true
        engine.hasMigratedMetadata = true
        engine.externalLinkHandler = ExternalLinkHandler(isEnabled: true, domains: domains)
        return [engine]
    }

    func testLockedSecureEngineLinkOpensInTheFallback() {
        // The helper never unlocks an engine: with the volume locked the
        // records are unreachable, so the link falls through to the
        // fallback browser as if nothing claimed it.
        let link = "https://chatgpt.com/c/abc"
        XCTAssertEqual(
            decision(for: link, services: secureClaiming("chatgpt.com"), recorded: "org.mozilla.firefox"),
            .openInFallbackBrowser(link: URL(string: link)!, bundleIdentifier: "org.mozilla.firefox")
        )
    }

    func testUnlockedSecureEngineLinkRoutesToQuiper() {
        let services = secureClaiming("chatgpt.com")
        let link = "https://chatgpt.com/c/abc"
        XCTAssertEqual(
            decision(for: link, services: services, unlocked: [services[0].id]),
            .routeToQuiper(link: URL(string: link)!)
        )
    }

    // MARK: - Host and settings locations

    /// A host app bundle on disk, with just the identifier it is known by.
    private func makeHostBundle(identifier: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hostBundle = root.appendingPathComponent("Quiper.app", isDirectory: true)
        let contentsDirectory = hostBundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDirectory, withIntermediateDirectories: true)
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(identifier)</string>
        </dict>
        </plist>
        """
        try infoPlist.write(
            to: contentsDirectory.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return hostBundle
    }

    func testHostBundleIdentifierComesFromTheNestedLocation() throws {
        let hostBundle = try makeHostBundle(identifier: hostIdentifier)
        let helperBundle = hostBundle.appendingPathComponent(
            "Contents/Library/LoginItems/\(LinkHelperRouting.helperAppName(hostBundleIdentifier: hostIdentifier))"
        )
        XCTAssertEqual(
            LinkHelperRouting.hostBundleIdentifier(helperBundleURL: helperBundle),
            hostIdentifier
        )
    }

    func testHostBundleIdentifierIsNilOutsideAHost() {
        XCTAssertNil(
            LinkHelperRouting.hostBundleIdentifier(
                helperBundleURL: URL(fileURLWithPath: "/usr/local/bin/Quiper.app")
            )
        )
    }

    func testSettingsFileLivesInTheHostFolder() {
        let settingsFile = LinkHelperRouting.settingsFileURL(hostBundleIdentifier: hostIdentifier)
        XCTAssertEqual(settingsFile.lastPathComponent, "settings.json")
        XCTAssertEqual(settingsFile.deletingLastPathComponent().lastPathComponent, hostIdentifier)
    }

    // MARK: - The helper's folder name

    func testProductionBuildsNestTheHelperAsQuiper() {
        // The folder name is the label macOS shows for the handler in System
        // Settings' Default web browser menu: a production install must read
        // as plain Quiper, the way every other browser does.
        XCTAssertEqual(
            LinkHelperRouting.helperAppName(hostBundleIdentifier: hostIdentifier),
            "Quiper.app"
        )
        XCTAssertEqual(LinkHelperRouting.helperAppName(hostBundleIdentifier: nil), "Quiper.app")
    }

    func testDevelopmentBuildsNestTheHelperAsQuiperDev() {
        // A development build must not join the production entry: its helper
        // nests as QuiperDev.app and reads as a handler of its own.
        XCTAssertEqual(
            LinkHelperRouting.helperAppName(hostBundleIdentifier: "app.sassanh.quiper.QuiperDev"),
            "QuiperDev.app"
        )
    }

    func testHelperBundleNestsUnderTheHostLoginItems() throws {
        let productionHost = try makeHostBundle(identifier: hostIdentifier)
        let developmentHost = try makeHostBundle(identifier: "app.sassanh.quiper.QuiperDev")

        let productionHelper = LinkHelperRouting.helperBundleURL(hostBundleURL: productionHost)
        XCTAssertEqual(productionHelper.deletingLastPathComponent().lastPathComponent, "LoginItems")
        XCTAssertEqual(productionHelper.lastPathComponent, "Quiper.app")
        XCTAssertEqual(
            LinkHelperRouting.helperBundleURL(hostBundleURL: developmentHost).lastPathComponent,
            "QuiperDev.app"
        )
    }
}
