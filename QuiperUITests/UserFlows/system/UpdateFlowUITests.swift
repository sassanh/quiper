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
        // 5. Verify UI enters downloading state
        // Use an expectation loop because mock download might be too fast and skip straight to 'Install Update'
        let downloadingText = app.staticTexts["Downloading update…"]
        let installUpdatesButton = app.buttons["Install Update"]
        
        let downloadingOrReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: downloadingText)
        let readyToInstall = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: installUpdatesButton)
        
        // Wait for either state
        let result = XCTWaiter().wait(for: [downloadingOrReady, readyToInstall], timeout: 5.0, enforceOrder: false)
        
        XCTAssertTrue(result == .completed || installUpdatesButton.exists, "UI should show downloading or ready state")
        
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
