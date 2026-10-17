import Foundation

/// The pointer modifiers a link click carries, platform-neutral: the macOS
/// click pipeline reads them from the click, bare clicks and platforms
/// without them stay empty.
struct ClickModifiers {
    var commandPressed: Bool
    var optionPressed: Bool
    var shiftPressed: Bool

    nonisolated init(commandPressed: Bool = false, optionPressed: Bool = false, shiftPressed: Bool = false) {
        self.commandPressed = commandPressed
        self.optionPressed = optionPressed
        self.shiftPressed = shiftPressed
    }

    nonisolated static let none = ClickModifiers()

    nonisolated var isEmpty: Bool { !commandPressed && !optionPressed && !shiftPressed }
}

/// Platform-neutral link routing shared by the macOS and iOS targets. This is the
/// same decision logic the macOS app applies in `WebViewManager`: same-origin
/// navigations always stay in place, otherwise the engine's routing rules decide,
/// defaulting to external.
enum RoutingResolver {
    enum Decision {
        case openHere
        case openNewWindow
        case openExternal
        case openPrivate
        case showPrompt
        case cancel
    }

    static func matchesPattern(targetString: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(location: 0, length: targetString.utf16.count)
        return regex.firstMatch(in: targetString, options: [], range: range) != nil
    }

    static func route(for url: URL, service: Service, serviceURL: URL, currentURL: URL?) -> Decision {
        route(for: url, service: service, serviceURL: serviceURL, pinnedURL: nil, currentURL: currentURL)
    }

    /// Single gate for link routing. Pinned-tab engines pass their session's
    /// pinned URL so the tab address stays fixed: same-URL reloads stay in
    /// place, every other navigation diverts to a popup or the system browser.
    /// `currentURL` is the committed page address. Same-document fragment
    /// navigations (target matches the page ignoring `#fragment`) always stay
    /// in place, even when the page host has drifted from the service root
    /// through redirects or routing rules. Held click modifiers then force
    /// their own destination through `modifierDecision` — ⌥ opens the link
    /// right here, in every frame and every engine — so the outcome is
    /// exactly what the click performs.
    static func route(
        for url: URL,
        service: Service,
        serviceURL: URL,
        pinnedURL: URL?,
        currentURL: URL?,
        modifiers: ClickModifiers = .none
    ) -> Decision {
        modifierDecision(modifiers: modifiers) ?? routeWithoutModifiers(
            for: url,
            service: service,
            serviceURL: serviceURL,
            pinnedURL: pinnedURL,
            currentURL: currentURL
        )
    }

    /// The single gate for what held ⌘/⌥/⇧ force on a link click. ⌘⇧
    /// always opens the link in a private tab (alone or with ⌥ held too),
    /// ⌘⌥ always sends it to the system browser, and ⌘ always sends it to a
    /// new window, wherever the bare click would have gone. ⌥ performs the
    /// explicit Open Link Here action — the very thing its context-menu
    /// item does — in every frame and every engine, pinned tabs included,
    /// so however the action is triggered it is the same thing. Shift
    /// without ⌘ means nothing and leaves the bare outcome standing.
    /// Returns nil when nothing is forced, so the bare outcome stands.
    static func modifierDecision(modifiers: ClickModifiers) -> Decision? {
        guard !modifiers.isEmpty else { return nil }
        if modifiers.commandPressed {
            if modifiers.shiftPressed { return .openPrivate }
            if modifiers.optionPressed { return .openExternal }
            return .openNewWindow
        }
        return modifiers.optionPressed ? .openHere : nil
    }

    /// The routing rules without click modifiers: the bare click's decision,
    /// which `route` falls back to when no modifier forces its own.
    private static func routeWithoutModifiers(
        for url: URL,
        service: Service,
        serviceURL: URL,
        pinnedURL: URL?,
        currentURL: URL?
    ) -> Decision {
        if let currentURL, urlsMatchIgnoringFragment(url, currentURL) {
            return .openHere
        }
        if let pinnedURL, service.isPinnedTabs {
            if urlsMatchIgnoringFragment(url, pinnedURL) {
                return .openHere
            }
            return routeForPinnedTabs(url: url, service: service)
        }
        let targetHost = url.host?.lowercased()
        let serviceHost = serviceURL.host?.lowercased()
        if let tHost = targetHost, let sHost = serviceHost {
            if tHost == sHost {
                return .openHere
            }
            let rootServiceHost = sHost.hasPrefix("www.") ? String(sHost.dropFirst(4)) : sHost
            if tHost == rootServiceHost || tHost.hasSuffix("." + rootServiceHost) {
                return .openHere
            }
        } else if url.scheme?.lowercased() == serviceURL.scheme?.lowercased() && (url.isFileURL || url.scheme == "data") {
            return .openHere
        } else if url.isFileURL {
            #if os(macOS)
            if Constants.LaunchMode.isUITesting {
                return .openHere
            }
            #endif
        }

        let targetString = url.absoluteString

        for rule in service.routingRules {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pattern.isEmpty && matchesPattern(targetString: targetString, pattern: pattern) {
                switch rule.action {
                case .internalStay:
                    return .openHere
                case .popup:
                    return .openNewWindow
                case .prompt:
                    return .showPrompt
                case .external:
                    return .openExternal
                }
            }
        }

        return .openExternal
    }

    /// Pinned-tab routing: no same-origin fast path, and in-place stays are
    /// diverted to popups so a bare click never changes the tab address.
    /// Prompts and external targets keep their meaning. The explicit Open
    /// Link Here action — the menu item, ⌥, or the prompt's Open Here —
    /// bypasses routing entirely, so it is not decided here.
    private static func routeForPinnedTabs(url: URL, service: Service) -> Decision {
        let targetString = url.absoluteString
        for rule in service.routingRules {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pattern.isEmpty && matchesPattern(targetString: targetString, pattern: pattern) {
                switch rule.action {
                case .internalStay:
                    return .openNewWindow
                case .popup:
                    return .openNewWindow
                case .prompt:
                    return .showPrompt
                case .external:
                    return .openExternal
                }
            }
        }
        return .openExternal
    }

    private static func urlsMatchIgnoringFragment(_ left: URL, _ right: URL) -> Bool {
        var leftComponents = URLComponents(url: left, resolvingAgainstBaseURL: false)
        var rightComponents = URLComponents(url: right, resolvingAgainstBaseURL: false)
        leftComponents?.fragment = nil
        rightComponents?.fragment = nil
        // Server-canonicalized reloads gain or lose a trailing slash; an empty
        // path and "/" name the same document.
        if var left = leftComponents {
            left.path = normalizedComparisonPath(left.path)
            leftComponents = left
        }
        if var right = rightComponents {
            right.path = normalizedComparisonPath(right.path)
            rightComponents = right
        }
        return leftComponents?.string == rightComponents?.string
    }

    private static func normalizedComparisonPath(_ path: String?) -> String {
        guard var path, !path.isEmpty else { return "" }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path == "/" ? "" : path
    }

    /// Resolves a pinned-tab engine's session URL. Nil for single-URL engines
    /// and empty slots.
    static func pinnedURL(for service: Service, sessionIndex: Int) -> URL? {
        guard let pinnedString = service.pinnedURL(for: sessionIndex) else { return nil }
        return URL(string: pinnedString)
    }

    /// Applies a remembered routing choice by inserting a host rule at the top of
    /// the list, mirroring macOS `rememberDecision`.
    static func applyingRememberedRule(host: String, action: RoutingAction, to service: Service) -> Service {
        var updated = service
        updated.routingRules.removeAll { rule in
            rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == host.lowercased()
        }
        let newRule = RoutingRule(pattern: host, action: action)
        updated.routingRules.insert(newRule, at: 0)
        return updated
    }
}
