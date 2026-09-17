import Testing
import Foundation
@testable import Quiper

@Suite
struct TabCloseGateTests {

    @Test func probeScriptFiresBeforeUnload() {
        let script = TabCloseGate.beforeUnloadProbeScript
        #expect(script.contains("onbeforeunload"))
        #expect(script.contains("BeforeUnloadEvent"))
        #expect(script.contains("dispatchEvent"))
        #expect(script.contains("returnValue"))
        #expect(script.contains("dispatchResult === false"))
    }

    @Test func probeScriptNeverThrowsForBlankPages() {
        // Every fallible step degrades to "no confirmation" instead of
        // surfacing a JavaScript error to native code.
        let script = TabCloseGate.beforeUnloadProbeScript
        #expect(script.contains("return false"))
    }

    @Test func reasonCopyIsActionable() {
        let reasons: [TabCloseReason] = [
            .closeCurrentSession,
            .closeAllSessions(serviceName: "Gemini"),
            .lockService(serviceName: "Gemini"),
            .lockAllServices,
            .switchService(serviceName: "Gemini"),
            .autoLock,
            .replaceWithEphemeral,
            .quit,
        ]
        for reason in reasons {
            #expect(!reason.alertTitle(tabCount: 1).isEmpty)
            #expect(!reason.confirmButtonTitle.isEmpty)
        }
        #expect(TabCloseReason.quit.alertTitle(tabCount: 1).contains("Quit"))
        #expect(TabCloseReason.quit.alertTitle(tabCount: 3).contains("3"))
        #expect(TabCloseReason.closeAllSessions(serviceName: "Gemini").alertTitle(tabCount: 2).contains("Gemini"))
        #expect(TabCloseReason.lockService(serviceName: "Gemini").confirmButtonTitle == "Lock")
    }

    @Test func informativeTextStaysOneLineWithoutTabs() {
        #expect(TabCloseGate.informativeText(for: []) == "Changes you made may not be saved.")
    }

    @Test func informativeTextListsAffectedTabs() {
        let tabs = [
            TabUnloadInfo(serviceID: UUID(), sessionIndex: 0, serviceName: "Gemini", title: "Chat"),
            TabUnloadInfo(serviceID: UUID(), sessionIndex: 2, serviceName: "ChatGPT", title: "  "),
        ]
        let text = TabCloseGate.informativeText(for: tabs)
        #expect(text.contains("Changes you made may not be saved."))
        #expect(text.contains("Gemini — Chat"))
        #expect(text.contains("ChatGPT — Session 3"))
    }

    @Test func informativeTextTruncatesLongLists() {
        let tabs = (0..<6).map {
            TabUnloadInfo(serviceID: UUID(), sessionIndex: $0, serviceName: "Engine", title: "Tab \($0)")
        }
        let text = TabCloseGate.informativeText(for: tabs)
        #expect(text.contains("Tab 0"))
        #expect(!text.contains("Tab 5"))
        #expect(text.contains("and 2 more"))
    }

    @Test func displayNameFallsBackToSessionNumber() {
        let info = TabUnloadInfo(serviceID: UUID(), sessionIndex: 1, serviceName: "Gemini", title: "")
        #expect(info.displayName == "Gemini — Session 2")
        #expect(info.tab.sessionIndex == 1)
    }

    @Test func settingsWarningSuffixAppendsCleanly() {
        #expect(TabCloseGate.settingsWarningSuffix.hasPrefix(" "))
        #expect(TabCloseGate.settingsWarningSuffix.contains("unsaved"))
    }
}
