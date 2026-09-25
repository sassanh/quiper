import Foundation
import XCTest

/// Grants macOS system permission dialogs that would otherwise cover the app
/// under test.
///
/// The local-network permission alert appears whenever the app, or any page it
/// loads in a webview, contacts a local address. It sits on top of the app and
/// swallows the events the test is about to send, and the grant is per machine,
/// so every fresh CI runner asks again. XCTest invokes the registered monitor
/// only when an interaction is blocked by such a dialog, so favicon fetches,
/// page loads, and future networking are all covered without predicting which
/// network call produces the dialog.
enum SystemDialogMonitor {

    /// Phrases taken from the dialogs' own header text. A dialog is granted
    /// only when its text says what is being asked for.
    private static let knownDialogHeaders = [
        "find devices on local networks",
        "Send You Notifications"
    ]

    /// Registers the monitor on the test case. XCTest removes it automatically
    /// when the test ends.
    static func register(on testCase: XCTestCase) {
        _ = testCase.addUIInterruptionMonitor(withDescription: "Quiper permission dialogs") { alert in
            handle(interruption: alert)
        }
        NSLog("[SystemDialogMonitor] registered on \(type(of: testCase))")
    }

    /// Returns true when the dialog was recognized and granted, so XCTest
    /// waits for it to disappear and retries the blocked interaction. An
    /// unrecognized dialog is left to XCTest's built-in handling.
    private static func handle(interruption alert: XCUIElement) -> Bool {
        let elements = elements(of: alert)
        NSLog("[SystemDialogMonitor] interruption: \(describe(elements))")

        guard let matchedHeader = knownDialogHeaders.first(where: { phrase in
            elements.contains { matches(phrase, in: text(of: $0)) }
        }) else {
            NSLog("[SystemDialogMonitor] unrecognized dialog, leaving it to XCTest")
            return false
        }
        NSLog("[SystemDialogMonitor] recognized \"\(matchedHeader)\"")

        guard let grantButton = elements.first(where: { isGrantButton($0) }) else {
            NSLog("[SystemDialogMonitor] no Allow button, leaving it to XCTest")
            return false
        }
        guard grantButton.exists, grantButton.isHittable else {
            NSLog("[SystemDialogMonitor] Allow button not hittable, leaving it to XCTest")
            return false
        }

        grantButton.click()
        NSLog("[SystemDialogMonitor] clicked Allow, still exists: \(grantButton.exists)")
        return true
    }

    /// The dialog's grant button. The text must equal "Allow" exactly in one
    /// attribute — a substring or prefix match would qualify "Don't Allow".
    private static func isGrantButton(_ element: XCUIElement) -> Bool {
        guard element.elementType == .button else { return false }
        return textAttributes(of: element).contains { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines) == "Allow"
        }
    }

    private static func matches(_ phrase: String, in text: String) -> Bool {
        text.range(of: phrase, options: .caseInsensitive) != nil
    }

    /// The alert's own attributes plus every descendant's, so header text is
    /// found wherever the dialog puts it.
    private static func elements(of alert: XCUIElement) -> [XCUIElement] {
        [alert] + alert.descendants(matching: .any).allElementsBoundByIndex
    }

    /// Every text attribute an element may carry. Dialog controls expose their
    /// visible text in different ones depending on how they are built.
    private static func textAttributes(of element: XCUIElement) -> [String] {
        [element.label, element.title, element.value as? String].compactMap { $0 }
    }

    private static func text(of element: XCUIElement) -> String {
        textAttributes(of: element).joined(separator: " ")
    }

    private static func describe(_ elements: [XCUIElement]) -> String {
        let summary = elements.map {
            "\($0.elementType) id='\($0.identifier)' label='\($0.label)' title='\($0.title)' value=\(String(describing: $0.value)) hittable=\($0.isHittable) frame=\($0.frame)"
        }.joined(separator: " || ")
        return String(summary.prefix(2000))
    }
}
