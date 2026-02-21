import XCTest

final class ScreenshotGenerator: BaseUITest {
    
    private let questions = [
        "Give me a one-sentence fun fact about space.",
        "What is the most joyful sound in the world?",
        "If you were a snack, what would you be?",
        "Tell me a one-liner joke about a programmer.",
        "What's the best topping for a pancake?",
        "Describe a sunset in one creative sentence.",
        "What would a cloud taste like if it were a candy?",
        "If you could be any mythical creature, which one would you choose?",
        "What's the funniest thing a toddler could say?",
        "Give me a one-sentence recipe for happiness.",
        "Which is cooler: ninjas or pirates?",
        "What's your favorite dance move?",
        "If you had a pet dragon, what would you name it?",
        "What's the best part about being a robot?",
        "Tell me a silly name for a squirrel.",
        "If music was a smell, what would jazz smell like?",
        "What's the most underrated superpower?",
        "If you were a fruit, which one would you be?",
        "Give me a one-sentence plot for a movie about a brave toaster.",
        "What's the best way to win a thumb war?"
    ]
    
    private var isInteractive = false

    override func setUpWithError() throws {
        // Skip these tests in normal test flows (CI, etc.)
        // They should only run when explicitly triggered via generate-screenshots.sh
        guard ProcessInfo.processInfo.arguments.contains("--screenshot-mode") else {
            throw XCTSkip("Skipping screenshot generation in normal test flow. Use generate-screenshots.sh to run these.")
        }
        
        // Correctly detect interactive mode from test name (assigned by xcodebuild -only-testing)
        if self.name.contains("testGenerateScreenshotsInteractive") {
            isInteractive = true
        }
    }
    
    override var launchArguments: [String] {
        var args = ["--uitesting", "--screenshot-mode"]
        if isInteractive {
            args.append("--interactive-mode")
        }
        return args
    }
    
    private var screenshotDir: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let url = downloads.appendingPathComponent("quiper-screenshots")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            print("ERROR: Could not create directory \(url.path): \(error)")
        }
        return url
    }
    
    func testGenerateScreenshotsNonInteractive() throws {
        try runScreenshotFlow()
    }

    func testGenerateScreenshotsInteractive() throws {
        // App Controller shows prompt if --interactive-mode is passed
        let startButton = app.buttons["Go"]
        if startButton.waitForExistence(timeout: 10) {
            startButton.waitForNonExistence(timeout: 20);
        }
        
        try runScreenshotFlow()
    }
    
    private func saveScreenshot(name: String, element: XCUIElement) {
        let screenshot = element.screenshot()
        let url = screenshotDir.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Failed to save screenshot to \(url.path): \(error)")
        }
    }
    
    private func waitForPageLoad(timeout: TimeInterval = 300) {
        print("Waiting for page load (event-driven)...")
        
        let overlay = app.windows["Quiper Overlay"]
        let loadingIndicator = overlay.otherElements["LoadingIndicator"]
        
        let doesNotExist = NSPredicate(format: "exists == false")
        expectation(for: doesNotExist, evaluatedWith: loadingIndicator, handler: nil)
        
        let titleStable = NSPredicate(format: "value != '-' AND value != '' AND value != 'Loading...'")
        let titleLabel = overlay.staticTexts.firstMatch
        expectation(for: titleStable, evaluatedWith: titleLabel, handler: nil)
        
        waitForExpectations(timeout: timeout)
        
        print("Page load detected. Waiting 3s for final rendering stability...")
        wait(1.0) 
    }
    
    private func requestUserConfirmation(name: String) {
        guard isInteractive else {
            print("Non-interactive mode: Waiting 20s for response...")
            wait(20.0)
            return
        }
        
        print("INTERACTIVE: Requesting confirmation for '\(name)'")
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("app.sassanh.quiper.ShowCapturePrompt"),
            object: name,
            userInfo: nil,
            deliverImmediately: true
        )
        
        let takeButton = app.buttons["TakeScreenshotButton"]
        
        // Wait for user to click the button
        if takeButton.waitForExistence(timeout: 30) {
            let doesNotExist = NSPredicate(format: "exists == false")
            expectation(for: doesNotExist, evaluatedWith: takeButton, handler: nil)
            waitForExpectations(timeout: 600) // 10 minutes max per step
            print("INTERACTIVE: Human confirmed. Capturing...")
        } else {
            print("WARNING: TakeScreenshotButton did not appear. Capturing anyway.")
        }
    }
    
    private func runScreenshotFlow() throws {
        ensureWindowVisible()
        let overlayWindow = app.windows["Quiper Overlay"]
        let engines = ["Gemini", "Claude", "Grok", "ChatGPT", "X", "Ollama", "Google"]
        let selectorDialog = app.dialogs.element

        // 1. 🔥 Pre-warm engines: click each one once to trigger loading
        print("🔥 Pre-warming engines...")
        var selector = overlayWindow.radioButtons[engines[0]]
        for engine in engines {
            selector.hover()
            let engineButton = selectorDialog.radioButtons[engine]

            if engineButton.waitForExistence(timeout: 10) {
                print("   Warming up \(engine)...")

                engineButton.click()
                selector = overlayWindow.radioButtons[engine]
                wait(0.2)
            } else {
                XCTFail("FAILED to warm up \(engine)")
            }
        }

        // 2. 🚀 Main screenshot loop
        print("🚀 Starting screenshot sequence...")
        var shuffledQuestions = questions.shuffled()
        
        for engine in engines {
            selector.hover()
            let engineButton = selectorDialog.radioButtons[engine]

            print("Processing engine: \(engine)")
            
            if engineButton.waitForExistence(timeout: 10) {
                print("   Found button for \(engine). Clicking...")
                engineButton.click()
                selector = overlayWindow.radioButtons[engine]
                waitForPageLoad()
                
                if let question = shuffledQuestions.popLast() {
                    print("   Typing question for \(engine): \(question)")
                    app.typeText(question)
                    app.typeKey(.enter, modifierFlags: [])
                    
                    requestUserConfirmation(name: "main_\(engine.lowercased())")
                }
                
                saveScreenshot(name: "main_\(engine.lowercased())", element: overlayWindow)
            } else {
                XCTFail("Could not find button for \(engine) even after expansion attempt.")
            }
        }

        selector.hover()
        var engineButton = selectorDialog.radioButtons[engines[2]]
        engineButton.click()
        
        print("Processing feature_selectors...")
        requestUserConfirmation(name: "feature_selectors")
        
        selector.hover()
        wait(0.2)
        // Capture the whole app to include the expanded panel (child window)
        saveScreenshot(name: "feature_selectors", element: app)
        
        print("Processing hero...")
        selector.hover()
        engineButton = selectorDialog.radioButtons[engines[0]]

        if engineButton.waitForExistence(timeout: 10) {
            print("   Found first engine for hero screenshot. Clicking...")
            engineButton.click()
            waitForPageLoad()
            requestUserConfirmation(name: "hero")
            saveScreenshot(name: "hero", element: overlayWindow)
        } else {
            XCTFail("Could not find first engine for hero screenshot.")
        }
        
        openSettings()
        let currentSettingsWindow = app.windows["Quiper Settings"]
        
        let tabs = [
            ("General", "settings_general"),
            ("Engines", "settings_engines"),
            ("Appearance", "settings_appearance"),
            ("Shortcuts", "settings_shortcuts"),
            ("Updates", "settings_updates")
        ]
        
        for (tab, fileName) in tabs {
            switchToSettingsTab(tab)
            wait(0.2)
            requestUserConfirmation(name: fileName)
            saveScreenshot(name: fileName, element: currentSettingsWindow)
            
            if tab == "Shortcuts" {
                requestUserConfirmation(name: "settings_shortcuts_hotkeys")
                saveScreenshot(name: "settings_shortcuts_hotkeys", element: currentSettingsWindow)
            }
        }
    }
}
