import Foundation
import Testing
import WebKit
@testable import Quiper

/// A valid WKContentRuleList payload with a single network rule, small
/// enough to compile instantly in toggle tests.
private let tinyRuleJSON = """
[{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]
"""

/// Stand-ins for the bundled AdGuard userscripts.
private let tinyExtraScript = "/* fake extra script */"
private let tinyYouTubeScript = "/* fake youtube script */"

@Suite(.serialized)
@MainActor
struct ContentBlockerTests {
    private func makeManager(isEnabled: Bool = true) -> ContentBlockerManager {
        ContentBlockerManager(
            isEnabled: isEnabled,
            ruleJSONProvider: { _ in tinyRuleJSON },
            extraScriptProvider: { tinyExtraScript },
            youtubeScriptProvider: { tinyYouTubeScript }
        )
    }

    // MARK: - Bundled artifacts

    @Test func bundledRuleListsArePresentAndStructurallyValid() throws {
        for source in ContentBlockerManager.sources {
            let json = try #require(
                ContentBlockerManager.bundledRuleJSON(named: source.resourceName),
                "\(source.resourceName).json is missing from the app bundle"
            )
            let rules = try #require(
                try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]],
                "\(source.resourceName).json is not a JSON array of rule objects"
            )
            #expect(!rules.isEmpty, "\(source.resourceName).json contains no rules")
            let malformedCount = rules.reduce(into: 0) { count, rule in
                if rule["trigger"] == nil || rule["action"] == nil { count += 1 }
            }
            #expect(
                malformedCount == 0,
                "\(source.resourceName).json contains \(malformedCount) rules without a trigger or action"
            )
        }
    }

    @Test func bundledRuleListsCompileWithWebKit() async {
        let manager = ContentBlockerManager(
            extraScriptProvider: { tinyExtraScript },
            youtubeScriptProvider: { tinyYouTubeScript }
        )
        let controller = WKUserContentController()
        manager.register(controller)
        let compiled = await manager.compileRuleLists()
        #expect(compiled == ContentBlockerManager.sources.count)
        #expect(manager.isInstalled(on: controller))
    }

    @Test func unchangedContentReusesTheCompiledDiskCache() async throws {
        // Start from a known state: the default store and the fingerprint
        // are shared across runs, so clear both for the tiny test content.
        let store = try #require(WKContentRuleListStore.default())
        for source in ContentBlockerManager.sources {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.removeContentRuleList(forIdentifier: source.identifier) { _ in
                    continuation.resume()
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: ContentBlockerManager.ruleListFingerprintKey)

        let manager = makeManager()
        let first = await manager.compileRuleLists()
        #expect(first == ContentBlockerManager.sources.count)
        #expect(manager.ruleListCacheHits == 0)

        let second = await manager.compileRuleLists()
        #expect(second == ContentBlockerManager.sources.count)
        #expect(manager.ruleListCacheHits == ContentBlockerManager.sources.count)
    }

    @Test func bundledExtraScriptIsPresentAndGated() throws {
        let raw = try #require(
            ContentBlockerManager.bundledExtraScriptSource(),
            "adguard-extra.user.js is missing from the app bundle"
        )
        #expect(raw.contains("@name AdGuard Extra"))

        let gated = ContentBlockerManager.makeExtraUserScript(rawSource: raw)
        #expect(gated.hasPrefix("(function () {"))
        #expect(gated.hasSuffix("})();"))
        // The script only runs while the flag handler is present (blocking on).
        #expect(gated.contains("handlers.\(ContentBlockerManager.scriptGateHandlerName)"))
        // Upstream runs non-strict under userscript managers; so do we.
        #expect(!gated.contains("\"use strict\""))
        // Every upstream @exclude directive is replicated for the runtime
        // gate — none missing, none invented. (Upstream formats vary: some
        // patterns carry a scheme, the YouTube embed one does not.)
        let upstreamExcludes = raw
            .split(separator: "\n")
            .compactMap { line -> String? in
                line.hasPrefix("// @exclude ") ? String(line.dropFirst("// @exclude ".count)) : nil
            }
        #expect(!upstreamExcludes.isEmpty)
        #expect(Set(upstreamExcludes) == Set(ContentBlockerManager.extraScriptExcludes))
        // No sandbox shims: the raw guards its own globals and never calls
        // GM_ APIs, so page-world injection needs no aliases.
        #expect(!gated.contains("var unsafeWindow = window;"))
        #expect(!gated.contains("var GM_xmlhttpRequest"))
        // The gate installs at registration; the prelude never polls for it.
        #expect(!gated.contains("gateScan"))
        // The bundled userscript is carried verbatim inside the wrapper.
        #expect(gated.contains(raw))
    }

    @Test func bundledYouTubeScriptIsPresentAndGated() throws {
        let raw = try #require(
            ContentBlockerManager.bundledYouTubeScriptSource(),
            "block-youtube-ads.user.js is missing from the app bundle"
        )
        #expect(raw.contains("runBlockYoutube"))
        #expect(raw.contains("jsonOverride"))

        let gated = ContentBlockerManager.makeYouTubeUserScript(rawSource: raw)
        #expect(gated.hasPrefix("(function () {"))
        #expect(gated.hasSuffix("})();"))
        // Gated on the flag handler (blocking on).
        #expect(gated.contains("handlers.\(ContentBlockerManager.scriptGateHandlerName)"))
        // Deferred until the parser creates <head>, which WebKit has not
        // parsed yet at document start.
        #expect(gated.contains("new MutationObserver(runPayload)"))
        #expect(gated.contains("if (document.head)"))
        // Trusted Types adapter for YouTube's require-trusted-types-for CSP.
        #expect(gated.contains("trustedTypes.createPolicy(\"quiper-content-blocking\""))
        #expect(gated.contains("Element.prototype"))
        // The script's innerHTML dance is routed through eval during its run
        // window (YouTube's script-src allows unsafe-eval).
        #expect(gated.contains("(0, eval)(code)"))
        // The adapter installs only after the host check decides this is one
        // of the script's YouTube hosts, and before the bundled script runs.
        let hostCheck = try #require(gated.range(of: "var initialHost = location.hostname"))
        let policyInstall = try #require(
            gated.range(of: "trustedTypes.createPolicy(\"quiper-content-blocking\"")
        )
        let rawStart = try #require(gated.range(of: "runBlockYoutube"))
        #expect(hostCheck.lowerBound < policyInstall.lowerBound)
        #expect(policyInstall.lowerBound < rawStart.lowerBound)
        // The prelude additionally strips ad metadata from the page's initial
        // inline player response assignment, which the bundled script's
        // JSON.parse interception misses.
        #expect(gated.contains("Object.defineProperty(window, \"ytInitialPlayerResponse\""))
        #expect(gated.contains("Array.isArray(obj.adPlacements)"))
        #expect(gated.contains("Array.isArray(obj.playerAds)"))
        // The layer posts an activation heartbeat to the log on YouTube hosts
        // so liveness is verifiable in Console.app.
        #expect(gated.contains("youtube-ads: active"))
        // The gate installs at registration; the prelude never polls for it.
        #expect(!gated.contains("gateScan"))
        // The bundled userscript is carried verbatim inside the wrapper.
        #expect(gated.contains(raw))
    }

    // MARK: - Enable/disable behaviour

    @Test func registrationInstallsRuleListsWhenEnabled() async {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        #expect(manager.isRegistered(controller))
        _ = await manager.compileRuleLists()
        #expect(manager.isInstalled(on: controller))
    }

    @Test func disabledManagerRegistersButInstallsNothingUntilEnabled() async {
        let manager = makeManager(isEnabled: false)
        let controller = WKUserContentController()
        manager.register(controller)
        #expect(manager.isRegistered(controller))
        #expect(controller.userScripts.isEmpty)
        _ = await manager.compileRuleLists()
        #expect(!manager.isInstalled(on: controller))
        #expect(controller.userScripts.isEmpty)
        manager.setEnabled(true)
        #expect(manager.isInstalled(on: controller))
        #expect(controller.userScripts.count == 2)
    }

    @Test func togglingOffUninstallsRuleLists() async {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        _ = await manager.compileRuleLists()
        #expect(manager.isInstalled(on: controller))
        manager.setEnabled(false)
        #expect(!manager.isInstalled(on: controller))
        #expect(manager.isRegistered(controller))
    }

    // MARK: - Injected script lifecycle

    @Test func registrationAddsInjectedScriptsExactlyOnceWhenEnabled() {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        #expect(manager.areInjectedScriptsInstalled(on: controller))
        #expect(controller.userScripts.count == 2)
    }

    @Test func togglingDoesNotDuplicateTheInjectedScripts() async {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        _ = await manager.compileRuleLists()
        manager.setEnabled(false)
        manager.setEnabled(true)
        // The scripts survive the off cycle (WebKit cannot remove individual
        // scripts; the flag handler is what switches them off) and must not
        // be added a second time when re-enabled.
        #expect(controller.userScripts.count == 2)
        #expect(manager.isInstalled(on: controller))
    }

    @Test func scriptWipeIsRestoredByReinstall() {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        // Simulates the engine-script refresh paths that wipe all scripts.
        controller.removeAllUserScripts()
        #expect(controller.userScripts.isEmpty)
        manager.reinstallInjectedScripts(on: controller)
        #expect(controller.userScripts.count == 2)
        #expect(manager.areInjectedScriptsInstalled(on: controller))
    }

    @Test func reinstallIgnoresUnregisteredControllers() {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.reinstallInjectedScripts(on: controller)
        #expect(controller.userScripts.isEmpty)
    }

    @Test func registrationInstallsTheGateBeforeRuleListsCompile() {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        // The gate must exist before the controller's first navigation —
        // compilation can still be running seconds into a launch — or a
        // document loaded in that window silently skips its blocking layer
        // for its whole life.
        #expect(manager.isGateHandlerInstalled(on: controller))
        #expect(manager.areInjectedScriptsInstalled(on: controller))
        #expect(!manager.isInstalled(on: controller))
    }

    @Test func togglingRemovesAndRestoresTheGateHandler() async {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        _ = await manager.compileRuleLists()
        #expect(manager.isGateHandlerInstalled(on: controller))
        manager.setEnabled(false)
        #expect(!manager.isGateHandlerInstalled(on: controller))
        manager.setEnabled(true)
        #expect(manager.isGateHandlerInstalled(on: controller))
        #expect(manager.isInstalled(on: controller))
        #expect(controller.userScripts.count == 2)
    }

    @Test func scriptWipeWhileDisabledIsStillRestored() {
        let manager = makeManager()
        let controller = WKUserContentController()
        manager.register(controller)
        manager.setEnabled(false)
        // The engine-script refresh can wipe while blocking is off. The
        // restore must key off what was shipped, not the current toggle, or
        // the stale flag would block the next enable from ever re-adding
        // the scripts — a controller left with the gate but no scripts.
        controller.removeAllUserScripts()
        manager.reinstallInjectedScripts(on: controller)
        #expect(controller.userScripts.count == 2)
        #expect(manager.areInjectedScriptsInstalled(on: controller))
        manager.setEnabled(true)
        #expect(controller.userScripts.count == 2)
        #expect(manager.isGateHandlerInstalled(on: controller))
    }

    // MARK: - Settings persistence

    @Test func blockAdsAndTrackersSurvivesCodecRoundTrip() throws {
        let payload = PersistedSettings(services: [], blockAdsAndTrackers: false)
        let data = try SettingsCodec.makeEncoder().encode(payload)
        let decoded = try SettingsCodec.makeDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.blockAdsAndTrackers == false)
    }

    @Test func absentBlockAdsAndTrackersKeyDecodesAsUnset() throws {
        let decoded = try SettingsCodec.makeDecoder().decode(
            PersistedSettings.self,
            from: Data("{}".utf8)
        )
        // Unset means consumers apply their default (blocking on).
        #expect(decoded.blockAdsAndTrackers == nil)
    }
}
