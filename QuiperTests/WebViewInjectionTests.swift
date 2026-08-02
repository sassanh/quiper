import XCTest
import AppKit
import WebKit
@testable import Quiper

@MainActor
final class WebViewInjectionTests: XCTestCase {
    func testWebViewUsesCurrentCustomCSSAndPromptSelectorWhenPassedStaleService() throws {
        let serviceID = UUID()
        let originalServices = Settings.shared.services
        defer { Settings.shared.services = originalServices }

        let css = "body { outline: 3px solid rgb(1, 2, 3); }"
        let currentService = Service(
            id: serviceID,
            name: "Test Engine",
            url: "https://example.com",
            focus_selector: "#current-prompt",
            customCSS: css
        )
        let staleService = Service(
            id: serviceID,
            name: currentService.name,
            url: currentService.url,
            focus_selector: "",
            customCSS: nil
        )
        Settings.shared.services = [currentService]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        manager.updateServices([staleService])
        let webView = manager.getOrCreateWebView(
            for: staleService,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer { manager.removeWebView(for: currentService, sessionIndex: 0) }

        let sources = webView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertTrue(sources.contains { $0.contains(css) })
        XCTAssertTrue(sources.contains { $0.contains("#current-prompt") })
    }

    func testWebViewUsesCurrentTemplateCSSAndPromptSelectorWhenPassedStaleService() throws {
        let originalServices = Settings.shared.services
        defer { Settings.shared.services = originalServices }

        guard let template = Settings.shared.defaultServiceTemplates.first(where: {
            Settings.shared.defaultCustomCSS(for: $0) != nil
                && Settings.shared.defaultPromptInputSelector(for: $0) != nil
        }) else {
            throw XCTSkip("No bundled service template contains both CSS and a prompt selector")
        }

        let serviceID = UUID()
        var currentService = template
        currentService.id = serviceID
        currentService.isEncrypted = false
        currentService.customCSS = nil
        currentService.focus_selector = ""
        currentService.templateCustomCSSSync = true
        currentService.templatePromptInputSelectorSync = true

        var staleService = currentService
        staleService.templateCustomCSSSync = false
        staleService.templatePromptInputSelectorSync = false

        Settings.shared.services = [currentService]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        manager.updateServices([staleService])
        let webView = manager.getOrCreateWebView(
            for: staleService,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer { manager.removeWebView(for: currentService, sessionIndex: 0) }

        let expectedCSS = try XCTUnwrap(Settings.shared.defaultCustomCSS(for: currentService))
        let expectedSelector = try XCTUnwrap(Settings.shared.defaultPromptInputSelector(for: currentService))
        let sources = webView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertTrue(sources.contains { $0.contains(expectedCSS) })
        XCTAssertTrue(sources.contains { $0.contains(expectedSelector) })
    }
}
