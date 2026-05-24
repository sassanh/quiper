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

    private enum HTMLIconResult {
        case data(Data)
        case url(URL)
    }

    /// Attempts to fetch a favicon for the given URL string.
    /// Tries HTML parsing -> /favicon.ico -> Google Favicon API fallback.
    /// Returns a base64 PNG string of the image.
    static func fetchFavicon(for urlString: String) async -> String? {
        guard let url = normalizeURL(urlString), let host = url.host else {
            return nil
        }
        
        // 1. Try HTML parsing for custom favicon link tags
        var htmlBase64: String? = nil
        if let htmlResult = await findIconInHTML(url: url) {
            switch htmlResult {
            case .data(let rawData):
                htmlBase64 = encodePNG(data: rawData)
            case .url(let htmlIconUrl):
                htmlBase64 = await downloadAndEncodeImage(from: htmlIconUrl)
            }
        }
        
        // If we found a high-resolution icon (>= 48x48) in the HTML, return it immediately
        if let base64 = htmlBase64, isHighRes(base64) {
            return base64
        }
        
        // 2. Try direct /favicon.ico fetch, preserving the original scheme and port
        let portStr = url.port != nil ? ":\(url.port!)" : ""
        let scheme = url.scheme ?? "https"
        var directBase64: String? = nil
        if let directFaviconUrl = URL(string: "\(scheme)://\(host)\(portStr)/favicon.ico") {
            directBase64 = await downloadAndEncodeImage(from: directFaviconUrl)
        }
        
        // If the direct favicon is high-resolution (>= 48x48), return it immediately
        if let base64 = directBase64, isHighRes(base64) {
            return base64
        }
        
        // 3. Fall back to Google's highly reliable faviconV2 API (skip for local hosts) which guarantees 128x128!
        if !isLocalHost(host), let googleApiUrl = URL(string: "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=\(scheme)://\(host)\(portStr)&size=128") {
            if let base64 = await downloadAndEncodeImage(from: googleApiUrl) {
                return base64
            }
        }
        
        // If no high-res icon was successfully retrieved, return the best available low-res icon
        if let base64 = htmlBase64 {
            return base64
        }
        if let base64 = directBase64 {
            return base64
        }
        
        return nil
    }
    
    /// Checks if a base64 PNG string is high resolution (>= 96x96 pixels)
    @MainActor
    private static func isHighRes(_ base64: String) -> Bool {
        guard let decodedData = Data(base64Encoded: base64),
              let image = NSImage(data: decodedData) else {
            return false
        }
        var sourceWidth: CGFloat = image.size.width
        for rep in image.representations {
            let w = CGFloat(rep.pixelsWide)
            if w > sourceWidth {
                sourceWidth = w
            }
        }
        return sourceWidth >= 96
    }
    
    /// Normalizes URL string by prepending http:// or https:// if scheme is missing.
    /// Also forces IPv4 for localhost to avoid IPv6 "Connection refused" from servers
    /// that only bind to 127.0.0.1 (e.g. llama.cpp).
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
        
        // Force IPv4 for localhost — many local servers (llama.cpp, etc.) only bind
        // to 127.0.0.1, but macOS resolves "localhost" to ::1 (IPv6) first.
        // We use a robust case-insensitive string replacement to avoid strict URLComponents percent-encoding failures.
        if normalized.lowercased().contains("localhost") {
            normalized = normalized.replacingOccurrences(of: "localhost", with: "127.0.0.1", options: .caseInsensitive)
        }
        
        return URL(string: normalized)
    }
    
    /// Scrapes site HTML to extract link tags indicating favicon assets.
    /// Returns either raw image data (for inline data URIs) or a resolved absolute URL.
    private static func findIconInHTML(url: URL) async -> HTMLIconResult? {
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
            if rel.contains("mask-icon") {
                priority = 4  // Highest preference for transparent monochrome/template vector!
            } else if href.lowercased().hasSuffix(".svg") {
                priority = 3  // SVG vector format (crisp at any size, often transparent)
            } else if rel.contains("apple-touch-icon") {
                priority = 2  // Crisp high-res fallback
            } else if rel == "icon" {
                priority = 1
            } else if rel.contains("icon") {
                priority = 0
            }
            
            if priority > highestPriority {
                highestPriority = priority
                bestHref = href
            }
        }
        
        guard let href = bestHref else { return nil }
        
        // Handle inline data URIs (e.g. data:image/svg+xml;base64,...)
        if href.lowercased().hasPrefix("data:") {
            guard let commaIndex = href.firstIndex(of: ",") else {
                return nil
            }
            let metadata = href[..<commaIndex].lowercased()
            let dataStr = String(href[href.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if metadata.contains(";base64") {
                if let rawData = Data(base64Encoded: dataStr) {
                    return .data(rawData)
                }
            } else {
                if let decodedStr = dataStr.removingPercentEncoding,
                   let rawData = decodedStr.data(using: .utf8) {
                    return .data(rawData)
                }
            }
            return nil
        }
        
        // Resolve absolute url
        let resolvedUrl: URL?
        if href.hasPrefix("//") {
            resolvedUrl = URL(string: "https:" + href)
        } else if href.hasPrefix("/") {
            guard let scheme = url.scheme, let host = url.host else { return nil }
            let portStr = url.port != nil ? ":\(url.port!)" : ""
            resolvedUrl = URL(string: "\(scheme)://\(host)\(portStr)\(href)")
        } else if href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") {
            resolvedUrl = URL(string: href)
        } else {
            resolvedUrl = URL(string: href, relativeTo: url)?.absoluteURL
        }
        
        if let resolved = resolvedUrl {
            return .url(resolved)
        }
        
        return nil
    }
    
    /// Downloads image, converts to PNG and returns Base64 string
    static func downloadAndEncodeImage(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5.0
        
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        return encodePNG(data: data)
    }
    
    /// Converts an image to its PNG representation and returns its Base64 string.
    /// Extracts the highest-resolution representation from multi-resolution files (like .ico)
    /// and caps large images at a maximum bounding box of 128x128 for storage efficiency.
    @MainActor
    static func encodePNG(data: Data) -> String? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        
        // Find the maximum pixel dimensions among all representations
        var sourceWidth: CGFloat = image.size.width
        var sourceHeight: CGFloat = image.size.height
        
        for rep in image.representations {
            let w = CGFloat(rep.pixelsWide)
            let h = CGFloat(rep.pixelsHigh)
            if w > sourceWidth {
                sourceWidth = w
            }
            if h > sourceHeight {
                sourceHeight = h
            }
        }
        
        let maxDimension: CGFloat = 128.0
        let targetSize: NSSize
        if sourceWidth > maxDimension || sourceHeight > maxDimension {
            let ratio = min(maxDimension / sourceWidth, maxDimension / sourceHeight)
            targetSize = NSSize(width: sourceWidth * ratio, height: sourceHeight * ratio)
        } else {
            targetSize = NSSize(width: sourceWidth, height: sourceHeight)
        }
        
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Passing .zero as 'fromRect' prompts AppKit to automatically select and draw the
        // best-fitting (highest-resolution) representation for the target destination rect.
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: .zero,
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
