import XCTest
@testable import Quiper

final class DefaultBrowserRoutingTests: XCTestCase {
    // MARK: - Fallback resolution

    func testFallbackUsesRecordedBrowserWhenItResolves() {
        XCTAssertEqual(
            DefaultBrowserRouting.fallbackBundleIdentifier(
                recorded: "org.mozilla.firefox",
                quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
            ) {
                $0 == "org.mozilla.firefox"
            },
            "org.mozilla.firefox"
        )
    }

    func testFallbackUsesSafariWhenNothingIsRecorded() {
        XCTAssertEqual(
            DefaultBrowserRouting.fallbackBundleIdentifier(
                recorded: nil,
                quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
            ) { _ in true },
            DefaultBrowserRouting.safariBundleIdentifier
        )
    }

    func testFallbackUsesSafariWhenRecordedBrowserIsGone() {
        XCTAssertEqual(
            DefaultBrowserRouting.fallbackBundleIdentifier(
                recorded: "com.example.uninstalled",
                quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
            ) { _ in false },
            DefaultBrowserRouting.safariBundleIdentifier
        )
    }

    func testFallbackNeverReturnsAFamilyBrowser() {
        // A recorded Quiper build would bounce the link straight back into
        // the loop the fallback exists to escape.
        for recorded in ["app.sassanh.quiper.Quiper", "app.sassanh.quiper.Quiper.LinkHelper"] {
            XCTAssertEqual(
                DefaultBrowserRouting.fallbackBundleIdentifier(
                    recorded: recorded,
                    quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
                ) { _ in true },
                DefaultBrowserRouting.safariBundleIdentifier
            )
        }
    }

    // MARK: - Default-opener detection

    func testEveryQuiperBuildIsRecognizedAsQuiper() {
        let production = "app.sassanh.quiper.Quiper"
        XCTAssertTrue(
            DefaultBrowserRouting.isQuiperBundleIdentifier(production, quiperBundleIdentifier: production)
        )
        XCTAssertTrue(
            DefaultBrowserRouting.isQuiperBundleIdentifier(
                "app.sassanh.quiper.QuiperDev",
                quiperBundleIdentifier: production
            )
        )
        XCTAssertTrue(
            DefaultBrowserRouting.isQuiperBundleIdentifier(
                production,
                quiperBundleIdentifier: "app.sassanh.quiper.QuiperDev"
            )
        )
        XCTAssertFalse(
            DefaultBrowserRouting.isQuiperBundleIdentifier(
                "com.example.browser",
                quiperBundleIdentifier: production
            )
        )
        // The resident link helper counts as Quiper: making it the system
        // default must read as Quiper being the default.
        XCTAssertTrue(
            DefaultBrowserRouting.isQuiperBundleIdentifier(
                "app.sassanh.quiper.Quiper.LinkHelper",
                quiperBundleIdentifier: production
            )
        )
        XCTAssertTrue(
            DefaultBrowserRouting.isQuiperBundleIdentifier(
                "app.sassanh.quiper.QuiperDev.LinkHelper",
                quiperBundleIdentifier: "app.sassanh.quiper.QuiperDev"
            )
        )
    }

    func testUnknownOrMissingApplicationURLIsNotQuiperOpener() {
        XCTAssertFalse(
            DefaultBrowserRouting.isQuiperDefaultOpener(
                applicationURL: URL(fileURLWithPath: "/Applications/Definitely Not Installed.app"),
                quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
            )
        )
        XCTAssertFalse(
            DefaultBrowserRouting.isQuiperDefaultOpener(
                applicationURL: nil,
                quiperBundleIdentifier: "app.sassanh.quiper.Quiper"
            )
        )
    }

    // MARK: - Persistence

    @MainActor
    func testFallbackBundleIdentifierRoundTripsThroughPersistedSettings() throws {
        Settings.shared.defaultBrowserFallbackBundleIdentifier = "org.mozilla.firefox"
        defer { Settings.shared.defaultBrowserFallbackBundleIdentifier = nil }

        let data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)

        XCTAssertEqual(decoded.defaultBrowserFallbackBundleIdentifier, "org.mozilla.firefox")
    }

    @MainActor
    func testPersistedSettingsWithoutFallbackKeyDecodesToNil() throws {
        let json = #"{"services": []}"#
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: json.data(using: .utf8)!)
        XCTAssertNil(decoded.defaultBrowserFallbackBundleIdentifier)
    }
}
