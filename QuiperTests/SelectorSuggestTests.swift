import XCTest
import AppKit
@testable import Quiper

@MainActor
final class SelectorSuggestTests: XCTestCase {
    func testCandidatesSelectProgressivelyDeeperAncestors() {
        let path = [
            SelectorElementDescriptor(tag: "html", segment: "html"),
            SelectorElementDescriptor(tag: "body", segment: "body"),
            SelectorElementDescriptor(tag: "div", segment: "div#main"),
            SelectorElementDescriptor(tag: "button", segment: "button.submit"),
        ]
        XCTAssertEqual(
            SelectorSuggest.candidates(for: path),
            [
                "div#main",
                "div#main > button.submit",
            ]
        )
    }

    func testCandidatesKeepBodyLeaf() {
        let path = [
            SelectorElementDescriptor(tag: "html", segment: "html"),
            SelectorElementDescriptor(tag: "body", segment: "body"),
        ]
        XCTAssertEqual(SelectorSuggest.candidates(for: path), ["body"])
    }

    func testCandidatesEmptyPathYieldsNone() {
        XCTAssertTrue(SelectorSuggest.candidates(for: []).isEmpty)
    }

    func testDescriptorParsesPickerPayload() {
        let descriptor = SelectorElementDescriptor(dictionary: [
            "tag": "button",
            "segment": "button[data-testid=\"submit\"]",
        ])
        XCTAssertEqual(
            descriptor,
            SelectorElementDescriptor(tag: "button", segment: "button[data-testid=\"submit\"]")
        )
    }

    func testDescriptorRejectsEmptySegment() {
        XCTAssertNil(SelectorElementDescriptor(dictionary: ["tag": "div", "segment": ""]))
        XCTAssertNil(SelectorElementDescriptor(dictionary: ["tag": "div"]))
    }

    func testHideRule() {
        XCTAssertEqual(
            SelectorSuggest.hideRule(for: "div#main > button.submit"),
            "div#main > button.submit { display: none !important; }"
        )
    }

    func testSuggestTitleItemDisabledForEphemeral() throws {
        let service = Service(
            id: UUID(),
            name: "Test Engine",
            url: "https://example.com",
            focus_selector: "",
            activationShortcut: nil
        )
        let controller = MainWindowController(services: [service])
        _ = controller.window
        _ = controller.webViewManager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        func suggestItem() throws -> NSMenuItem {
            let menu = controller.makeTitleContextMenu()
            return try XCTUnwrap(menu.items.first(where: { $0.title == "Suggest Selector..." }))
        }
        XCTAssertTrue(try suggestItem().isEnabled)
        controller.createQuiperPrivateTemporarySession()
        XCTAssertFalse(try suggestItem().isEnabled)
    }

    func testDialogHugsContent() throws {
        let controller = SelectorSuggestWindowController()
        controller.present(
            candidates: ["div#main", "div#main > button.submit"],
            parentWindow: nil
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        let stack = try XCTUnwrap(controller.selectorContentStack)
        XCTAssertFalse(stack.hasAmbiguousLayout)
        XCTAssertEqual(window.contentLayoutRect.height, stack.fittingSize.height, accuracy: 2)
        let buttonRow = try XCTUnwrap(stack.arrangedSubviews.last)
        XCTAssertEqual(buttonRow.frame.maxX, stack.bounds.width - 20, accuracy: 1)
        controller.dismissWithoutCallback()
    }

    func testPickerScriptsExposeExpectedHooks() {
        let startScript = WebScripts.makeSelectorPickerStartScript()
        XCTAssertTrue(startScript.contains("quiperSelectorPicker"))
        XCTAssertTrue(startScript.contains("__quiper-selector-hover"))
        XCTAssertFalse(startScript.contains("style.outline"))
        XCTAssertTrue(startScript.contains("data-testid"))
        XCTAssertFalse(startScript.contains("nth-of-type"))
        XCTAssertFalse(startScript.contains("nth-child"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewScript(selector: "button").contains("querySelectorAll"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewScript(selector: "button").contains("scrollIntoView"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewScript(selector: "button", scrollIntoView: false).contains("var shouldScroll = false"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewScript(selector: "button").contains("__quiper-selector-shield"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewScript(selector: "button").contains("pointer-events:none"))
        XCTAssertTrue(WebScripts.makeSelectorPreviewClearScript().contains("__quiper-selector-shield"))
    }
}
