import XCTest

extension BaseUITest {
    
    /// Adds a custom service with the given name and URL.
    /// Assumes Settings is already open.
    func addCustomService(name: String, url: String) {
        let addButton = app.descendants(matching: .any).matching(identifier: "Add Service").firstMatch
        XCTAssertTrue(waitForElement(addButton, timeout: 5), "Add Service button should exist")
        
        addButton.click()
        
        let blankServiceMenuItem = app.menuItems["Blank Service"]
        XCTAssertTrue(waitForElement(blankServiceMenuItem, timeout: 2), "Blank Service menu item should appear")
        blankServiceMenuItem.click()
        // Wait for name field to be ready
        let nameField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(waitForElement(nameField, timeout: 3), "Name text field should exist")
        
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(name)
        
        let urlField = app.textFields.element(boundBy: 1)
        XCTAssertTrue(waitForElement(urlField, timeout: 3), "URL text field should exist")
        
        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeText(url)
    }
    
    /// Finds a record button within a cell/element using robust filtering (Approach C).
    /// Filters out Delete/Trash buttons and returns the Nth valid record button.
    func findRecordButton(in container: XCUIElement, index: Int = 0) -> XCUIElement? {
        // Get all buttons in the container
        let buttons = container.buttons.allElementsBoundByIndex
        
        // Filter out known non-record buttons
        let recordCandidates = buttons.filter { btn in
            let label = btn.label
            return label != "Delete action" &&
                   label != "Delete" &&
                   label != "Trash" &&
                   label != "Top" &&     // Reorder buttons
                   label != "Bottom" &&  // Reorder buttons
                   label != "Reset to Default" // Clear/Reset buttons matching "record" if any? 
                   // Ideally we look for what IS, or what IS NOT.
                   // Approach C was "NOT Delete".
        }
        
        if index < recordCandidates.count {
            return recordCandidates[index]
        }
        
        return nil
    }
    
    /// Finds a button with a specific identifier within a container.
    func findButton(in container: XCUIElement, withIdentifier identifier: String, index: Int = 0) -> XCUIElement? {
        let buttons = container.buttons.matching(identifier: identifier).allElementsBoundByIndex
        if index < buttons.count {
            return buttons[index]
        }
        return nil
    }
    
    /// Creates a temporary file with the Key Logger HTML content and returns its file URL.
    func createKeyLoggerFile() -> URL {
        let htmlContent = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Key Logger</title>
        </head>
        <body>
            <h1>Key Logger</h1>
            <div id="log">Waiting for input...</div>
            <script>
                document.addEventListener('keydown', (event) => {
                    const keys = [];
                    if (event.metaKey) keys.push('Cmd');
                    if (event.ctrlKey) keys.push('Ctrl');
                    if (event.altKey) keys.push('Opt');
                    if (event.shiftKey) keys.push('Shift');
                    keys.push(event.key.toUpperCase());
                    
                    const keyString = keys.join('+');
                    document.getElementById('log').innerText = keyString;
                });
            </script>
        </body>
        </html>
        """
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("key_logger.html")
        
        try? htmlContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
