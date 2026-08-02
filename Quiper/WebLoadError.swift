import Foundation

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
        case httpClientError(statusCode: Int)
        case httpServerError(statusCode: Int)
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
            case let .httpClientError(statusCode):
                return Self.httpClientTitle(for: statusCode)
            case let .httpServerError(statusCode):
                return Self.httpServerTitle(for: statusCode)
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
            case let .httpClientError(statusCode):
                return Self.httpClientMessage(for: statusCode)
            case let .httpServerError(statusCode):
                return Self.httpServerMessage(for: statusCode)
            case .contentProcessTerminated:
                return "The page process stopped unexpectedly."
            case .unknown:
                return "An unexpected error prevented the page from loading."
            }
        }

        private static func httpClientTitle(for statusCode: Int) -> String {
            switch statusCode {
            case 400: return "Bad request"
            case 401, 407: return "Authentication required"
            case 403: return "Access denied"
            case 404: return "Page not found"
            case 405: return "Method not allowed"
            case 408: return "Request timed out"
            case 409: return "Request conflict"
            case 410: return "Page is gone"
            case 413: return "Request is too large"
            case 414: return "Address is too long"
            case 415: return "Unsupported request"
            case 422: return "Request could not be processed"
            case 423: return "Resource is locked"
            case 425: return "Request could not be processed yet"
            case 426: return "Connection upgrade required"
            case 429: return "Too many requests"
            case 431: return "Request headers are too large"
            case 451: return "Page is unavailable"
            default: return "Client request failed"
            }
        }

        private static func httpClientMessage(for statusCode: Int) -> String {
            switch statusCode {
            case 401, 407:
                return "The server requires authentication before it can show this page."
            case 403:
                return "You do not have permission to view this page."
            case 404:
                return "The requested page could not be found."
            case 408:
                return "The server timed out while waiting for the request."
            case 429:
                return "The server is receiving too many requests."
            default:
                return "The server could not process this request."
            }
        }

        private static func httpServerTitle(for statusCode: Int) -> String {
            switch statusCode {
            case 500: return "Server error"
            case 501: return "Server feature unavailable"
            case 502: return "Bad gateway"
            case 503: return "Service unavailable"
            case 504: return "Gateway timed out"
            case 505: return "HTTP version unsupported"
            case 511: return "Network authentication required"
            default: return "Server request failed"
            }
        }

        private static func httpServerMessage(for statusCode: Int) -> String {
            switch statusCode {
            case 502:
                return "The server received an invalid response from another server."
            case 503:
                return "The server is temporarily unavailable."
            case 504:
                return "Another server took too long to respond."
            case 511:
                return "The network requires authentication before it can connect."
            default:
                return "The server could not complete this request."
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

    static func http(statusCode: Int, url: URL? = nil) -> WebLoadError {
        let kind: Kind = (400..<500).contains(statusCode)
            ? .httpClientError(statusCode: statusCode)
            : .httpServerError(statusCode: statusCode)
        return WebLoadError(kind: kind, url: url)
    }

    static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
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
