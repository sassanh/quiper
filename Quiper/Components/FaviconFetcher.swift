import Foundation
import AppKit

final class FaviconFetcher {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: FaviconFetcherSessionDelegate.shared, delegateQueue: nil)
    }()

    private static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower.hasSuffix(".local")
    }

    /// Attempts to fetch a favicon for the given URL string.
    /// Tries HTML parsing -> /favicon.ico -> Google Favicon API fallback.
    /// Returns a base64 PNG string of a 32x32 scaled version of the image.
    static func fetchFavicon(for urlString: String) async -> String? {
        guard let url = normalizeURL(urlString), let host = url.host else {
            return nil
        }
        
        // 1. Try HTML parsing for custom favicon link tags
        if let htmlIconUrl = await findIconInHTML(url: url) {
            if let base64 = await downloadAndResizeImage(from: htmlIconUrl) {
                return base64
            }
        }
        
        // 2. Try direct /favicon.ico fetch, preserving the original scheme and port
        let portStr = url.port != nil ? ":\(url.port!)" : ""
        let scheme = url.scheme ?? "https"
        if let directFaviconUrl = URL(string: "\(scheme)://\(host)\(portStr)/favicon.ico") {
            if let base64 = await downloadAndResizeImage(from: directFaviconUrl) {
                return base64
            }
        }
        
        // 3. Fall back to Google's highly reliable Favicon API (skip for local hosts)
        if !isLocalHost(host), let googleApiUrl = URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)") {
            if let base64 = await downloadAndResizeImage(from: googleApiUrl) {
                return base64
            }
        }
        
        return nil
    }
    
    /// Normalizes URL string by prepending http:// or https:// if scheme is missing
    private static func normalizeURL(_ urlString: String) -> URL? {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        
        if !normalized.lowercased().hasPrefix("http://") && !normalized.lowercased().hasPrefix("https://") {
            let lower = normalized.lowercased()
            if lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") {
                normalized = "http://" + normalized
            } else {
                normalized = "https://" + normalized
            }
        }
        
        return URL(string: normalized)
    }
    
    /// Scrapes site HTML to extract link tags indicating favicon assets
    private static func findIconInHTML(url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5.0
        
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Match: <link ... rel="icon" ... href="..." >
        // Match: <link ... href="..." ... rel="apple-touch-icon" >
        // We use a simplified regex scanning for <link[^>]*> elements
        let pattern = "<link[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        
        var bestHref: String? = nil
        var highestPriority = -1
        
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let linkTag = String(html[matchRange])
            
            // Check for rel indicating an icon
            let relPattern = "rel\\s*=\\s*\"([^\"]+)\""
            let hrefPattern = "href\\s*=\\s*\"([^\"]+)\""
            
            guard let relRegex = try? NSRegularExpression(pattern: relPattern, options: .caseInsensitive),
                  let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive) else {
                continue
            }
            
            let tagRange = NSRange(linkTag.startIndex..<linkTag.endIndex, in: linkTag)
            
            guard let relMatch = relRegex.firstMatch(in: linkTag, options: [], range: tagRange),
                  let relValRange = Range(relMatch.range(at: 1), in: linkTag),
                  let hrefMatch = hrefRegex.firstMatch(in: linkTag, options: [], range: tagRange),
                  let hrefValRange = Range(hrefMatch.range(at: 1), in: linkTag) else {
                continue
            }
            
            let rel = String(linkTag[relValRange]).lowercased()
            let href = String(linkTag[hrefValRange])
            
            var priority = -1
            if rel.contains("apple-touch-icon") {
                priority = 3
            } else if rel == "icon" {
                priority = 2
            } else if rel.contains("icon") {
                priority = 1
            }
            
            if priority > highestPriority {
                highestPriority = priority
                bestHref = href
            }
        }
        
        guard let href = bestHref else { return nil }
        
        // Resolve absolute url
        if href.hasPrefix("//") {
            return URL(string: "https:" + href)
        } else if href.hasPrefix("/") {
            guard let scheme = url.scheme, let host = url.host else { return nil }
            let portStr = url.port != nil ? ":\(url.port!)" : ""
            return URL(string: "\(scheme)://\(host)\(portStr)\(href)")
        } else if href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") {
            return URL(string: href)
        } else {
            // Relative to current url directory path
            return URL(string: href, relativeTo: url)?.absoluteURL
        }
    }
    
    /// Downloads image, resizes it to 32x32, converts to PNG and returns Base64 string
    static func downloadAndResizeImage(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5.0
        
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        return resizeAndEncodePNG(data: data)
    }
    
    /// Resizes an NSImage to 32x32 and returns its Base64 PNG representation
    @MainActor
    static func resizeAndEncodePNG(data: Data) -> String? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        let targetSize = NSSize(width: 32, height: 32)
        let resizedImage = NSImage(size: targetSize)
        
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData.base64EncodedString()
    }
}

final class FaviconFetcherSessionDelegate: NSObject, URLSessionDelegate {
    static let shared = FaviconFetcherSessionDelegate()
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host.lowercased()
            if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") {
                // Allow self-signed or invalid certs on local connections
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
