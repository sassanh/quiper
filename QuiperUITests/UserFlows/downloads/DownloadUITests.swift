import XCTest

/// Tests for the webview download functionality.
/// Downloads are triggered when WKWebView encounters content it cannot display inline
/// or when a navigation action requests a download.
final class DownloadUITests: BaseUITest {
    
    let fileManager = FileManager.default
    
    /// Unique temp directory for test files
    lazy var tempDir: URL = {
        return fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }()
    
    /// Test HTML page that triggers a download
    lazy var downloadTestFile: URL = {
        return tempDir.appendingPathComponent("test-custom-engine-1.html")
    }()
    
    /// Unique download filename to avoid conflicts with other tests
    lazy var downloadFilename: String = {
        return "quiper-test-download-\(UUID().uuidString).txt"
    }()
    
    /// Expected destination in User Downloads folder
    lazy var downloadsDir: URL = {
        // FileManager.urls(for: .downloadsDirectory) returns the Sandbox container path in the Runner.
        // We need the ACTUAL user Downloads directory to verify the file the App (which writes to real Downloads) created.
        let userName = NSUserName()
        return URL(fileURLWithPath: "/Users/\(userName)/Downloads")
    }()
    
    override var launchArguments: [String] {
        return [
            "--uitesting",
            "--test-custom-engines=1",
            "--test-custom-engines-path=\(tempDir.path)"
        ]
    }
    
    override func setUp() {
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            
            // Create HTML page with a download link using data: URI
            // data: URIs bypass network requirements while still triggering download behavior
            let htmlContent = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Download Test Page</title>
            </head>
            <body>
                <h1 id="status">Ready</h1>
                <a id="downloadLink">Download Test File</a>
                <script>
                    window.addEventListener('load', function() {
                        const content = "Hello from Quiper download test!";
                        const blob = new Blob([content], { type: 'text/plain' });
                        const url = URL.createObjectURL(blob);
                        const link = document.getElementById('downloadLink');
                        link.href = url;
                        link.download = "\(downloadFilename)";
                        document.getElementById('status').textContent = 'Loaded';
                    });
                </script>
            </body>
            </html>
            """
            try htmlContent.write(to: downloadTestFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to set up test files: \(error)")
        }
        
        super.setUp()
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? fileManager.removeItem(at: tempDir)
        
        // Clean up downloaded file from Downloads folder
        let downloadedFile = downloadsDir.appendingPathComponent(downloadFilename)
        try? fileManager.removeItem(at: downloadedFile)
        
        super.tearDown()
    }
    
    // MARK: - Tests
    
    /// Test that clicking a download link triggers a download to the Downloads folder.
    func testDownloadLinkTriggersDownload() {
        ensureWindowVisible()
        
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0), "WebView should exist")
        
        // Wait for page to load - the WebView's accessibility label is set to the page title
        let loadedPredicate = NSPredicate(format: "label CONTAINS 'Download Test Page'")
        let loadExpectation = XCTNSPredicateExpectation(predicate: loadedPredicate, object: webView)
        let loadResult = XCTWaiter().wait(for: [loadExpectation], timeout: 10.0)
        XCTAssertEqual(loadResult, .completed, "Page should load with expected title")
        
        // Identify existing files to differentiate new download
        let initialFiles = (try? fileManager.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil)) ?? []
        let initialFileSet = Set(initialFiles.map { $0.path })
        
        // Find and click the download link inside the WebView
        let downloadLink = webView.links["Download Test File"]
        XCTAssertTrue(downloadLink.waitForExistence(timeout: 5.0), "Download link should exist in the WebView")
        downloadLink.click()
        
        
        // Wait for download to complete (a new file should appear)
        var capturedFile: URL?
        let downloadExpectation = expectation(description: "File should be downloaded")
        
        DispatchQueue.global().async {
            let maxWait = 15.0
            let pollInterval = 0.5
            var elapsed = 0.0
            
            // Log directory info
            var isDir: ObjCBool = false
            let exists = self.fileManager.fileExists(atPath: self.downloadsDir.path, isDirectory: &isDir)
            NSLog("Checking downloads dir: \(self.downloadsDir.path). Exists: \(exists), IsDir: \(isDir.boolValue)")

            while elapsed < maxWait {
                if let currentFiles = try? self.fileManager.contentsOfDirectory(at: self.downloadsDir, includingPropertiesForKeys: nil) {
                     for file in currentFiles {
                         if !initialFileSet.contains(file.path) && file.lastPathComponent != ".DS_Store" {
                             capturedFile = file
                             downloadExpectation.fulfill()
                             return
                         }
                     }
                }
                Thread.sleep(forTimeInterval: pollInterval)
                elapsed += pollInterval
            }
        }
        
        waitForExpectations(timeout: 17.0)
        
        guard let downloadedFile = capturedFile else {
            XCTFail("No new file appeared in downloads folder")
            return
        }
        NSLog("Found downloaded file at: \(downloadedFile.path)")
        
        // Clean up
        defer { try? fileManager.removeItem(at: downloadedFile) }

        // Verify content
        if let downloadedContent = try? String(contentsOf: downloadedFile, encoding: .utf8) {
            XCTAssertEqual(downloadedContent, "Hello from Quiper download test!", "Downloaded content should match expected")
        } else {
            // Check that file is non-empty at minimum
            let attributes = try? fileManager.attributesOfItem(atPath: downloadedFile.path)
            let fileSize = attributes?[.size] as? Int ?? 0
            XCTAssertGreaterThan(fileSize, 0, "Downloaded file should not be empty")
        }
    }
    
    // MARK: - Helpers
    
    private func ensureWindowVisible() {
        let sessionSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector")
        
        if !sessionSelector.firstMatch.exists {
            let statusItem = app.statusItems.firstMatch
            if statusItem.waitForExistence(timeout: 5.0) {
                statusItem.click()
                let showItem = app.menuItems["Show Quiper"]
                if showItem.waitForExistence(timeout: 2.0) {
                    showItem.click()
                }
            }
        }
        
        if !waitForElement(sessionSelector.firstMatch, timeout: 5.0) {
            XCTFail("Main window content (SessionSelector) must be visible for tests")
        }
    }
}
