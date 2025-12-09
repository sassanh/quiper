import Testing
import AppKit
import Carbon
@testable import Quiper

@MainActor
struct CustomActionShortcutDispatcherTests {
    
    class MockActionProvider: CustomActionProvider {
        var customActions: [CustomAction] = []
    }
    
    @Test func handleKeyDown_NoMatch_ReturnsFalse() {
        // Given
        let provider = MockActionProvider()
        provider.customActions = []
        
        let dispatcher = CustomActionShortcutDispatcher(actionProvider: provider)
        
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "b",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_B)
        )!
        
        // When
        ShortcutRecordingState.isRecording = false
        let result = dispatcher.handleKeyDown(event)
        
        // Then
        #expect(!result)
    }
}
