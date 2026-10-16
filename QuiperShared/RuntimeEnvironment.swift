import Foundation

/// Central definitions for the process-environment predicates that gate
/// storage redirection, automation-only behavior, and development
/// conveniences. Keeping the raw probes here gives every call site a single
/// named semantics and keeps XCTest/Xcode detection from drifting between
/// files.
enum RuntimeEnvironment {
    /// The process was launched by an XCTest runner: `XCTestConfigurationFilePath` is set.
    nonisolated static let isUnitTestRunner: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }()

    /// `XCTestBundlePath` is set in the process environment.
    nonisolated static let hasXCTestBundle: Bool = {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }()

    /// XCTest classes are loaded into this process (`NSClassFromString("XCTestCase")`).
    nonisolated static let areXCTestClassesLoaded: Bool = {
        NSClassFromString("XCTestCase") != nil
    }()

    /// A test runner injected a test bundle into this process: `XCInjectBundleInto` is set.
    nonisolated static let isXCTestInjected: Bool = {
        ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
    }()

    /// XCTest tooling is detectable in this process in any form. Sufficient for
    /// production code to yield the floor to automated runs; **not** the cheapest
    /// predicate, so prefer the specific ones above on hot paths.
    nonisolated static let isRunningUnderXCTest: Bool =
        isUnitTestRunner || hasXCTestBundle || areXCTestClassesLoaded

    /// The process was started by Xcode development tooling: SwiftUI previews,
    /// an Xcode XPC service, or a build under DerivedData. Always false inside
    /// unit-test hosts, matching the launch-argument model elsewhere in the app.
    nonisolated static let isXcodeDevelopmentSession: Bool = {
        if isUnitTestRunner {
            return false
        }
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil {
            return true
        }
        if let serviceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
           serviceName.contains("com.apple.dt.Xcode") {
            return true
        }
        if Bundle.main.bundlePath.contains("/DerivedData/") {
            return true
        }
        return false
    }()

    /// Per-process isolated storage directory used while running with XCTest
    /// tooling, so automated runs never touch real application-support data.
    nonisolated static var quiperTestsStorageDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
    }
}
