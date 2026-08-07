import Foundation

/// Platform-neutral link routing shared by the macOS and iOS targets. This is the
/// same decision logic the macOS app applies in `WebViewManager`: same-origin
/// navigations always stay in place, otherwise the engine's routing rules decide,
/// defaulting to external.
enum RoutingResolver {
    enum Decision {
        case openHere
        case openNewWindow
        case openExternal
        case showPrompt
        case cancel
    }

    static func matchesPattern(targetString: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(location: 0, length: targetString.utf16.count)
        return regex.firstMatch(in: targetString, options: [], range: range) != nil
    }

    static func route(for url: URL, service: Service, serviceURL: URL) -> Decision {
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
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
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
