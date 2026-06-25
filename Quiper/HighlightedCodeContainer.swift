import SwiftUI
import AppKit

struct HighlightedCodeContainer: View {
    @Binding var code: String
    let language: String
    let fileName: String
    var isReadOnly: Bool = false
    let openInEditor: () -> Void
    let revealInFinder: () -> Void
    let copyFilePath: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.accentColor)
                Text(fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                // Active Action Buttons
                if isReadOnly {
                    Label("In Sync", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    HStack(spacing: 12) {
                        Button(action: openInEditor) {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .help("Open in your default text editor")

                        Button(action: revealInFinder) {
                            Label("Reveal", systemImage: "sidebar.left")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .help("Show file in Finder")

                        Button(action: copyFilePath) {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .help("Copy absolute file path to clipboard")
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Live Editable Code Text Editor with dynamic height fill
            CodeTextEditor(text: $code, language: language, isEditable: !isReadOnly)
                .frame(minHeight: 160, maxHeight: .infinity)
                .background(Color(red: 30/255, green: 30/255, blue: 30/255))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 5,
                        bottomTrailingRadius: 5,
                        topTrailingRadius: 0
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        )
    }
}

#if os(macOS)
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let isEditable: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.white
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator

        // Enable horizontal scrolling by expanding text container width
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        let oldDelegate = textView.delegate
        textView.delegate = nil
        
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        
        // Apply syntax highlighting natively
        if let textStorage = textView.textStorage {
            let nsAttributedString = SyntaxHighlighter.highlight(code: text, language: language)
            
            let selectedRange = textView.selectedRange()
            textStorage.setAttributedString(nsAttributedString)
            textView.setSelectedRange(selectedRange)
        }
        
        textView.delegate = oldDelegate
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        init(parent: Coordinator.Parent) { self.parent = parent }
        typealias Parent = CodeTextEditor
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
#else
struct CodeTextEditor: View {
    @Binding var text: String
    let language: String
    let isEditable: Bool
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .disabled(!isEditable)
    }
}
#endif
