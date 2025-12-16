import Cocoa
import WebKit
// MARK: - WKDownloadDelegate
@available(macOS 11.3, *)
extension MainWindowController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Determine filename
        let filename = suggestedFilename.isEmpty ? (response.url?.lastPathComponent ?? "download") : suggestedFilename
        
        // Check for test override

        let downloads: URL
        if let testPath = UserDefaults.standard.string(forKey: "test-downloads-path") {
            NSLog("[Quiper][WKDownload] Test override logic active. Path from defaults: \(testPath)")
            downloads = URL(fileURLWithPath: testPath)
        } else {
            downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        }
        
        // Ensure filenames are unique to avoid overwriting (or handle conflicts)
        // For blob downloads, the suggested filename might be generic.
        let uniqueFilename = filename 
            + (FileManager.default.fileExists(atPath: downloads.appendingPathComponent(filename).path) ? "-\(UUID().uuidString.prefix(4))" : "")
        
        let destination = downloads.appendingPathComponent(uniqueFilename)
        
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        } catch {
            NSLog("[Quiper][WKDownload] Failed to create directory: \(error.localizedDescription)")
        }
        
        NSLog("[Quiper][WKDownload] Destination: \(destination.path)")
        completionHandler(destination)
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        NSLog("[Quiper][WKDownload] Failed: \(error.localizedDescription)")
        activeDownloads.removeAll { ($0 as? WKDownload) === download }
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        NSLog("[Quiper][WKDownload] Finished successfully.")
        activeDownloads.removeAll { ($0 as? WKDownload) === download }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        NSLog("[Quiper][WKDownload] Redirecting to: \(request.url?.absoluteString ?? "nil")")
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        NSLog("[Quiper][WKDownload] Auth challenge: \(challenge.protectionSpace.authenticationMethod)")
        completionHandler(.performDefaultHandling, nil)
    }
}
