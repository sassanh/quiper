import XCTest
import AppKit
import WebKit
@testable import Quiper

@MainActor
final class SessionSelectorTooltipTests: XCTestCase {
    func testBlankTooltipsAreRemoved() {
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 1

        control.setToolTip("Title", forSegment: 0)
        XCTAssertEqual(control.toolTip(forSegment: 0), "Title")

        control.setToolTip("  \n  ", forSegment: 0)
        XCTAssertNil(control.toolTip(forSegment: 0))
    }

    func testClosedSegmentRejectsStaleCachedTooltip() {
        let delegate = SessionTooltipSelectorDelegate(instantiatedSegments: [])
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 1
        control.selectorDelegate = delegate
        control.alwaysShowTooltips = true
        control.requiresInstantiatedSegmentForTooltip = true
        control.setToolTip("Previously open", forSegment: 0)

        XCTAssertFalse(control.shouldShowTooltip(forSegment: 0))
    }

    func testOpenSegmentAllowsTooltip() {
        let delegate = SessionTooltipSelectorDelegate(instantiatedSegments: [0])
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 1
        control.selectorDelegate = delegate
        control.alwaysShowTooltips = true
        control.requiresInstantiatedSegmentForTooltip = true
        control.setToolTip("Open session", forSegment: 0)

        XCTAssertTrue(control.shouldShowTooltip(forSegment: 0))
    }

    func testInstantiationRequirementIsOptIn() {
        let delegate = SessionTooltipSelectorDelegate(instantiatedSegments: [])
        let control = SegmentedControl(frame: .zero)
        control.segmentCount = 1
        control.selectorDelegate = delegate
        control.alwaysShowTooltips = true
        control.setToolTip("Service title", forSegment: 0)

        XCTAssertTrue(control.shouldShowTooltip(forSegment: 0))
    }

    func testOpenUntitledSessionsUseSessionNumber() {
        XCTAssertEqual(
            MainWindowController.sessionTooltipTitle(pageTitle: nil, sessionIndex: 0),
            "Session 1"
        )
        XCTAssertEqual(
            MainWindowController.sessionTooltipTitle(pageTitle: "  ", sessionIndex: 9),
            "Session 0"
        )
    }

    func testOpenTitledSessionUsesTrimmedPageTitle() {
        XCTAssertEqual(
            MainWindowController.sessionTooltipTitle(
                pageTitle: "  Example page  \n",
                sessionIndex: 0
            ),
            "Example page"
        )
    }

    func testPersistedTitleIsUsedWhenCurrentTitleIsUnavailable() {
        XCTAssertEqual(
            MainWindowController.sessionTooltipTitle(
                pageTitle: nil,
                fallbackTitle: "  Restored page  ",
                sessionIndex: 1
            ),
            "Restored page"
        )
    }

    func testCurrentTitleTakesPrecedenceOverPersistedTitle() {
        XCTAssertEqual(
            MainWindowController.sessionTooltipTitle(
                pageTitle: "Current page",
                fallbackTitle: "Restored page",
                sessionIndex: 1
            ),
            "Current page"
        )
    }

    func testLazySessionRetainsTitleWithoutLoading() {
        let service = Service(
            id: UUID(),
            name: "Service",
            url: "https://example.com",
            focus_selector: "",
            activationShortcut: nil
        )
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: containerView)
        manager.updateServices([service])

        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 1,
            dragArea: nil,
            targetURL: "https://example.com/restored",
            restoredTitle: "  Restored page  ",
            loadImmediately: false
        )

        XCTAssertNil(webView.url)
        XCTAssertEqual(manager.sessionTitle(for: service, sessionIndex: 1), "Restored page")
        XCTAssertEqual(manager.getOpenSessionTitlesState()[service.url]?[1], "Restored page")

        manager.removeWebView(for: service, sessionIndex: 1)
        XCTAssertNil(manager.sessionTitle(for: service, sessionIndex: 1))
        XCTAssertNil(manager.getOpenSessionTitlesState()[service.url]?[1])
    }

    func testLazyRestoredTitlePopulatesBothSelectorCaches() {
        let service = Service(
            id: UUID(),
            name: "Service",
            url: "https://example.com",
            focus_selector: "",
            activationShortcut: nil
        )
        let controller = MainWindowController(services: [service])
        _ = controller.window
        let sessionIndex = 1
        let segment = controller.segmentIndex(forSession: sessionIndex)

        _ = controller.webViewManager.getOrCreateWebView(
            for: service,
            sessionIndex: sessionIndex,
            dragArea: controller.dragArea,
            targetURL: "https://example.com/restored",
            restoredTitle: "Restored page",
            loadImmediately: false
        )
        controller.updateSessionSelector()

        XCTAssertEqual(controller.sessionSelector?.toolTip(forSegment: segment), "Restored page")
        XCTAssertEqual(controller.collapsibleSessionSelector?.tooltips[segment], "Restored page")
    }

    func testRemovingSessionClearsBothSelectorCaches() {
        let service = Service(
            id: UUID(),
            name: "Service",
            url: "https://example.com",
            focus_selector: "",
            activationShortcut: nil
        )
        let controller = MainWindowController(services: [service])
        _ = controller.window
        let sessionIndex = 1
        let segment = controller.segmentIndex(forSession: sessionIndex)
        guard let sessionSelector = controller.sessionSelector,
              let collapsibleSessionSelector = controller.collapsibleSessionSelector else {
            XCTFail("Expected both session selectors to be initialized")
            return
        }

        controller.updateSessionSelector()
        XCTAssertNil(sessionSelector.toolTip(forSegment: segment))
        XCTAssertNil(collapsibleSessionSelector.tooltips[segment])

        _ = controller.getOrCreateWebview(for: service, sessionIndex: sessionIndex)
        controller.updateSessionTooltip(for: service, sessionIndex: sessionIndex)
        XCTAssertNotNil(sessionSelector.toolTip(forSegment: segment))
        XCTAssertNotNil(collapsibleSessionSelector.tooltips[segment])

        controller.removeWebViewAndCleanObserver(for: service, sessionIndex: sessionIndex)
        XCTAssertNil(sessionSelector.toolTip(forSegment: segment))
        XCTAssertNil(collapsibleSessionSelector.tooltips[segment])
    }
}

@MainActor
private final class SessionTooltipSelectorDelegate: CollapsibleSelectorDelegate {
    private let instantiatedSegments: Set<Int>

    init(instantiatedSegments: Set<Int>) {
        self.instantiatedSegments = instantiatedSegments
    }

    func segmentedControl(_ control: SegmentedControl, isInstantiated index: Int) -> Bool {
        instantiatedSegments.contains(index)
    }
}
