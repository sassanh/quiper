import AppKit
import WebKit

// MARK: - TabCloseGate
//
// Single source of truth for the web `beforeunload` standard: a tab whose
// page reports unsaved state must not be destroyed without asking the user,
// no matter which code path initiates the close.
//
// The gate has three parts, each with exactly one implementation:
//   1. Detection — `TabCloseGate.beforeUnloadProbeScript`, evaluated in the
//      page. Destroying a WKWebView never fires `beforeunload` by itself, so
//      the gate fires a synthetic cancelable event and honors both the
//      `preventDefault` signal and a legacy `returnValue` string.
//   2. Decision copy — `TabCloseReason` titles/buttons plus
//      `informativeText(for:)`. Every confirmation dialog in the app,
//      AppKit or SwiftUI, derives its wording from here.
//   3. Presentation — `MainWindowController.requestCloseTabs` (async sheet)
//      for in-app closes. App quit cannot use Swift concurrency (see
//      `applicationShouldTerminate`), so it reuses the same script and copy
//      through `openTabsNeedingUnloadConfirmationSync` with a modal dialog.
//
// Destruction itself stays in `WebViewManager` / `MainWindowController`, but
// those are commit-only: every caller must pass this gate first.

/// A tab that the probe flagged as holding unsaved page state.
struct TabUnloadInfo: Hashable, Sendable {
    let serviceID: UUID
    let sessionIndex: Int
    let serviceName: String
    let title: String

    var tab: TabIdentifier {
        TabIdentifier(serviceID: serviceID, sessionIndex: sessionIndex)
    }

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(serviceName) — Session \(sessionIndex + 1)"
        }
        return "\(serviceName) — \(trimmed)"
    }
}

/// Why tabs are about to be destroyed. Drives dialog wording only; the
/// probe result drives whether a dialog appears at all.
enum TabCloseReason: Sendable {
    case closeCurrentSession
    case closeAllSessions(serviceName: String)
    case lockService(serviceName: String)
    case lockAllServices
    case switchService(serviceName: String)
    case autoLock
    case replaceWithEphemeral
    case replaceWithNormal
    case quit

    func alertTitle(tabCount: Int) -> String {
        switch self {
        case .closeCurrentSession:
            return "Leave this session?"
        case .closeAllSessions(let serviceName):
            return "Close all sessions for \(serviceName)?"
        case .lockService(let serviceName):
            return "Lock \(serviceName)?"
        case .lockAllServices:
            return "Lock all engines?"
        case .switchService(let serviceName):
            return "Switch away from \(serviceName)?"
        case .autoLock:
            return "Lock inactive engines?"
        case .replaceWithEphemeral:
            return "Discard this session?"
        case .replaceWithNormal:
            return "Discard this session?"
        case .quit:
            return tabCount == 1 ? "Quit with unsaved changes?" : "Quit with unsaved changes in \(tabCount) sessions?"
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .closeCurrentSession:
            return "Leave"
        case .closeAllSessions:
            return "Close"
        case .lockService, .lockAllServices, .autoLock:
            return "Lock"
        case .switchService:
            return "Switch"
        case .replaceWithEphemeral:
            return "Discard"
        case .replaceWithNormal:
            return "Discard"
        case .quit:
            return "Quit"
        }
    }
}

enum TabCloseGate {
    /// Fires a synthetic cancelable `beforeunload` in the page and reports
    /// whether the page asks to confirm the unload. Matches browser
    /// behavior: `preventDefault()` (or a legacy non-empty `returnValue`)
    /// means "confirm", anything else means "no dialog". A page that assigns
    /// `window.onbeforeunload` is treated as confirming without dispatching,
    /// so legacy string-return handlers are honored even though synthetic
    /// dispatch does not propagate their return value on every engine.
    /// Never throws and never returns true for blank or unloadable pages;
    /// errors mean "nothing to protect".
    static let beforeUnloadProbeScript = """
(function() {
  try {
    if (typeof window.onbeforeunload === 'function') { return true; }
    var event = null;
    try {
      event = new BeforeUnloadEvent('beforeunload', { cancelable: true });
    } catch (creationError) {
      try {
        event = document.createEvent('BeforeUnloadEvent');
        event.initEvent('beforeunload', false, true);
      } catch (fallbackError) {
        return false;
      }
    }
    var dispatchResult = true;
    try {
      dispatchResult = window.dispatchEvent(event);
    } catch (dispatchError) {
      return false;
    }
    if (dispatchResult === false) { return true; }
    try {
      var returnValue = event.returnValue;
      if (typeof returnValue === 'string' && returnValue !== '') { return true; }
    } catch (ignored) {}
    return false;
  } catch (outerError) {
    return false;
  }
})()
"""

    /// How long one probe may take before the tab counts as needing
    /// confirmation. A hung web process must not wedge tab closes forever;
    /// timing out is the conservative direction (ask, don't silently drop).
    static let probeTimeoutNanoseconds: UInt64 = 2_000_000_000

    /// Single copy source for every unsaved-changes dialog.
    static func informativeText(for tabs: [TabUnloadInfo]) -> String {
        var lines = ["Changes you made may not be saved."]
        let listed = tabs.prefix(4)
        if !listed.isEmpty {
            lines.append("")
            lines += listed.map { "• \($0.displayName)" }
            let remaining = tabs.count - listed.count
            if remaining > 0 {
                lines.append("and \(remaining) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One-line warning folded into SwiftUI confirmations that already ask
    /// about a destructive settings change (engine delete, erase-all, web
    /// data reset, secure-storage migration).
    static let settingsWarningSuffix = " Some sessions have unsaved changes."
}

// MARK: - Probe state

/// Matches at most one resume per probe. The JavaScript reply and the
/// timeout race; whichever finishes first wins and the loser finds its entry
/// gone. All access is MainActor-isolated, mirroring the navigation
/// continuation bookkeeping in WebViewManager.
@MainActor
enum UnloadProbeState {
    private static var pending: [UUID: CheckedContinuation<Bool, Never>] = [:]

    static func begin(_ probeID: UUID, _ continuation: CheckedContinuation<Bool, Never>) {
        pending[probeID] = continuation
    }

    static func finish(_ probeID: UUID, with value: Bool) {
        guard let continuation = pending.removeValue(forKey: probeID) else { return }
        continuation.resume(returning: value)
    }
}

extension WKWebView {
    /// Evaluates the shared `beforeunload` probe in the main frame.
    /// Returns false when the page is blank, gone, or reports nothing to
    /// protect; returns true on timeout so a hung page asks instead of
    /// silently dropping state.
    @MainActor
    func requiresUnloadConfirmation() async -> Bool {
        await withCheckedContinuation { continuation in
            let probeID = UUID()
            UnloadProbeState.begin(probeID, continuation)
            self.evaluateJavaScript(TabCloseGate.beforeUnloadProbeScript) { result, _ in
                let needsConfirm = result as? Bool ?? false
                Task {
                    UnloadProbeState.finish(probeID, with: needsConfirm)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: TabCloseGate.probeTimeoutNanoseconds)
                UnloadProbeState.finish(probeID, with: true)
            }
        }
    }
}

// MARK: - WebViewManager queries

extension WebViewManager {
    /// Reads are safe for tabs whose service was already deleted from
    /// settings: the webview maps are keyed by service ID, not by Service.
    func webView(for tab: TabIdentifier) -> WKWebView? {
        webviewsByID[tab.serviceID]?[tab.sessionIndex]
    }

    /// Every live tab, sorted for stable dialog listings.
    func allOpenTabs() -> [TabIdentifier] {
        webviewsByID.flatMap { serviceID, sessions in
            sessions.keys.map { TabIdentifier(serviceID: serviceID, sessionIndex: $0) }
        }
        .sorted {
            if $0.serviceID != $1.serviceID {
                return $0.serviceID.uuidString < $1.serviceID.uuidString
            }
            return $0.sessionIndex < $1.sessionIndex
        }
    }

    func unloadInfo(for tab: TabIdentifier) -> TabUnloadInfo? {
        guard let webView = webView(for: tab) else { return nil }
        let serviceName = service(for: webView)?.name ?? "Engine"
        let title: String
        if let service = service(for: webView) {
            title = sessionTitle(for: service, sessionIndex: tab.sessionIndex) ?? ""
        } else {
            title = ""
        }
        return TabUnloadInfo(
            serviceID: tab.serviceID,
            sessionIndex: tab.sessionIndex,
            serviceName: serviceName,
            title: title
        )
    }

    /// Probes each tab sequentially and returns infos for the ones whose
    /// pages ask to confirm. Tabs without a live webview are skipped: there
    /// is no page state left to protect.
    func tabsRequiringConfirmation(_ tabs: [TabIdentifier]) async -> [TabUnloadInfo] {
        var blocking: [TabUnloadInfo] = []
        for tab in tabs {
            guard let info = unloadInfo(for: tab),
                  let webView = webView(for: tab) else { continue }
            if await webView.requiresUnloadConfirmation() {
                blocking.append(info)
            }
        }
        return blocking
    }
}

// MARK: - Dialog serialization

/// Sheets stack one at a time per window. Concurrent close requests (a
/// middle-click racing an auto-lock, for example) queue here instead of
/// presenting over each other.
@MainActor
final class TabCloseDialogQueue {
    static let shared = TabCloseDialogQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ work: () async -> T) async -> T {
        if isRunning {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        isRunning = true
        defer {
            isRunning = false
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
        return await work()
    }
}
