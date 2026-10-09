import AppKit
import Foundation

// MARK: - External Links

extension MainWindowController {
    /// Opens a link another app handed Quiper into `service`, placing it
    /// according to the engine's external-link configuration. Callers pass
    /// only claimed links, and a secure engine claims only while unlocked,
    /// so by the time a link reaches this method the engine is ready.
    func openExternalLink(_ url: URL, for service: Service) {
        // Planned against the state before the engine switch: activating an
        // engine may create its active slot with the engine's own page, and
        // that page was never asked for — the link takes over such a slot
        // instead of counting it as busy.
        let handler = service.externalLinkHandler
        let plan = ExternalLinkSessionPlacement.plan(
            placement: handler.placement,
            fixedSessionIndex: handler.fixedSessionIndex,
            visibleSlots: service.visibleSessionIndices,
            occupiedSlots: occupiedSessionSlots(for: service),
            visitOrder: externalLinkVisitOrder(for: service)
        )

        guard selectService(withID: service.id) else {
            NSLog("[Quiper] External link could not open: engine %@ unavailable", service.name)
            return
        }

        switch plan {
        case .openInSession(let index):
            openExternalLink(url, in: service, sessionIndex: index)
        case .replaceBusySession(let defaultIndex):
            guard let index = promptForSessionReplacement(defaultIndex: defaultIndex, service: service) else {
                NSLog("[Quiper] External link dismissed for engine %@", service.name)
                return
            }
            openExternalLink(url, in: service, sessionIndex: index)
        case .noSessionAvailable:
            presentNoOpenSessionAlert(for: service)
        }
    }

    /// Switches to the planned slot and loads the link there. Explicit-load
    /// semantics: the link bypasses routing rules, like an address-bar entry.
    private func openExternalLink(_ url: URL, in service: Service, sessionIndex: Int) {
        guard currentService()?.id == service.id else {
            NSLog("[Quiper] External link could not open: engine %@ not selected", service.name)
            return
        }
        switchSession(to: sessionIndex)
        guard let webView = webViewManager.getWebView(for: service, sessionIndex: sessionIndex) else {
            NSLog("[Quiper] External link could not open in %@ session %d", service.name, sessionIndex)
            return
        }
        webViewManager.loadExplicitUserURL(url, in: webView)
    }

    /// The slots of `service` with a live page.
    private func occupiedSessionSlots(for service: Service) -> Set<Int> {
        Set(service.visibleSessionIndices.filter {
            webViewManager.getWebView(for: service, sessionIndex: $0) != nil
        })
    }

    /// Visible slots from most to least recently visited: the engine's
    /// current slot first, then the MRU history, then slots never visited
    /// this session in slot order.
    private func externalLinkVisitOrder(for service: Service) -> [Int] {
        var order: [Int] = []
        var appended = Set<Int>()
        func append(_ slot: Int) {
            guard service.visibleSessionIndices.contains(slot), !appended.contains(slot) else { return }
            appended.insert(slot)
            order.append(slot)
        }
        if let active = activeIndicesByID[service.id] {
            append(active)
        }
        for tab in tabHistory where tab.serviceID == service.id {
            append(tab.sessionIndex)
        }
        for slot in service.visibleSessionIndices {
            append(slot)
        }
        return order
    }

    /// Asks which busy session the link takes over — Quiper's fixed
    /// convention is 10 sessions per engine. Returns nil on cancel.
    private func promptForSessionReplacement(defaultIndex: Int, service: Service) -> Int? {
        let busy = occupiedSessionSlots(for: service)
        let slots = service.visibleSessionIndices.filter { busy.contains($0) }
        guard !slots.isEmpty else { return nil }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "No free session"
        alert.informativeText = "Quiper keeps at most 10 sessions per engine. Choose which session of \(service.name) opens this link — its current page will be replaced."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for slot in slots {
            popup.addItem(withTitle: SessionSlots.tooltipTitle(for: slot))
        }
        popup.selectItem(at: slots.firstIndex(of: defaultIndex) ?? 0)
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open Link")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selected = popup.indexOfSelectedItem
        guard slots.indices.contains(selected) else { return nil }
        return slots[selected]
    }

    private func presentNoOpenSessionAlert(for service: Service) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No open session in \(service.name)"
        alert.informativeText = "Pinned Tabs engines open links only in slots with a tab URL. Add a tab URL in this engine's URL settings, then follow the link again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
