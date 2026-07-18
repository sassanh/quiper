import XCTest
@testable import Quiper

@MainActor
final class QuickTooltipVisibilityCoordinatorTests: XCTestCase {
    func testStaleHideCannotHideNewTarget() throws {
        let ownerA = NSObject()
        let ownerB = NSObject()
        let targetA = TooltipTargetID(owner: ownerA)
        let targetB = TooltipTargetID(owner: ownerB)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(targetA)
        let requestID = try scheduledRequestID(
            from: coordinator.requestHide(for: ObjectIdentifier(ownerA))
        )
        coordinator.show(targetB)

        XCTAssertFalse(coordinator.completeHide(requestID: requestID))
        XCTAssertEqual(coordinator.state, .visible(targetB))
    }

    func testNewTargetCanShowAfterHideCompletes() throws {
        let ownerA = NSObject()
        let ownerB = NSObject()
        let targetA = TooltipTargetID(owner: ownerA)
        let targetB = TooltipTargetID(owner: ownerB)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(targetA)
        let requestID = try scheduledRequestID(
            from: coordinator.requestHide(for: ObjectIdentifier(ownerA))
        )

        XCTAssertTrue(coordinator.completeHide(requestID: requestID))
        XCTAssertEqual(coordinator.state, .hidden)

        coordinator.show(targetB)
        XCTAssertEqual(coordinator.state, .visible(targetB))
    }

    func testLateExitFromPreviousOwnerCannotScheduleHide() {
        let ownerA = NSObject()
        let ownerB = NSObject()
        let targetB = TooltipTargetID(owner: ownerB)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(TooltipTargetID(owner: ownerA))
        coordinator.show(targetB)

        XCTAssertEqual(
            coordinator.requestHide(for: ObjectIdentifier(ownerA)),
            .none
        )
        XCTAssertEqual(coordinator.state, .visible(targetB))
    }

    func testReenteringTargetInvalidatesPendingHide() throws {
        let owner = NSObject()
        let target = TooltipTargetID(owner: owner)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(target)
        let requestID = try scheduledRequestID(
            from: coordinator.requestHide(for: ObjectIdentifier(owner))
        )
        coordinator.show(target)

        XCTAssertFalse(coordinator.completeHide(requestID: requestID))
        XCTAssertEqual(coordinator.state, .visible(target))
    }

    func testRepeatedHideRequestKeepsOriginalDeadline() throws {
        let owner = NSObject()
        let target = TooltipTargetID(owner: owner)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(target)
        let requestID = try scheduledRequestID(
            from: coordinator.requestHide(for: ObjectIdentifier(owner))
        )

        XCTAssertEqual(
            coordinator.requestHide(for: ObjectIdentifier(owner)),
            .existing(requestID: requestID)
        )
        XCTAssertEqual(
            coordinator.state,
            .pendingHide(target, requestID: requestID)
        )
    }

    func testUpdatesRequireMatchingVisibleTarget() {
        let ownerA = NSObject()
        let ownerB = NSObject()
        let targetA = TooltipTargetID(owner: ownerA)
        let targetB = TooltipTargetID(owner: ownerB)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(targetA)
        XCTAssertTrue(coordinator.canUpdate(targetA))
        XCTAssertFalse(coordinator.canUpdate(targetB))

        _ = coordinator.requestHide(for: ObjectIdentifier(ownerA))
        XCTAssertFalse(coordinator.canUpdate(targetA))
    }

    func testImmediateHideInvalidatesPendingRequest() throws {
        let owner = NSObject()
        let target = TooltipTargetID(owner: owner)
        var coordinator = TooltipVisibilityCoordinator()

        coordinator.show(target)
        let requestID = try scheduledRequestID(
            from: coordinator.requestHide(for: ObjectIdentifier(owner))
        )
        coordinator.hideImmediately()

        XCTAssertFalse(coordinator.completeHide(requestID: requestID))
        XCTAssertEqual(coordinator.state, .hidden)
    }

    private func scheduledRequestID(
        from request: TooltipVisibilityCoordinator.HideRequest
    ) throws -> UInt64 {
        guard case .scheduled(let requestID) = request else {
            XCTFail("Expected a newly scheduled hide request, got \(request)")
            throw UnexpectedHideRequest()
        }
        return requestID
    }
}

private struct UnexpectedHideRequest: Error {}
