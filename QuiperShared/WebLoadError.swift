import Foundation
import WebKit

struct WebLoadError: Equatable {
    enum Kind: Equatable {
        case timeout
        case dnsFailure
        case connectionUnavailable
        case offline
        case connectionLost
        case secureConnectionFailure
        case authenticationFailure
        case redirectFailure
        case invalidURL
        case resourceUnavailable
        case fileAccessFailure
        case contentProcessTerminated
        case unknown

        var title: String {
            switch self {
            case .timeout:
                return "Connection timed out"
            case .dnsFailure:
                return "Address not found"
            case .connectionUnavailable:
                return "Unable to connect"
            case .offline:
                return "No internet connection"
            case .connectionLost:
                return "Connection lost"
            case .secureConnectionFailure:
                return "Secure connection failed"
            case .authenticationFailure:
                return "Authentication failed"
            case .redirectFailure:
                return "Redirect failed"
            case .invalidURL:
                return "Invalid address"
            case .resourceUnavailable:
                return "Resource unavailable"
            case .fileAccessFailure:
                return "File could not be opened"
            case .contentProcessTerminated:
                return "Page process stopped"
            case .unknown:
                return "Page failed to load"
            }
        }

        var message: String {
            switch self {
            case .timeout:
                return "The server took too long to respond."
            case .dnsFailure:
                return "The address could not be found."
            case .connectionUnavailable:
                return "A connection to the server could not be established."
            case .offline:
                return "Check your internet connection and try again."
            case .connectionLost:
                return "The connection ended before the page finished loading."
            case .secureConnectionFailure:
                return "The server could not establish a trusted secure connection."
            case .authenticationFailure:
                return "The server rejected the authentication request."
            case .redirectFailure:
                return "The page could not follow the server's redirect."
            case .invalidURL:
                return "The page address is not valid or supported."
            case .resourceUnavailable:
                return "The requested page is currently unavailable."
            case .fileAccessFailure:
                return "The local file is missing or cannot be read."
            case .contentProcessTerminated:
                return "The page process stopped unexpectedly."
            case .unknown:
                return "An unexpected error prevented the page from loading."
            }
        }
    }

    let kind: Kind
    let url: URL?

    init(kind: Kind, url: URL? = nil) {
        self.kind = kind
        self.url = url
    }

    init(error: Error, fallbackURL: URL? = nil) {
        let nsError = error as NSError
        self.kind = Self.kind(for: nsError)
        self.url = Self.failingURL(from: nsError) ?? fallbackURL
    }

    static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    /// Fires when a navigation was superseded or cancelled by a policy
    /// decision (redirects, downloads, custom routing) rather than by a real
    /// failure — must never surface as a load error.
    ///
    /// Code 102 is `WKErrorFrameLoadInterruptedByPolicyChange`
    /// ("Frame load interrupted"); the constant isn't exposed to Swift on all
    /// SDKs, so its stable numeric identity is used directly.
    static func isFrameLoadInterrupted(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "WebKitErrorDomain" && nsError.code == 102
    }

    private static func kind(for error: NSError) -> Kind {
        guard error.domain == NSURLErrorDomain else { return .unknown }

        switch URLError.Code(rawValue: error.code) {
        case .timedOut:
            return .timeout
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure
        case .cannotConnectToHost:
            return .connectionUnavailable
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .networkConnectionLost:
            return .connectionLost
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return .secureConnectionFailure
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return .authenticationFailure
        case .httpTooManyRedirects, .redirectToNonExistentLocation:
            return .redirectFailure
        case .badURL, .unsupportedURL:
            return .invalidURL
        case .resourceUnavailable, .cannotLoadFromNetwork, .dataLengthExceedsMaximum:
            return .resourceUnavailable
        case .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile:
            return .fileAccessFailure
        default:
            return .unknown
        }
    }

    private static func failingURL(from error: NSError) -> URL? {
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        // Keep compatibility with older NSError payloads without referencing
        // the deprecated Foundation constant.
        if let urlString = error.userInfo["NSErrorFailingURLStringKey"] as? String {
            return URL(string: urlString)
        }
        return nil
    }
}

struct WebProcessTerminationRetryState {
    private(set) var hasRetried = false

    mutating func shouldRetry() -> Bool {
        guard !hasRetried else { return false }
        hasRetried = true
        return true
    }

    mutating func reset() {
        hasRetried = false
    }
}
