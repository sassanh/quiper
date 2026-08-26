import XCTest
import AppKit
import WebKit
@testable import Quiper

@MainActor
final class WebLoadErrorTests: XCTestCase {
    private func privateProperty<T>(_ object: Any, named name: String) -> T? {
        Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
    }

    func testNetworkErrorClassification() {
        XCTAssertEqual(WebLoadError(error: URLError(.timedOut)).kind, .timeout)
        XCTAssertEqual(WebLoadError(error: URLError(.dnsLookupFailed)).kind, .dnsFailure)
        XCTAssertEqual(WebLoadError(error: URLError(.cannotConnectToHost)).kind, .connectionUnavailable)
        XCTAssertEqual(WebLoadError(error: URLError(.notConnectedToInternet)).kind, .offline)
        XCTAssertEqual(WebLoadError(error: URLError(.networkConnectionLost)).kind, .connectionLost)
    }

    func testSecurityAndRoutingErrorClassification() {
        XCTAssertEqual(WebLoadError(error: URLError(.serverCertificateUntrusted)).kind, .secureConnectionFailure)
        XCTAssertEqual(WebLoadError(error: URLError(.userAuthenticationRequired)).kind, .authenticationFailure)
        XCTAssertEqual(WebLoadError(error: URLError(.httpTooManyRedirects)).kind, .redirectFailure)
        XCTAssertEqual(WebLoadError(error: URLError(.badURL)).kind, .invalidURL)
    }

    func testResourceAndFileErrorClassification() {
        XCTAssertEqual(WebLoadError(error: URLError(.resourceUnavailable)).kind, .resourceUnavailable)
        XCTAssertEqual(WebLoadError(error: URLError(.fileDoesNotExist)).kind, .fileAccessFailure)
        XCTAssertEqual(WebLoadError(error: URLError(.noPermissionsToReadFile)).kind, .fileAccessFailure)
    }

    func testUnknownErrorUsesFallbackClassification() {
        struct TestError: Error {}
        XCTAssertEqual(WebLoadError(error: TestError()).kind, .unknown)
    }

    func testFailingURLIsPreferredOverFallbackURL() {
        let failingURL = URL(string: "https://failed.example/page")!
        let fallbackURL = URL(string: "https://fallback.example/page")!
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.timedOut.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        XCTAssertEqual(WebLoadError(error: error, fallbackURL: fallbackURL).url, failingURL)
    }

    func testLegacyFailingURLStringIsStillPreferredOverFallbackURL() {
        let failingURL = URL(string: "https://legacy-failed.example/page")!
        let fallbackURL = URL(string: "https://fallback.example/page")!
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.timedOut.rawValue,
            userInfo: ["NSErrorFailingURLStringKey": failingURL.absoluteString]
        )

        XCTAssertEqual(WebLoadError(error: error, fallbackURL: fallbackURL).url, failingURL)
    }

    func testCancellationDetectionAndProcessRetryLimit() {
        XCTAssertTrue(WebLoadError.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(WebLoadError.isCancellation(URLError(.timedOut)))

        var retryState = WebProcessTerminationRetryState()
        XCTAssertTrue(retryState.shouldRetry())
        XCTAssertFalse(retryState.shouldRetry())
        retryState.reset()
        XCTAssertTrue(retryState.shouldRetry())
    }

    func testFrameLoadInterruptedByPolicyChangeIsDetected() {
        let interrupted = NSError(domain: "WebKitErrorDomain", code: 102)
        XCTAssertTrue(WebLoadError.isFrameLoadInterrupted(interrupted))
        XCTAssertFalse(WebLoadError.isFrameLoadInterrupted(URLError(.timedOut)))
        XCTAssertFalse(WebLoadError.isFrameLoadInterrupted(NSError(domain: "WebKitErrorDomain", code: 404)))

        let loadError = WebLoadError(error: interrupted)
        XCTAssertEqual(loadError.kind, .unknown, "The error itself still classifies as unknown — it must simply be filtered out")
    }

    func testErrorViewPersistsWhenSessionWrapperIsHidden() throws {
        let service = Service(name: "Service", url: "https://example.com", focus_selector: "")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        manager.updateServices([service])
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )

        let wrapper = try XCTUnwrap(webView.superview as? WebViewWrapperView)
        let errorView = try XCTUnwrap(wrapper.subviews.compactMap { $0 as? WebLoadErrorView }.first)
        wrapper.showError(WebLoadError(kind: .timeout), retryAvailable: true)

        manager.hideAll()

        XCTAssertTrue(wrapper.isHidden)
        XCTAssertTrue(wrapper.isShowingError)
        XCTAssertTrue(webView.isHidden)
        XCTAssertFalse(errorView.isHidden)

        wrapper.isHidden = false
        XCTAssertTrue(wrapper.isShowingError)
        XCTAssertTrue(webView.isHidden)
        XCTAssertFalse(errorView.isHidden)

        wrapper.showWebContent()
        XCTAssertFalse(wrapper.isShowingError)
        XCTAssertFalse(webView.isHidden)
        XCTAssertTrue(errorView.isHidden)
        manager.removeWebView(for: service, sessionIndex: 0)
    }

    func testRetryButtonIsDisabledWithoutRetryTarget() throws {
        let errorView = WebLoadErrorView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        errorView.configure(error: WebLoadError(kind: .invalidURL), retryAvailable: false)

        let retryButton: NSButton = try XCTUnwrap(privateProperty(errorView, named: "retryButton"))
        XCTAssertFalse(retryButton.isEnabled)
    }
}
