import Combine
import Foundation
import AppKit

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    struct ReleaseInfo: Equatable {
        let version: String
        let notes: String?
        let downloadURL: URL
        let pageURL: URL
        let requiresBrowserDownload: Bool
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case readyToInstall(URL)
        case installing
        case installed(URL)
        case failed(String)

        var description: String {
            switch self {
            case .idle:
                return "Never checked"
            case .checking:
                return "Checking for updates…"
            case .upToDate:
                return "You’re up to date."
            case .available(let release):
                return "Version \(release.version) is available."
            case .downloading:
                return "Downloading update…"
            case .readyToInstall:
                return "Update ready to install."
            case .installing:
                return "Installing update…"
            case .installed:
                return "Update installed—relaunch to finish."
            case .failed(let message):
                return "Update check failed: \(message)"
            }
        }
    }

    static let shared = UpdateManager()

    @Published var status: Status = .idle
    @Published private(set) var isChecking = false
    @Published var isDownloading = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var availableRelease: ReleaseInfo?
    @Published private(set) var downloadLocation: URL?
    @Published var downloadProgress: Double?

    private lazy var sessionDelegate: UpdateSessionDelegate = UpdateSessionDelegate(manager: self)
    private var session: URLSession!
    private let settings = Settings.shared
    let updatesDirectory: URL
    var downloadTask: URLSessionDownloadTask?
    private let relativeFormatter: RelativeDateTimeFormatter
    private var currentDownloadingRelease: ReleaseInfo?

    private override init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Quiper", isDirectory: true)
        let updatesDir = appDir.appendingPathComponent("Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        self.updatesDirectory = updatesDir
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        self.relativeFormatter = formatter

        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: OperationQueue.main)
        
        // Check arguments in init to set configuration early
        if CommandLine.arguments.contains("--enable-automatic-updates") {
            shouldDisableAutomaticChecksInTests = false
        }
    }

    var shouldDisableAutomaticChecksInTests = true
    
    func handleLaunchIfNeeded() {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        
        // If testing and disabled, return
        if (isRunningTests || isUITesting) && shouldDisableAutomaticChecksInTests {
            return
        }
        
        guard settings.updatePreferences.automaticallyChecksForUpdates || !shouldDisableAutomaticChecksInTests else { return }
        
        // If explicitly enabled for testing via launch argument, bypass interval check
        if shouldDisableAutomaticChecksInTests {
            let now = Date()
            if let last = settings.updatePreferences.lastAutomaticCheck,
               now.timeIntervalSince(last) < Constants.Updates.automaticCheckInterval {
                return
            }
        }
        checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        status = .checking
        downloadLocation = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await self.fetchLatestRelease()
                let now = Date()
                await MainActor.run {
                    self.isChecking = false
                    self.lastCheckedAt = now
                    self.settings.updatePreferences.lastAutomaticCheck = now
                    self.settings.saveSettings()
                    if self.isReleaseNewer(release.version) {
                        self.handleReleaseAvailable(release, userInitiated: userInitiated)
                    } else {
                        self.availableRelease = nil
                        self.status = .upToDate
                    }
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                    self.status = .failed(error.readableDescription)
                    if !userInitiated {
                        NSLog("[UpdateManager] Automatic update check failed: %@", error.readableDescription)
                    }
                }
            }
        }
    }

    @MainActor
    private func handleReleaseAvailable(_ release: ReleaseInfo, userInitiated: Bool) {
        availableRelease = release
        status = .available(release)

        if shouldShowPrompt(for: release.version, userInitiated: userInitiated) {
            UpdatePromptWindowController.shared.present(for: release)
            if !userInitiated {
                settings.updatePreferences.lastNotifiedVersion = release.version
                settings.saveSettings()
            }
        }

        if settings.updatePreferences.automaticallyDownloadsUpdates {
            downloadLatestRelease()
        }
    }

    func downloadLatestRelease() {
        guard let release = availableRelease else { return }
        guard !isDownloading else { return }
        if release.requiresBrowserDownload {
            NSWorkspace.shared.open(release.pageURL)
            status = .available(release)
            return
        }
        
        if CommandLine.arguments.contains("--mock-update-available") {
            isDownloading = true
            status = .downloading
            downloadProgress = 0
            currentDownloadingRelease = release
            
            // Simulate download progress
            Task {
                for i in 1...10 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    await MainActor.run {
                        self.downloadProgress = Double(i) / 10.0
                    }
                }
                
                await MainActor.run {
                    // Fake a downloaded file
                    let dummyURL = FileManager.default.temporaryDirectory.appendingPathComponent("mock-update.zip")
                    try? "dummy content".write(to: dummyURL, atomically: true, encoding: .utf8)
                    self.handleDownloadReady(at: dummyURL)
                }
            }
            return
        }

        isDownloading = true
        status = .downloading
        downloadProgress = 0
        currentDownloadingRelease = release
        let task = session.downloadTask(with: release.downloadURL)
        downloadTask = task
        task.resume()
    }

    func installReadyUpdate() {
        guard case .readyToInstall = status, let release = availableRelease, let location = downloadLocation else { return }
        
        if CommandLine.arguments.contains("--mock-update-available") {
            status = .installing
            
            // Simulate install delay
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                await MainActor.run {
                     // Directly succeed
                     self.handleInstallationSuccess(installedURL: self.updatesDirectory.appendingPathComponent("MockApp.app"), release: release)
                }
            }
            return
        }
        
        installDownloadedRelease(from: location, release: release)
    }

    private func installDownloadedRelease(from fileURL: URL, release: ReleaseInfo) {
        status = .installing
        let updatesDir = updatesDirectory
        var currentBundleURL = Bundle.main.bundleURL
        
        // During UI tests (specifically enabled one), we can't overwrite the running bundle
        // in DerivedData due to permissions/sandboxing. Redirect to a dummy target.
        if CommandLine.arguments.contains("--enable-automatic-updates") {
            let tempDir = FileManager.default.temporaryDirectory
            let dummyApp = tempDir.appendingPathComponent("QuiperConfiguredForTest.app")
            // Create a placeholder directory to be replaced
            try? FileManager.default.createDirectory(at: dummyApp, withIntermediateDirectories: true)
            currentBundleURL = dummyApp
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<URL, Error> = Result {
                let installer = UpdateInstaller(archiveURL: fileURL,
                                                updatesDirectory: updatesDir,
                                                currentBundleURL: currentBundleURL)
                return try installer.perform()
            }
            Task { @MainActor [weak self] in
                switch result {
                case .success(let installedURL):
                    self?.handleInstallationSuccess(installedURL: installedURL, release: release)
                case .failure(let error):
                    self?.handleInstallationFailure(error: error, artifactURL: fileURL)
                }
            }
        }
    }

    @MainActor
    private func handleInstallationSuccess(installedURL: URL, release: ReleaseInfo) {
        downloadLocation = installedURL
        availableRelease = nil
        status = .installed(installedURL)
        UpdatePromptWindowController.shared.dismissIfNeeded()
        presentPostInstallPrompt(for: release)
    }

    @MainActor
    private func handleInstallationFailure(error: Error, artifactURL: URL) {
        status = .failed(error.readableDescription)
    }

    @MainActor
    private func presentPostInstallPrompt(for release: ReleaseInfo) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update installed"
        alert.informativeText = "\(Constants.APP_NAME) updated to version \(release.version). Relaunch now to finish installing."
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApplication()
        }
    }

    @MainActor
    private func relaunchApplication() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        
        let helperURL = URL(fileURLWithPath: "/tmp/relauncher_\(pid).sh")
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        sleep 0.5
        open "\(bundlePath)"
        rm "$0"
        """
        
        try? script.write(to: helperURL, atomically: true, encoding: .utf8)
        chmod(helperURL.path, 0o755)
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [helperURL.path]
        try? task.run()
        
        NSApp.terminate(nil)
    }

    @MainActor
    func relaunchApplicationFromPrompt() {
        relaunchApplication()
    }

    var statusDescription: String {
        var message = status.description
        if let lastCheckedAt, status != .checking {
            let relative = relativeFormatter.localizedString(for: lastCheckedAt, relativeTo: Date())
            let suffix = "Last checked \(relative)"
            if message.isEmpty {
                message = suffix
            } else {
                message += " — \(suffix)"
            }
        }
        return message
    }


    private func fetchLatestRelease() async throws -> ReleaseInfo {
        if CommandLine.arguments.contains("--mock-update-available") {
            // Return a dummy release that is guaranteed to be newer than local
            return ReleaseInfo(version: "999.0.0",
                               notes: "This is a mock update for testing.",
                               downloadURL: URL(string: "https://example.com/mock-update.zip")!,
                               pageURL: URL(string: "https://example.com/mock-release")!,
                               requiresBrowserDownload: false)
        }

        var request = URLRequest(url: Constants.Updates.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(GitHubRelease.self, from: data)
        let version = normalizedVersion(payload.tagName)
        let preferredAsset = payload.assets.first { asset in
            Constants.Updates.preferredAssetExtensions.contains(asset.browserDownloadUrl.pathExtension.lowercased())
        }
        let downloadURL = preferredAsset?.browserDownloadUrl ?? payload.htmlUrl
        let requiresBrowser = preferredAsset == nil
        return ReleaseInfo(version: version,
                           notes: payload.body,
                           downloadURL: downloadURL,
                           pageURL: payload.htmlUrl,
                           requiresBrowserDownload: requiresBrowser)
    }

    private func isReleaseNewer(_ releaseVersion: String) -> Bool {
        let current = currentAppVersion()
        let lhs = normalizedComponents(from: releaseVersion)
        let rhs = normalizedComponents(from: current)
        let count = max(lhs.count, rhs.count)
        for idx in 0..<count {
            let left = idx < lhs.count ? lhs[idx] : 0
            let right = idx < rhs.count ? rhs[idx] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func currentAppVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    private func normalizedComponents(from version: String) -> [Int] {
        return normalizedVersion(version)
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    private func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        if let dashIndex = trimmed.firstIndex(of: "-") {
            return String(trimmed[..<dashIndex])
        }
        return trimmed
    }

    private func shouldShowPrompt(for releaseVersion: String, userInitiated: Bool) -> Bool {
        // If explicitly enabled for testing, always show prompt
        if !shouldDisableAutomaticChecksInTests { return true }

        // If running checks in tests (and not explicitly enabled above), BLOCK prompt
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        if (isRunningTests || isUITesting) {
            return false
        }

        if userInitiated { return true }
        
        if settings.updatePreferences.lastNotifiedVersion == releaseVersion {
            return false
        }
        return settings.updatePreferences.automaticallyChecksForUpdates
    }

    struct DownloadSnapshot {
        let task: URLSessionDownloadTask?
        let directory: URL
    }
    
    var downloadSnapshot: DownloadSnapshot {
        DownloadSnapshot(task: downloadTask, directory: updatesDirectory)
    }
}

private final class UpdateSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    unowned let manager: UpdateManager
    init(manager: UpdateManager) { self.manager = manager }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            let isExpectedTask: Bool = await MainActor.run { [manager] in
                return downloadTask == manager.downloadTask
            }
            guard isExpectedTask else { return }
            await MainActor.run { [manager] in
                if totalBytesExpectedToWrite > 0 {
                    manager.delegateSetProgress(max(0, min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))))
                } else {
                    manager.delegateSetProgress(nil)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Capture values synchronously without touching MainActor state
        var currentTask: URLSessionDownloadTask?
        var updatesDir: URL!
        MainActor.assumeIsolated {
            currentTask = manager.downloadTask
            updatesDir = manager.updatesDirectory
        }
        
        guard downloadTask === currentTask else { return }
        
        let fileName = downloadTask.originalRequest?.url?.lastPathComponent ?? UUID().uuidString
        
        let moveResult = Result { try MoveDownloadedFile(from: location, named: fileName, primaryDirectory: updatesDir) }
        
        Task { @MainActor in
            // Double-check task still current after await
            guard self.manager.downloadTask === downloadTask else { return }
            
            switch moveResult {
            case .success(let url):
                self.manager.handleDownloadReady(at: url)
            case .failure(let error):
                self.manager.isDownloading = false
                self.manager.downloadProgress = nil
                self.manager.downloadTask = nil
                self.manager.status = .failed(error.readableDescription)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            let isExpectedTask: Bool = await MainActor.run { [manager] in
                return task == manager.downloadTask
            }
            guard isExpectedTask else { return }
            await MainActor.run { [manager] in
                manager.delegateClearDownloadTask()
                if let error {
                    manager.delegateSetDownloading(false)
                    manager.delegateSetProgress(nil)
                    manager.delegateFail(error)
                }
            }
        }
    }
}

private extension UpdateManager {
    @MainActor
    func delegateSetProgress(_ value: Double?) {
        downloadProgress = value
    }

    @MainActor
    func delegateSetDownloading(_ downloading: Bool) {
        isDownloading = downloading
    }

    @MainActor
    func delegateClearDownloadTask() {
        downloadTask = nil
    }

    @MainActor
    func delegateFail(_ error: Error) {
        status = .failed(error.readableDescription)
    }

    func handleDownloadReady(at url: URL) {
        downloadLocation = url
        isDownloading = false
        downloadProgress = nil
        downloadTask = nil
        if let release = currentDownloadingRelease {
            currentDownloadingRelease = nil
            availableRelease = release
        }
        status = .readyToInstall(url)
    }
}

private func MoveDownloadedFile(from location: URL, named fileName: String, primaryDirectory: URL) throws -> URL {
    let fileManager = FileManager.default
    func moveFile(from location: URL, toDirectory directory: URL, fileName: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let destination = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: location, to: destination)
        try? fileManager.removeItem(at: location)
        return destination
    }
    do {
        return try moveFile(from: location, toDirectory: primaryDirectory, fileName: fileName)
    } catch {
        let fallbackDir = fileManager.temporaryDirectory.appendingPathComponent("QuiperUpdates", isDirectory: true)
        return try moveFile(from: location, toDirectory: fallbackDir, fileName: fileName)
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}


private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let browserDownloadUrl: URL
        let name: String
    }

    let tagName: String
    let body: String?
    let htmlUrl: URL
    let assets: [Asset]
}




private extension Error {
    var readableDescription: String {
        if let localized = (self as? LocalizedError)?.errorDescription {
            return localized
        }
        return localizedDescription
    }
}
