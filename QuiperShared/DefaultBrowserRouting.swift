import Foundation

/// Decides where links open when Quiper is itself the system default browser.
enum DefaultBrowserRouting {
    /// Used when no fallback is recorded or the recorded app is gone:
    /// Safari ships with macOS and always resolves.
    static let safariBundleIdentifier = "com.apple.safari"

    /// The browser unclaimed links open with: the recorded fallback when it
    /// still resolves, Safari when nothing is recorded or the recorded app
    /// is gone — and never a build of Quiper, which would hand the link
    /// straight back into the loop the caller is escaping.
    static func fallbackBundleIdentifier(
        recorded: String?,
        quiperBundleIdentifier: String,
        resolvable: (String) -> Bool
    ) -> String {
        if let recorded,
           resolvable(recorded),
           !isQuiperBundleIdentifier(recorded, quiperBundleIdentifier: quiperBundleIdentifier) {
            return recorded
        }
        return safariBundleIdentifier
    }

    /// Whether a bundle identifier names a build of Quiper. Every build
    /// shares the product prefix, so stale or parallel copies — a Debug
    /// build, a repo-root release — are recognized too.
    static func isQuiperBundleIdentifier(
        _ bundleIdentifier: String,
        quiperBundleIdentifier: String
    ) -> Bool {
        guard let separator = quiperBundleIdentifier.lastIndex(of: ".") else {
            return bundleIdentifier == quiperBundleIdentifier
        }
        return bundleIdentifier.hasPrefix(quiperBundleIdentifier[..<separator])
    }

    /// Whether Launch Services would open links in a build of Quiper itself —
    /// forwarding such a link would bounce it straight back in a loop. The
    /// family rule, not exact equality: the system default can be the
    /// resident link helper or a stale parallel build, and both count as
    /// Quiper. Compared by bundle identifier: Launch Services and
    /// `Bundle.main` can report the same app as differently spelled file URLs.
    static func isQuiperDefaultOpener(applicationURL: URL?, quiperBundleIdentifier: String) -> Bool {
        guard let applicationURL,
              let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier else {
            return false
        }
        return isQuiperBundleIdentifier(bundleIdentifier, quiperBundleIdentifier: quiperBundleIdentifier)
    }
}
