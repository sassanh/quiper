import SwiftUI

struct PromptHistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var draftText = ""

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Saved Prompts",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Submitted prompts appear here when prompt history is enabled.")
                    )
                } else {
                    List(entries.reversed(), id: \.timestamp) { entry in
                        Button {
                            draftText = entry.text
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text)
                                    .font(.body)
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Prompt History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !draftText.isEmpty {
                composerPreview
            }
        }
    }

    private var entries: [PromptHistoryEntry] {
        guard let serviceID = environment.activeService?.id else { return [] }
        let index = environment.activeSessionIndex(for: serviceID)
        return environment.promptHistory(for: serviceID, sessionIndex: index)
    }

    private var composerPreview: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                Text(draftText)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                Button("Use") {
                    useDraft()
                }
                .font(.body.weight(.semibold))
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func useDraft() {
        guard let serviceID = environment.activeService?.id else { return }
        let index = environment.activeSessionIndex(for: serviceID)
        let session = environment.webViewSession(
            for: serviceID,
            sessionIndex: index,
            initialURL: environment.activeSessionURL(for: serviceID)
        )
        session.submitPrompt(draftText)
        dismiss()
    }
}
