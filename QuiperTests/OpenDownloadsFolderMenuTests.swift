import XCTest
import AppKit
@testable import Quiper

/// Covers the title menu's "Open Downloads Folder" item: it exists for every
/// page, follows the engine that owns that page, and a locked secure engine
/// shows a lock with a reason instead of a live action.
@MainActor
final class OpenDownloadsFolderMenuTests: XCTestCase {

    private func makeController(engine: Service) -> MainWindowController {
        let controller = MainWindowController(services: [engine])
        _ = controller.window
        _ = controller.webViewManager.getOrCreateWebView(
            for: engine,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        return controller
    }

    private func downloadsItem(in controller: MainWindowController) throws -> NSMenuItem {
        let menu = controller.makeTitleContextMenu()
        return try XCTUnwrap(menu.items.first(where: { $0.title == "Open Downloads Folder" }))
    }

    func testItemIsPresentAndEnabledForARegularEngine() throws {
        let engine = Service(name: "Plain Engine", url: "https://plain.example", focus_selector: "")
        let controller = makeController(engine: engine)

        XCTAssertTrue(try downloadsItem(in: controller).isEnabled)
    }

    func testLockedSecureEngineCarriesALockWithAReason() throws {
        let engine = Service(
            name: "Locked Engine",
            url: "https://locked.example",
            focus_selector: "",
            isEncrypted: true
        )
        defer { EncryptedVolumeManager.shared.markLocked(engine.id) }
        let controller = makeController(engine: engine)

        let item = try downloadsItem(in: controller)

        XCTAssertFalse(item.isEnabled)
        XCTAssertNotNil(item.image, "A locked engine must show the lock, not a plain grey item")
        XCTAssertEqual(item.toolTip, "Unlock “Locked Engine” to open its downloads")
    }

    func testUnlockedSecureEngineCarriesNoLock() throws {
        let engine = Service(
            name: "Unlocked Engine",
            url: "https://unlocked.example",
            focus_selector: "",
            isEncrypted: true
        )
        EncryptedVolumeManager.shared.markUnlocked(engine.id)
        defer { EncryptedVolumeManager.shared.markLocked(engine.id) }
        let controller = makeController(engine: engine)

        let item = try downloadsItem(in: controller)

        XCTAssertTrue(item.isEnabled)
        XCTAssertNil(item.image)
        XCTAssertNil(item.toolTip)
    }
}
