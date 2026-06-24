import XCTest
import AppKit
import Carbon
import WebKit
@testable import Quiper

@MainActor
final class MainWindowControllerTests: XCTestCase {

    func testSelectServiceWithURL() {
        // Given
        let service1 = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let service2 = Service(id: UUID(), name: "Service 2", url: "https://example.com/2", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service1, service2])
        
        // When selecting existing service
        let result1 = controller.selectService(withURL: "https://example.com/2")
        
        // Then
        XCTAssertTrue(result1)
        XCTAssertEqual(controller.activeServiceURL, "https://example.com/2")
        XCTAssertEqual(controller.currentServiceName, "Service 2")
        
        // When selecting non-existent service
        let result2 = controller.selectService(withURL: "https://example.com/3")
        
        // Then
        XCTAssertFalse(result2)
        // Should remain on previous selection
        XCTAssertEqual(controller.activeServiceURL, "https://example.com/2")
    }

    func testTrashSessionButtonInitialization() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        _ = controller.window
        
        XCTAssertNotNil(controller.trashSessionButton)
        XCTAssertEqual(controller.trashSessionButton.action, #selector(MainWindowController.closeSessionTapped(_:)))
    }

    func testToolbarButtonsTooltips() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        _ = controller.window
        
        XCTAssertEqual(controller.trashSessionButton.toolTip, "Close Current Session")
        XCTAssertEqual(controller.sessionActionsButton.toolTip, "Session Actions")
        XCTAssertEqual(controller.manualLockButton.toolTip, "Lock Engine")
        XCTAssertEqual(controller.navigationButtonGroup.backButton.toolTip, "Go Back")
        XCTAssertEqual(controller.navigationButtonGroup.forwardButton.toolTip, "Go Forward")
    }

    func testPromptHistoryButtonInitialization() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        _ = controller.window
        
        XCTAssertNotNil(controller.promptHistoryButton)
        XCTAssertEqual(controller.promptHistoryButton.toolTip, "Prompt History")
        XCTAssertEqual(controller.promptHistoryButton.action, #selector(MainWindowController.promptHistoryButtonTapped(_:)))
    }

    func testPromptHistoryRecordingToggle() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        
        // Default should follow Settings (true)
        XCTAssertTrue(controller.webViewManager.isPromptHistoryEnabled(for: service.url, sessionIndex: 0))
        
        // Override to false
        controller.webViewManager.setPromptHistoryEnabled(false, for: service.url, sessionIndex: 0)
        XCTAssertFalse(controller.webViewManager.isPromptHistoryEnabled(for: service.url, sessionIndex: 0))
        
        // Override to true
        controller.webViewManager.setPromptHistoryEnabled(true, for: service.url, sessionIndex: 0)
        XCTAssertTrue(controller.webViewManager.isPromptHistoryEnabled(for: service.url, sessionIndex: 0))
    }

    func testPromptHistoryClearing() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        
        let entry = PromptHistoryEntry(text: "Test Prompt", timestamp: Date())
        controller.webViewManager.addPromptHistoryEntry(entry, for: service.url, sessionIndex: 0)
        
        XCTAssertEqual(controller.webViewManager.getPromptHistory(for: service.url, sessionIndex: 0).count, 1)
        XCTAssertEqual(controller.webViewManager.getPromptHistory(for: service.url, sessionIndex: 0).first?.text, "Test Prompt")
        
        controller.webViewManager.clearPromptHistory(for: service.url, sessionIndex: 0)
        XCTAssertTrue(controller.webViewManager.getPromptHistory(for: service.url, sessionIndex: 0).isEmpty)
    }

    func testEscapeKeySwallowsEventWhenLoading() {
        class MockWebView: WKWebView {
            var mockIsLoading = false
            var stopLoadingCalled = false
            
            override var isLoading: Bool {
                return mockIsLoading
            }
            
            override func stopLoading() {
                stopLoadingCalled = true
            }
        }
        
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil)
        let controller = MainWindowController(services: [service])
        _ = controller.window
        
        let mockWebView = MockWebView()
        controller.webViewManager.webviewsByID[service.id] = [0: mockWebView]
        controller.activeIndicesByURL[service.url] = 0
        
        // Scenario 1: WebView is loading -> Escape key should stop loading and return nil (swallowed)
        mockWebView.mockIsLoading = true
        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        )!
        
        let resultEvent = controller.handleLocalEvent(escapeEvent)
        XCTAssertNil(resultEvent)
        XCTAssertTrue(mockWebView.stopLoadingCalled)
        
        // Scenario 2: WebView is not loading -> Escape key should not swallow event and return event itself
        mockWebView.mockIsLoading = false
        mockWebView.stopLoadingCalled = false
        
        let resultEvent2 = controller.handleLocalEvent(escapeEvent)
        XCTAssertNotNil(resultEvent2)
        XCTAssertEqual(resultEvent2, escapeEvent)
        XCTAssertFalse(mockWebView.stopLoadingCalled)
    }

    func testPromptHistorySelectionClearRecording() {
        let service = Service(id: UUID(), name: "Service 1", url: "https://example.com/1", focus_selector: "", activationShortcut: nil, preservePrompt: true)
        let controller = MainWindowController(services: [service])
        
        // 1. When selectionClear trigger is disabled (default):
        Settings.shared.promptHistoryRecordOnSelectionClear = false
        controller.webViewManager.clearPromptHistory(for: service.url, sessionIndex: 0)
        
        let payloadDisabled: [String: Any] = [
            "text": "new text",
            "isContentEditable": false,
            "start": 8,
            "end": 8,
            "wasSent": true,
            "wasSentText": "previous select-all prompt",
            "clearType": "selectionClear"
        ]
        
        controller.webViewManager.mockReceiveInputStateMessage(payload: payloadDisabled, service: service, sessionIndex: 0)
        XCTAssertTrue(controller.webViewManager.getPromptHistory(for: service.url, sessionIndex: 0).isEmpty)
        
        // 2. When selectionClear trigger is enabled:
        Settings.shared.promptHistoryRecordOnSelectionClear = true
        let payloadEnabled: [String: Any] = [
            "text": "new text",
            "isContentEditable": false,
            "start": 8,
            "end": 8,
            "wasSent": true,
            "wasSentText": "previous select-all prompt",
            "clearType": "selectionClear"
        ]
        
        controller.webViewManager.mockReceiveInputStateMessage(payload: payloadEnabled, service: service, sessionIndex: 0)
        let history = controller.webViewManager.getPromptHistory(for: service.url, sessionIndex: 0)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.text, "previous select-all prompt")
        
        // Cleanup settings to default false
        Settings.shared.promptHistoryRecordOnSelectionClear = false
    }
}
