import AppKit
import WebKit

extension MainWindowController {

    // MARK: - Tab close gate
    //
    // Every path that destroys live tabs funnels through `requestCloseTabs`:
    // explicit closes, middle-click closes, close-all, ephemeral replacement,
    // and every encrypted-engine lock (manual, all, switch-away, inactivity).
    // Settings-driven destroys (engine delete, erase-all, secure-storage
    // migration, web data reset) probe through
    // `unloadInfosNeedingConfirmation(for:)` before mutating settings, and
    // app quit probes through `openTabsNeedingUnloadConfirmationSync`.
    // The teardown methods themselves are commit-only.

    /// Confirms with the user when any of `tabs` holds unsaved page state,
    /// then destroys exactly those tabs. Returns false when the user stays,
    /// in which case nothing is destroyed. Tabs without a live webview are
    /// ignored: there is no page state left to protect.
    func requestCloseTabs(_ tabs: [TabIdentifier], reason: TabCloseReason) async -> Bool {
        let liveTabs = tabs.filter { webViewManager.webView(for: $0) != nil }
        guard !liveTabs.isEmpty else { return true }
        let blocking = await webViewManager.tabsRequiringConfirmation(liveTabs)
        guard !blocking.isEmpty else {
            commitClosingTabs(liveTabs)
            return true
        }
        let confirmed = await confirmUnload(tabs: blocking, reason: reason)
        if confirmed {
            commitClosingTabs(liveTabs)
        }
        return confirmed
    }

    /// Single commit implementation behind the gate: history bookkeeping,
    /// observer cleanup, and webview teardown for exactly these tabs.
    /// Callers handle reselection and empty state afterwards.
    func commitClosingTabs(_ tabs: [TabIdentifier]) {
        guard !tabs.isEmpty else { return }
        for tab in tabs {
            tabHistory.removeAll { $0 == tab }
            if lastActiveTab == tab {
                lastActiveTab = nil
            }
            tabPreviews.removeValue(forKey: tab)
            removeTabWithoutSaving(for: tab.serviceID, sessionIndex: tab.sessionIndex)
        }
        saveTabsState()
    }

    /// Presents the shared unsaved-changes dialog for already-probed tabs.
    /// Auto-confirms in tests so suites stay non-interactive.
    func confirmUnload(tabs: [TabUnloadInfo], reason: TabCloseReason) async -> Bool {
        guard !tabs.isEmpty else { return true }
        guard !AppController.isRunningTests else { return true }
        guard let window else { return true }
        return await TabCloseDialogQueue.shared.run {
            await withCheckedContinuation { continuation in
                let alert = NSAlert()
                alert.messageText = reason.alertTitle(tabCount: tabs.count)
                alert.informativeText = TabCloseGate.informativeText(for: tabs)
                alert.addButton(withTitle: reason.confirmButtonTitle)
                alert.addButton(withTitle: "Cancel")
                alert.buttons[1].keyEquivalent = "\u{1b}"
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }
    }

    /// Synchronous modal variant for app quit only: `applicationShouldTerminate`
    /// cannot use Swift concurrency, so quit reuses the same script and copy
    /// through `openTabsNeedingUnloadConfirmationSync` plus this dialog.
    /// Returns true when there is nothing to protect or the user confirms.
    func confirmUnloadSync(tabs: [TabUnloadInfo], reason: TabCloseReason) -> Bool {
        guard !tabs.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = reason.alertTitle(tabCount: tabs.count)
        alert.informativeText = TabCloseGate.informativeText(for: tabs)
        alert.addButton(withTitle: reason.confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Probe-only query for callers that confirm through their own dialog
    /// (Settings destructive actions). Returns infos for tabs whose pages
    /// ask to confirm; empty means nothing to warn about.
    func unloadInfosNeedingConfirmation(for serviceIDs: [UUID]) async -> [TabUnloadInfo] {
        let idSet = Set(serviceIDs)
        let tabs = webViewManager.allOpenTabs().filter { idSet.contains($0.serviceID) }
        return await webViewManager.tabsRequiringConfirmation(tabs)
    }

    /// Synchronous probe for `applicationShouldTerminate`, which cannot use
    /// Swift concurrency. Fires the shared script with completion handlers
    /// and pumps the main runloop until every tab answers or the deadline
    /// passes. Unanswered tabs count as blocking: quitting must ask rather
    /// than silently drop a hung page.
    func openTabsNeedingUnloadConfirmationSync() -> [TabUnloadInfo] {
        let tabs = webViewManager.allOpenTabs()
        guard !tabs.isEmpty else { return [] }
        final class Collector {
            var answers: [TabIdentifier: Bool] = [:]
        }
        let collector = Collector()
        var probed: [TabIdentifier] = []
        for tab in tabs {
            guard let webView = webViewManager.webView(for: tab) else { continue }
            probed.append(tab)
            webView.evaluateJavaScript(TabCloseGate.beforeUnloadProbeScript) { result, _ in
                collector.answers[tab] = result as? Bool ?? false
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while probed.contains(where: { collector.answers[$0] == nil }) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let blockingTabs = probed.filter { collector.answers[$0] ?? true }
        return blockingTabs.compactMap { webViewManager.unloadInfo(for: $0) }
    }
}
