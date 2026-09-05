import Foundation

// MARK: - Server sign-in (HTTP Basic/Digest authentication)
//
// Local engines such as OpenCode (`opencode web` with OPENCODE_SERVER_PASSWORD
// set) protect their web UI with HTTP authentication. WKWebView never prompts
// on its own: without a navigation-delegate challenge handler the load just
// fails. Both platform delegates route user/password challenges through
// ServerAuthenticationCoordinator, which owns the decision (silent credential
// reuse vs. prompting) and coalesces concurrent challenges for the same
// protection space, so N sessions hitting one locked server produce a single
// sign-in prompt instead of N stacked sheets.

/// What the sign-in prompt shows. Pure data; each platform renders it natively.
struct ServerAuthenticationPrompt: Sendable {
    /// Engine the challenge belongs to, for context (e.g. "OpenCode").
    let serviceName: String?
    /// Host with port when explicit, e.g. "127.0.0.1:4096".
    let displayHost: String
    let realm: String?
    /// Username to prefill: the previously rejected one, or the remembered one.
    let suggestedUsername: String
    /// True when credentials would travel unencrypted (Basic over http).
    let showsUnencryptedWarning: Bool
    /// True when a previous sign-in attempt for this space was rejected.
    let isRetry: Bool
}

/// What the user decided in the sign-in prompt.
enum ServerAuthenticationDecision: Sendable {
    case signIn(username: String, password: String, remember: Bool)
    case cancel
}

/// Single gate for HTTP authentication challenges from every engine web view.
@MainActor
final class ServerAuthenticationCoordinator {
    static let shared = ServerAuthenticationCoordinator()
    private init() {}

    typealias ChallengeCompletion = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    private struct PendingPrompt {
        var protectionSpace: URLProtectionSpace
        var serviceName: String?
        var waiters: [ChallengeCompletion]
    }

    private var pendingPrompts: [String: PendingPrompt] = [:]

    /// Resolves one challenge. Non-password methods fall through to default
    /// handling. A stored credential is reused silently on first attempt; a
    /// prompt is presented otherwise (or when the stored credential failed).
    /// Challenges arriving for the same space while its prompt is open join
    /// the pending prompt and share its outcome.
    func handle(
        _ challenge: URLAuthenticationChallenge,
        serviceName: String?,
        completionHandler: @escaping ChallengeCompletion,
        presentPrompt: @escaping (ServerAuthenticationPrompt, @escaping (ServerAuthenticationDecision) -> Void) -> Void
    ) {
        let space = challenge.protectionSpace
        guard ServerAuthentication.handlesAuthenticationMethod(space.authenticationMethod) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let key = ServerAuthentication.key(for: space)
        if pendingPrompts[key] != nil {
            pendingPrompts[key]?.waiters.append(completionHandler)
            if pendingPrompts[key]?.serviceName == nil {
                pendingPrompts[key]?.serviceName = serviceName
            }
            return
        }
        pendingPrompts[key] = PendingPrompt(protectionSpace: space, serviceName: serviceName, waiters: [completionHandler])

        if challenge.previousFailureCount == 0,
           let stored = challenge.proposedCredential ?? URLCredentialStorage.shared.defaultCredential(for: space),
           stored.hasPassword {
            finish(key: key, disposition: .useCredential, credential: stored)
            return
        }

        let suggestedUsername = challenge.proposedCredential?.user
            ?? URLCredentialStorage.shared.defaultCredential(for: space)?.user
            ?? ""
        let prompt = ServerAuthenticationPrompt(
            serviceName: serviceName,
            displayHost: ServerAuthentication.displayHost(for: space),
            realm: space.realm,
            suggestedUsername: suggestedUsername,
            showsUnencryptedWarning: !space.receivesCredentialSecurely,
            isRetry: challenge.previousFailureCount > 0
        )
        presentPrompt(prompt) { [weak self] decision in
            Task { @MainActor in
                self?.resolve(key: key, space: space, decision: decision)
            }
        }
    }

    private func resolve(key: String, space: URLProtectionSpace, decision: ServerAuthenticationDecision) {
        switch decision {
        case .signIn(let username, let password, let remember):
            let credential = URLCredential(
                user: username,
                password: password,
                persistence: remember ? .permanent : .forSession
            )
            URLCredentialStorage.shared.setDefaultCredential(credential, for: space)
            finish(key: key, disposition: .useCredential, credential: credential)
        case .cancel:
            finish(key: key, disposition: .cancelAuthenticationChallenge, credential: nil)
        }
    }

    private func finish(key: String, disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?) {
        guard let pending = pendingPrompts.removeValue(forKey: key) else { return }
        for waiter in pending.waiters {
            waiter(disposition, credential)
        }
    }
}

/// Pure helpers behind the coordinator: which challenges take a username and
// password, and how a protection space is identified and displayed.
enum ServerAuthentication {
    static func handlesAuthenticationMethod(_ method: String) -> Bool {
        method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodHTTPDigest
    }

    static func key(for space: URLProtectionSpace) -> String {
        [
            space.authenticationMethod,
            space.host.lowercased(),
            String(space.port),
            space.realm ?? "",
        ].joined(separator: "\n")
    }

    static func displayHost(for space: URLProtectionSpace) -> String {
        space.port == 0 ? space.host : "\(space.host):\(space.port)"
    }
}
