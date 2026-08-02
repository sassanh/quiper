import XCTest
@testable import Quiper

@MainActor
final class EngineMetadataMigrationTests: XCTestCase {
    func testLoadMetadataReturnsUnmigratedServiceUnchanged() throws {
        let service = Service(
            name: "Legacy Engine",
            url: "https://example.com",
            focus_selector: "#prompt",
            customCSS: "body { color: red; }"
        )
        let originalServices = Settings.shared.services
        defer { Settings.shared.services = originalServices }
        Settings.shared.services = [service]

        let loaded = try EngineMetadataMigrationManager.shared.loadMetadataForUnlockedService(service.id)
        XCTAssertEqual(loaded.id, service.id)
        XCTAssertEqual(loaded.url, service.url)
        XCTAssertEqual(loaded.focus_selector, service.focus_selector)
        XCTAssertEqual(loaded.customCSS, service.customCSS)
    }

    func testLoadMetadataReportsMissingMigratedMetadata() {
        var service = Service(
            name: "Migrated Engine",
            url: "",
            focus_selector: "",
            isEncrypted: true,
            hasMigratedMetadata: true
        )
        service.id = UUID()

        let originalServices = Settings.shared.services
        defer { Settings.shared.services = originalServices }
        Settings.shared.services = [service]

        XCTAssertThrowsError(
            try EngineMetadataMigrationManager.shared.loadMetadataForUnlockedService(service.id)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Failed to read metadata from secure storage"))
        }
    }
}
