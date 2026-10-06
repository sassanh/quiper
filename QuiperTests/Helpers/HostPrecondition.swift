import XCTest
import AppKit
@testable import Quiper

/// A precondition the test host must satisfy before a focus, activation, or
/// hotkey-registration scenario can be judged.
///
/// Every such precondition in this suite routes through here, and only here.
/// `condition` gets `timeout` to hold while `requesting` re-issues the host
/// action that should satisfy it, so a late window-server handover is waited
/// for instead of mistaken for a refusal. A condition the host never
/// satisfies fails the test with its focus state and throws, so a host that
/// withholds focus turns CI red instead of skipping the scenario green.
@MainActor
enum HostPrecondition {

    /// Raised after a refusal is reported, so the scenario body never runs on
    /// a precondition the host did not meet.
    struct Refused: Error {
        let expectation: String
    }

    /// Waits until `window` holds key status, re-issuing the request that
    /// asks for it — by default an activation plus an order-front — on every
    /// poll until the handover lands.
    static func requireKey(
        _ window: NSWindow,
        named expectation: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        requesting request: (() -> Void)? = nil
    ) async throws {
        let issueRequest = request ?? {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        try await require(
            "The test host refused key status: \(expectation)",
            requesting: issueRequest,
            timeout: timeout,
            file: file,
            line: line,
            until: { window.isKeyWindow }
        )
    }

    /// Waits until `condition` holds, re-issuing `requesting` on every poll
    /// while it does not. A condition that never holds within `timeout`
    /// fails the test at the call site, reporting `expectation` alongside
    /// the host's current focus state.
    static func require(
        _ expectation: String,
        requesting request: (() -> Void)? = nil,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        until condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail(
                    "\(expectation)\nHost focus state: \(focusState())",
                    file: file,
                    line: line
                )
                throw Refused(expectation: expectation)
            }
            request?()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// The host's focus state at the moment of refusal: which window holds
    /// key status, what the focus gate records and prefers, and whether the
    /// app is active at all — enough to tell a refused activation, a refused
    /// precedence, and a handover that simply never landed.
    private static func focusState() -> String {
        let gate = KeyFocusGate.shared
        return [
            "app active: \(NSApp.isActive)",
            "key window: \(describe(NSApp.keyWindow))",
            "focus history: \(describe(gate.lastKeyWindow))",
            "precedence target: \(gate.precedenceTarget().map { describe($0) } ?? "none")",
            "onboarding active: \(GhostOnboardingManager.shared.isActive)"
        ].joined(separator: "; ")
    }

    private static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "none" }
        let title = window.title.isEmpty ? "untitled" : "\"\(window.title)\""
        return "\(type(of: window))(\(title), visible: \(window.isVisible), key: \(window.isKeyWindow))"
    }
}
