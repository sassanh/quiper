import AppKit

extension Notification.Name {
    /// Posted by `KeyFocusGate` after it handled AppKit's key-status
    /// notification. The gate is the app's only listener of AppKit's key
    /// notifications; windows that react to focus changes subscribe here
    /// instead of opening a second observer of their own.
    static let quiperKeyWindowDidBecomeKey = Notification.Name("QuiperKeyWindowDidBecomeKey")
    static let quiperKeyWindowDidResignKey = Notification.Name("QuiperKeyWindowDidResignKey")
}

/// A weak handle to a recorded focus window; popup entries use it so a
/// closed popup never keeps history alive.
struct WeakWindowReference {
    weak var window: NSWindow?
}

/// The application's single authority over key-window status.
///
/// Every deliberate move of key status — the show restore, the
/// session-switch focus policy, popup creation and close, HUD and panel
/// presentation, activation precedence, and the successor chosen when a
/// key window leaves the screen — travels through this type. Call sites
/// announce what happened (`orderOut`, `willHide`, `popupWillClose`,
/// `windowWillClose`) or request focus (`focus`, `focusPopup`,
/// `applyPrecedence`); the gate alone performs the transition, alone
/// records focus history, and alone applies the Settings/update-prompt
/// precedence. The only key changes that do not start here are AppKit's
/// own hand-offs inside a single window-tree operation — the gate is the
/// app's sole listener for those and judges their results when recording
/// history, and it removes the need for them wherever our code is the one
/// ordering a key window out by deciding the successor first.
@MainActor
final class KeyFocusGate: NSObject {

    static let shared = KeyFocusGate()

    /// How a focus request orders the target among its siblings.
    enum Ordering {
        /// `makeKeyAndOrderFront` — bring the target to the front.
        case orderFront
        /// `makeKey` only — move key status without touching stacking.
        case keyOnly
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyStatusChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyStatusChanged(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    // MARK: - The governing overlay

    /// The controller whose overlay currently governs focus. `show()`
    /// registers it; it scopes recording, popup policy, and restore to the
    /// stage actually on screen. With no visible overlay nothing records,
    /// because no Quiper window can be the user's choice while hidden.
    weak var activeController: MainWindowController?

    // MARK: - Focus history (the only copy)

    /// The Quiper window that most recently took key status while the
    /// governing overlay was on screen — the show stage restores it.
    private(set) weak var lastKeyWindow: NSWindow?
    /// The controller that recorded `lastKeyWindow`. History belongs to
    /// the stage that recorded it: a show must never restore a window
    /// another controller's overlay recorded, so a stale cross-stage
    /// record reads as no history at all.
    private weak var lastKeyWindowController: MainWindowController?
    /// The most recent key popup per session — the session-switch stage
    /// restores the switching session's own entry instead of whichever
    /// popup opened last.
    private(set) var lastKeyPopupBySession: [TabIdentifier: WeakWindowReference] = [:]
    /// The focus descriptor saved at quit: the show stage consumes it on
    /// the first restore after launch, when in-memory history is empty.
    var pendingLaunchRestore: PersistedKeyWindow?

    // MARK: - Performing transitions (the only key-moving code)

    /// Gives key status to `window`. Every caller in the app comes through
    /// here; nothing else calls `makeKey`/`makeKeyAndOrderFront`.
    func focus(_ window: NSWindow?, ordering: Ordering = .orderFront) {
        guard let window else { return }
        switch ordering {
        case .orderFront:
            window.makeKeyAndOrderFront(nil)
        case .keyOnly:
            window.makeKey()
        }
    }

    /// Gives key status and content focus to a managed, visible popup.
    /// Returns false when the window is not a live popup of the governing
    /// overlay, so callers fall through to their fallback target.
    @discardableResult
    func focusPopup(_ popup: NSWindow) -> Bool {
        guard let manager = activeController?.webViewManager,
              manager.isPopupWindow(popup),
              popup.isVisible else { return false }
        // Key status and the responder chain move; this request itself
        // orders nothing. The gate's own fan-out then raises the popup's
        // branch in the stack (WebViewManager), so focusing a buried
        // popup brings its whole branch forward, never a lone window out
        // of its band.
        focus(popup, ordering: .keyOnly)
        manager.focusPopupContent(popup)
        return true
    }

    /// Re-keys whatever currently holds key status — used after a system
    /// prompt (biometrics, Keychain) took focus away.
    func reassertCurrentKey() {
        guard NSApp.isActive else { return }
        focus(NSApp.keyWindow, ordering: .orderFront)
    }

    /// Orders a Quiper window out after deciding who takes focus. If the
    /// window holds key status the successor is keyed first, so AppKit has
    /// no hand-off to choose: a hidden overlay leaves nothing of ours on
    /// screen and focus leaves the app; anything else hands focus to the
    /// precedence window or the overlay. Non-key windows simply order out.
    func orderOut(_ window: NSWindow?) {
        guard let window else { return }
        if holdsKeyStatus(window) {
            focusSuccessor(beforeLeaving: window)
        }
        window.orderOut(nil)
    }

    /// Declares that `window` is about to leave the screen on its own
    /// (an animated hide whose own view orders it out later), so focus
    /// moves first instead of AppKit choosing once the view hides. The
    /// departure itself is declared whether or not `window` holds key
    /// status — the overlay taking key is often what triggered the hide,
    /// so key status alone would miss the departure and the open-HUD
    /// query would re-key the fading window a turn later. Focus only
    /// moves when the hiding window still holds key status.
    func willHide(_ window: NSWindow?) {
        guard let window else { return }
        if holdsKeyStatus(window) {
            focusSuccessor(beforeLeaving: window)
        } else {
            declareDeparture(window)
        }
    }

    /// A managed popup is closing while holding key status: the hand-back
    /// to its parent is decided here, before the close, never after — and
    /// a hidden parent is never re-ordered front. A cascade close (the
    /// parent popup is itself closing, `parentIsClosing`) hands focus at
    /// its own level instead. The close's departure is declared first, so
    /// the hand-back records as what it is — the popup leaving — and the
    /// persisted descriptor keeps the user's choice instead of being
    /// re-aimed at the parent.
    func popupWillClose(_ popup: NSWindow, parent: NSWindow?, parentIsClosing: Bool) {
        guard holdsKeyStatus(popup), let parent, parent.isVisible, !parentIsClosing else { return }
        declareDeparture(popup)
        focus(parent, ordering: .orderFront)
    }

    /// Any other Quiper window closes while holding key status: focus
    /// moves to the precedence window or the overlay first, chosen here.
    func windowWillClose(_ closing: NSWindow) {
        guard holdsKeyStatus(closing),
              let overlay = activeController?.window,
              overlay.isVisible else { return }
        focusSuccessor(beforeLeaving: closing)
    }

    /// Whether `window` holds key status in the system's own record rather
    /// than its self-report: a window can override `isKeyWindow` to claim
    /// status it never had (the selector's expanded panel always claims
    /// it, while `canBecomeKey` forbids it ever holding key status), and a
    /// claim must never trigger a focus hand-off — successors are chosen
    /// only for the window that actually held key status, so collapsing a
    /// panel leaves focus exactly where the user put it.
    private func holdsKeyStatus(_ window: NSWindow) -> Bool {
        NSApp.keyWindow === window
    }

    // MARK: - The show stage

    /// The show stage's snapshot: taken before the show orders the overlay
    /// front (which fires didBecomeKey and overwrites history), so the
    /// restore brings back the window that held key before the hide.
    /// Scoped to the stage that recorded it — a record from another
    /// controller's overlay is not this stage's history, and restoring it
    /// would hand the show key status for a window the stage never had.
    func snapshotForRestore() -> NSWindow? {
        guard lastKeyWindowController === activeController else { return nil }
        return lastKeyWindow
    }

    /// The show stage's pre-frame restore: the same policy as
    /// `restoreAfterShow`, run inside show()'s own turn — before the
    /// mapping flush presents anything — because AppKit's hand-off during
    /// the overlay's show leaves the front-most popup holding key status,
    /// and showing that state for a turn is the bright blink on reshow.
    /// The launch descriptor waits for the post-frame call: its popup does
    /// not exist yet at this stage.
    func restoreBeforeFirstFrame(snapshot: NSWindow?) {
        guard pendingLaunchRestore == nil else { return }
        restoreAfterShow(snapshot: snapshot)
    }

    /// The show stage's restore: the recorded window first, then the
    /// descriptor saved at quit, then the popup the user sees in front,
    /// then the overlay. Windows with their own show precedence (an
    /// attached sheet, Settings, the update prompt, onboarding) keep key
    /// status untouched.
    func restoreAfterShow(snapshot: NSWindow?) {
        guard let controller = activeController,
              let overlay = controller.window,
              overlay.isVisible else { return }
        guard !isFocusReservedElsewhere() else { return }
        // An open HUD owns the show's focus — the overlay's own
        // became-key rule targets it, scheduled before this restore
        // runs — so restoring the snapshot here would steal focus back.
        guard controller.openHUDs.isEmpty else { return }

        if let target = snapshot, target !== overlay, target.isVisible {
            if controller.webViewManager?.isPopupWindow(target) == true {
                if focusPopup(target) { return }
            } else {
                focus(target, ordering: .keyOnly)
                return
            }
        }
        // The descriptor from the previous run, consumed on first use: it
        // is the only record of which window held key at quit. An overlay
        // record keys the overlay — popups in front stay dim — and a popup
        // record that no longer resolves falls through to the defaults.
        // The popup case resolves against the launch restore's own record
        // of which saved entry became which window: the `occurrence`-th
        // saved popup of `owner`, the same identity the save wrote the
        // descriptor from, with no live-list filter able to shift the
        // position between the two. The descriptor carries no URL, so a
        // restored page whose load has not committed still resolves; a
        // popup that is not live and visible falls through to the default
        // focus target.
        if let launch = pendingLaunchRestore {
            pendingLaunchRestore = nil
            switch launch {
            case .overlay:
                focus(overlay, ordering: .keyOnly)
                return
            case .popup(let owner, let occurrence):
                let resolved = controller.webViewManager?.restoredPopupWindow(owner: owner, occurrence: occurrence)
                if let resolved, focusPopup(resolved) { return }
            }
        }
        // No recorded window: the launch restoration left the session's
        // popups in front of the overlay, and the window the user sees on
        // top is the one that should hold focus.
        if snapshot == nil,
           let activeTab = controller.currentTabIdentifier(),
           let frontmost = controller.webViewManager?.frontmostPopup(for: activeTab),
           focusPopup(frontmost) {
            return
        }
        // No recoverable target: the overlay itself.
        focus(overlay, ordering: .keyOnly)
    }

    // MARK: - The session-switch stage

    /// The session-switch focus policy: when the activated session owns
    /// popups, one of them holds key status — the popup this session last
    /// had key if it is still around, otherwise the frontmost under the
    /// stack the interaction built — so focus never lands on the webview
    /// hidden behind a popup. A session with no popups keeps the webview
    /// focus the switch already applied.
    func sessionSwitchFocus(for tab: TabIdentifier) {
        guard let manager = activeController?.webViewManager else { return }
        let focusable = manager.focusablePopups(for: tab)
        guard !focusable.isEmpty else { return }
        let preferred = lastKeyPopupBySession[tab]?.window
        let target = preferred.flatMap { candidate in
            focusable.first(where: { $0 === candidate })
        } ?? manager.frontmostPopup(for: tab)
        guard let target else { return }
        focusPopup(target)
    }

    // MARK: - Precedence

    /// The window whose departure is being handled right now: declared
    /// before any key move in `focusSuccessor`, and unconditionally by
    /// `willHide` (an animated hide can start after the window already
    /// lost key status to the overlay), and it clears on the next
    /// runloop turn — by then the hand-off work it protects has run.
    /// While set, focus must not move back to it (the successor's own
    /// key move would be undone, and open-focus queries skip it), and
    /// precedence no longer counts it.
    private weak var departingFocusWindow: NSWindow?

    /// Whether `window`'s departure is in flight: focus must not move
    /// back to it, and open-focus queries exclude it.
    func isDeparting(_ window: NSWindow) -> Bool {
        departingFocusWindow === window
    }

    /// Settings and the update prompt outrank every other window while
    /// visible and not leaving; the single ordering the veto, the steering,
    /// the show restore, and the activation handler all share.
    func precedenceTarget() -> NSWindow? {
        if AppDelegate.sharedSettingsWindow.isVisible,
           AppDelegate.sharedSettingsWindow !== departingFocusWindow {
            return AppDelegate.sharedSettingsWindow
        }
        if UpdatePromptWindowController.shared.window?.isVisible == true,
           UpdatePromptWindowController.shared.window !== departingFocusWindow {
            return UpdatePromptWindowController.shared.window
        }
        return nil
    }

    /// Applies the precedence window if one is visible; returns whether it
    /// took key status (callers then skip their own focus handling).
    @discardableResult
    func applyPrecedence() -> Bool {
        guard let target = precedenceTarget() else { return false }
        focus(target, ordering: .orderFront)
        return true
    }

    /// Whether another window's show precedence currently outranks the
    /// overlay's own key request (`windowShouldBecomeKey`).
    func shouldBecomeKey() -> Bool {
        precedenceTarget() == nil
    }

    /// Whether the show restore must leave key status untouched.
    private func isFocusReservedElsewhere() -> Bool {
        GhostOnboardingManager.shared.isActive
            || activeController?.window?.attachedSheet != nil
            || precedenceTarget() != nil
    }

    /// Declares that `leaving` is on its way off screen, before any key
    /// move: while in flight the leaving window must not regain focus
    /// (the successor's own key move would be undone, and the overlay's
    /// open-HUD query skips a departing HUD), and precedence stops
    /// counting a window that is leaving. Cleared on the next runloop
    /// turn, covering the hand-off work this declaration protects.
    private func declareDeparture(_ leaving: NSWindow) {
        departingFocusWindow = leaving
        DispatchQueue.main.async { [weak self, weak leaving] in
            guard let self, self.departingFocusWindow === leaving else { return }
            self.departingFocusWindow = nil
        }
    }

    /// The focus successor when `leaving` holds key status: the overlay's
    /// children leave with it, so a departing overlay leaves nothing of
    /// ours on screen and focus leaves the app; any other departure hands
    /// focus to the remaining precedence window, else back to the recorded
    /// content window the departure displaced — an interruption hands the
    /// choice back to where the user left it — else the overlay. Decided
    /// here, never by AppKit.
    private func focusSuccessor(beforeLeaving leaving: NSWindow) {
        if leaving === activeController?.window { return }
        guard let controller = activeController, let overlay = controller.window,
              overlay.isVisible else { return }
        declareDeparture(leaving)
        if let precedence = precedenceTarget() {
            focus(precedence, ordering: .orderFront)
            return
        }
        // A HUD departs into the window it serves — its parent in the
        // child-window tree, the overlay or the popup it rides on — never
        // into the recorded content window: HUDs close for reasons of
        // their own (dismissals, a future timeout), and a departure that
        // only takes the chrome away must not re-aim focus at an
        // unrelated recorded window.
        if controller.isHUDWindow(leaving) {
            if let parent = leaving.parent, parent.isVisible {
                focus(parent, ordering: .orderFront)
            } else {
                focus(overlay, ordering: .orderFront)
            }
            return
        }
        // Hand-back: an interruption window (Settings, the update prompt)
        // leaves while the content window it displaced is still on screen —
        // restore the user's choice instead of re-aiming at the overlay. A
        // popup restores content focus and raises its branch through the
        // gate's fan-out; the overlay re-keys without restacking, exactly
        // like the show restore.
        if let recorded = lastKeyWindow, recorded !== leaving, recorded.isVisible {
            if controller.webViewManager?.isPopupWindow(recorded) == true {
                if focusPopup(recorded) { return }
            } else if recorded === overlay {
                focus(overlay, ordering: .keyOnly)
                return
            }
        }
        focus(overlay, ordering: .orderFront)
    }

    // MARK: - Observing (the app's only AppKit key listener)

    @objc private func handleKeyStatusChanged(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow else { return }
        let becameKey = notification.name == NSWindow.didBecomeKeyNotification
        if becameKey {
            record(changedWindow)
        }
        NotificationCenter.default.post(
            name: becameKey ? .quiperKeyWindowDidBecomeKey : .quiperKeyWindowDidResignKey,
            object: changedWindow
        )
    }

    /// Remembers which window — and which session's popup — just took key
    /// status, so a later show or session switch can restore it, and
    /// persists that focus as the saved state's focus descriptor: a quit
    /// right after this, with no further key transition, must reopen on
    /// this window. Two conditions keep the history honest: the governing
    /// overlay must be on screen (while it is ordered out, AppKit's
    /// teardown hand-offs are not a choice the user made), and the
    /// descriptor is written only for a move between windows still on
    /// screen — a choice the user made — because when the window being
    /// replaced has already left the screen, or its departure is in
    /// flight (declared by `popupWillClose`/`focusSuccessor`), the move
    /// is that departure passing key sideways (a close, an order-out),
    /// and the durable record must keep naming the user's last choice;
    /// the next tab-state save re-derives the record from this in-memory
    /// history. Popup entries hold their window weakly; the pass over the
    /// table prunes entries whose window has since closed.
    private func record(_ window: NSWindow) {
        guard let controller = activeController,
              controller.window?.isVisible == true else { return }
        let replacesDepartedFocus = lastKeyWindow.map {
            !$0.isVisible || $0 === departingFocusWindow
        } ?? false
        guard let owner = controller.webViewManager?.ownerTab(forPopupWindow: window) else {
            // Focus history records content destinations only: the overlay
            // or a popup. Settings, the update prompt, and the HUD panels
            // take key as interruptions — recording one would replace the
            // user's content choice and re-aim the persisted descriptor
            // away from the window they return to when the interruption
            // ends.
            guard window === controller.window else { return }
            lastKeyWindow = window
            lastKeyWindowController = controller
            if !replacesDepartedFocus {
                controller.persistFocusDescriptor()
            }
            return
        }
        // A popup only earns focus history while its own session is on
        // screen: key handed sideways mid-switch (an ordered-out popup
        // passing key to a sibling that the same pass hides next) is
        // teardown noise, not a choice the user made.
        guard owner == controller.currentTabIdentifier() else { return }
        lastKeyWindow = window
        lastKeyWindowController = controller
        lastKeyPopupBySession[owner] = WeakWindowReference(window: window)
        lastKeyPopupBySession = lastKeyPopupBySession.filter { $0.value.window != nil }
        if !replacesDepartedFocus {
            controller.persistFocusDescriptor()
        }
    }
}
