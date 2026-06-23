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
}
