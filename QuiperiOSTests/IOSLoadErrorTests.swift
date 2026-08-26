import Foundation
import Testing
import WebKit
@testable import QuiperiOS

/// Covers the iOS load-error state machine that mirrors macOS
/// `WebViewManager`'s failure handling: cancellations stay invisible,
/// failures keep their URL for retry, and new navigations clear the panel.
@MainActor
@Suite(.serialized)
struct IOSLoadErrorTests {

    @Test func cancellationsNeverSurface() {
        let session = makeSession()

        session.reportLoadFailure(URLError(.cancelled))

        #expect(session.loadError == nil)
    }

    @Test func navigationFailureSurfacesWithRetryURL() throws {
        let session = makeSession()
        let failedURL = try #require(URL(string: "https://engine.example.com/chat"))

        session.beginMainFrameNavigation(to: failedURL)
        session.reportLoadFailure(URLError(.cannotConnectToHost))

        let error = try #require(session.loadError)
        #expect(error.kind == .connectionUnavailable)
        #expect(error.url == failedURL)
    }

    @Test func newNavigationClearsError() throws {
        let session = makeSession()
        let failedURL = try #require(URL(string: "https://engine.example.com/chat"))
        let nextURL = try #require(URL(string: "https://engine.example.com/other"))

        session.beginMainFrameNavigation(to: failedURL)
        session.reportLoadFailure(URLError(.timedOut))
        #expect(session.loadError != nil)

        session.beginMainFrameNavigation(to: nextURL)
        #expect(session.loadError == nil)
    }

    @Test func firstTerminationAutoRecoversAndSecondSurfaces() throws {
        let session = makeSession()

        session.reportWebContentTermination()
        #expect(session.loadError == nil)

        session.reportWebContentTermination()
        let error = try #require(session.loadError)
        #expect(error.kind == .contentProcessTerminated)
    }

    @Test func retryStartsLoadingTheFailedURL() throws {
        let session = makeSession()
        let failedURL = try #require(URL(string: "https://unit-test.invalid/chat"))

        session.beginMainFrameNavigation(to: failedURL)
        session.reportLoadFailure(URLError(.cannotConnectToHost))

        session.retryFailedLoad()

        #expect(session.loadError == nil)
        #expect(session.webView.isLoading)
    }

    private func makeSession() -> WebViewSession {
        WebViewSession(
            service: Service(name: "Load Error Test", url: "https://example.com", focus_selector: ""),
            sessionIndex: 0,
            initialURL: nil,
            websiteDataStore: .nonPersistent(),
            initialBackgroundColor: .black,
            loadImmediately: false
        )
    }
}
