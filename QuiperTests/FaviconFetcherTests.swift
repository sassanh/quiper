import XCTest
@testable import Quiper

final class FaviconFetcherTests: XCTestCase {

    // MARK: - normalizeURL Tests

    func testNormalizeURL_AddsHttpsByDefault() {
        let url = FaviconFetcher.normalizeURL("google.com")
        XCTAssertEqual(url?.absoluteString, "https://google.com")
    }

    func testNormalizeURL_PreservesHttps() {
        let url = FaviconFetcher.normalizeURL("https://apple.com")
        XCTAssertEqual(url?.absoluteString, "https://apple.com")
    }

    func testNormalizeURL_PreservesHttp() {
        let url = FaviconFetcher.normalizeURL("http://example.com")
        XCTAssertEqual(url?.absoluteString, "http://example.com")
    }

    func testNormalizeURL_TrimsWhitespace() {
        let url = FaviconFetcher.normalizeURL("   github.com   ")
        XCTAssertEqual(url?.absoluteString, "https://github.com")
    }

    func testNormalizeURL_AddsHttpForLocalhost() {
        let url = FaviconFetcher.normalizeURL("localhost:8080")
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:8080")
    }

    func testNormalizeURL_AddsHttpForIPv4Local() {
        let url = FaviconFetcher.normalizeURL("127.0.0.1:8000")
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:8000")
    }

    func testNormalizeURL_ForcesIPv4ForLocalhostWithExistingScheme() {
        let url = FaviconFetcher.normalizeURL("http://localhost:3000")
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:3000")
    }

    func testNormalizeURL_ForcesIPv4ForLocalhostWithHttpsScheme() {
        let url = FaviconFetcher.normalizeURL("https://localhost:4000")
        XCTAssertEqual(url?.absoluteString, "https://127.0.0.1:4000")
    }

    func testNormalizeURL_EmptyStringReturnsNil() {
        let url = FaviconFetcher.normalizeURL("   ")
        XCTAssertNil(url)
    }

    // MARK: - isLocalHost Tests

    func testIsLocalHost_WithLocalhost() {
        XCTAssertTrue(FaviconFetcher.isLocalHost("localhost"))
        XCTAssertTrue(FaviconFetcher.isLocalHost("LOCALHOST"))
    }

    func testIsLocalHost_WithIPv4() {
        XCTAssertTrue(FaviconFetcher.isLocalHost("127.0.0.1"))
    }

    func testIsLocalHost_WithLocalDomain() {
        XCTAssertTrue(FaviconFetcher.isLocalHost("myapp.local"))
        XCTAssertTrue(FaviconFetcher.isLocalHost("MYAPP.LOCAL"))
    }

    func testIsLocalHost_WithPublicDomain() {
        XCTAssertFalse(FaviconFetcher.isLocalHost("google.com"))
        XCTAssertFalse(FaviconFetcher.isLocalHost("192.168.1.1"))
    }

    // MARK: - isHighRes Tests

    @MainActor
    func testIsHighRes_WithLowResImage() {
        // Create a 32x32 image
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmapData = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapData.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to generate test image")
            return
        }

        let base64 = pngData.base64EncodedString()
        XCTAssertFalse(FaviconFetcher.isHighRes(base64))
    }

    @MainActor
    func testIsHighRes_WithHighResImage() {
        // Create a 128x128 image
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 128, height: 128).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmapData = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapData.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to generate test image")
            return
        }

        let base64 = pngData.base64EncodedString()
        XCTAssertTrue(FaviconFetcher.isHighRes(base64))
    }

    @MainActor
    func testIsHighRes_WithInvalidBase64() {
        XCTAssertFalse(FaviconFetcher.isHighRes("invalid-base64"))
    }
}
