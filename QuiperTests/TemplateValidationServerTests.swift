import XCTest
@testable import Quiper

final class TemplateValidationServerTests: XCTestCase {
    func testProductionBundleCannotStartValidationServer() {
        XCTAssertFalse(
            TemplateValidationServer.canStart(
                bundleIdentifier: "app.sassanh.quiper.Quiper",
                arguments: ["Quiper", TemplateValidationServer.launchFlag]
            )
        )
    }

    func testDevBundleRequiresExplicitLaunchFlag() {
        XCTAssertFalse(
            TemplateValidationServer.canStart(
                bundleIdentifier: "app.sassanh.quiper.QuiperDev",
                arguments: ["Quiper"]
            )
        )
    }

    func testDevBundleCanStartWithExplicitLaunchFlag() {
        XCTAssertTrue(
            TemplateValidationServer.canStart(
                bundleIdentifier: "app.sassanh.quiper.QuiperDev",
                arguments: ["Quiper", TemplateValidationServer.launchFlag]
            )
        )
    }
}
