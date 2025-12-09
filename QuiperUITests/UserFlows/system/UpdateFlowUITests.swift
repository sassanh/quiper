import XCTest

class UpdateFlowUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // We use check-for-updates to trigger the real flow, but since we are 0.0.0
        // and GitHub has > 0.0.0, it will find an update.
        // We also need to ensure the App activation policy allows windows to be seen easily.
        // Use mock update to ensure reliable testing in CI without network/rate limits.
        return ["--uitesting", "--enable-automatic-updates", "--mock-update-available"]
    }

    override func setUp() {
        super.setUp()
        // Override setup to add specific launch argument
        // The launch arguments are now provided by the 'launchArguments' computed property.
        app.launch()
    }

    func testUpdateFlowDoesNotCrashAndShowsPrompt() throws {
        // The app runs as an accessory app, so we must bring it to the foreground
        // by interacting with the status bar item to make windows accessible to XCTest.
        
        // 1. Click Status Item to open menu
        let statusItem = app.statusItems.firstMatch
        if statusItem.waitForExistence(timeout: 5.0) {
            statusItem.click()
        } else {
            XCTFail("Status item not found")
        }
        
        // 2. Click "Show Quiper" to activate the app
        let showAppItem = app.menuItems["Show Quiper"]
        if showAppItem.waitForExistence(timeout: 2.0) {
            showAppItem.click()
        } else {
            // If "Show Quiper" isn't there, maybe it's already active or title is different?
            // But proceeding anyway to check for Update Prompt.

        }

        // 3. Wait for the main update view to appear
        // The app should automatically check for updates on launch because of the launch argument
        // We expect the "Software Update" window (or alert) to appear eventually
        
        // Wait for the main update view to appear
        let updateView = app.descendants(matching: .any)["UpdatePromptMainView"]
        let exists = updateView.waitForExistence(timeout: 10.0)
        
        XCTAssertTrue(exists, "Update prompt view (UpdatePromptMainView) should appear on launch")
        
        // 4. Verify Download Flow
        let downloadButton = app.buttons["Download Update"]
        XCTAssertTrue(downloadButton.exists, "Download Update button should be present")
        
        // Click Download
        downloadButton.click()
        
        // 5. Verify UI enters downloading state
        let downloadingText = app.staticTexts["Downloading update…"]
        let startedDownloading = downloadingText.waitForExistence(timeout: 5.0)
        XCTAssertTrue(startedDownloading, "UI should show 'Downloading update…' after clicking download")
        
        // 6. Wait for Download to Finish / "Install Update" to appear
        // This involves network usage, so we need a generous timeout.
        let installButton = app.buttons["Install Update"]
        // Polling loop to check for failure while waiting
        var downloadCompleted = false
        let hasFailed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Update failed'")).firstMatch
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 120.0 {
            if installButton.exists {
                downloadCompleted = true
                break
            }
            if hasFailed.exists {
                XCTFail("Update download failed in UI: \(hasFailed.label)")
                return
            }
            sleep(1)
        }
        
        XCTAssertTrue(downloadCompleted, "Should eventually show 'Install Update' button")
        
        // 7. Click Install
        installButton.click()
        
        // 8. Verify Installation Progress & Completion
        let installingText = app.staticTexts["Installing update…"]
        let relaunchButton = app.buttons["Relaunch Now"]
        let failedText = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Update failed'")).firstMatch
        
        // We wait for arguably the final state, but check for intermediate/failure states
        let installTimeout = 60.0
        let installStart = Date()
        var sawInstalling = false
        var success = false
        
        while Date().timeIntervalSince(installStart) < installTimeout {
            if relaunchButton.exists {
                success = true
                break
            }
            if failedText.exists {
                XCTFail("Update installation failed: \(failedText.label)")
                return
            }
            if installingText.exists {
                if !sawInstalling {
                    sawInstalling = true
                }
            }
            sleep(1)
        }
        
        XCTAssertTrue(success, "Should eventually show 'Relaunch Now' button after installation")
    }
}
