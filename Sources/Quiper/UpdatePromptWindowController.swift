import SwiftUI
import AppKit
import MarkdownUI

final class UpdatePromptWindowController: NSWindowController {
    static let shared = UpdatePromptWindowController()

    private var hostingController: NSHostingController<UpdatePromptView>?
    private var releaseInfo: UpdateManager.ReleaseInfo?

    private init() {
        let contentRect = NSRect(x: 0, y: 0, width: 560, height: 520)
        let window = NSPanel(contentRect: contentRect,
                             styleMask: [.titled, .closable],
                             backing: .buffered,
                             defer: false)
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(for release: UpdateManager.ReleaseInfo) {
        releaseInfo = release
        let rootView = UpdatePromptView(release: release)
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hosting = NSHostingController(rootView: rootView)
            hostingController = hosting
            window?.contentViewController = hosting
        }
        window?.title = "Software Update"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissIfNeeded() {
        window?.orderOut(nil)
    }
}

private struct UpdatePromptView: View {
    let release: UpdateManager.ReleaseInfo
    @ObservedObject private var updater = UpdateManager.shared
    private let releaseNotesText: String?

    init(release: UpdateManager.ReleaseInfo) {
        self.release = release
        self.releaseNotesText = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            notesSection
            Divider()
            controlSection
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text("A new version of \(Constants.APP_NAME) is available")
                    .font(.title3)
                    .bold()
                Text("Version \(release.version) is available; you have \(Bundle.main.versionDisplayString).")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if release.requiresBrowserDownload {
                Button("Open Release Page") {
                    NSWorkspace.shared.open(release.pageURL)
                }
            } else {
                switch updater.status {
                case .available:
                    Button("Download Update") {
                        updater.downloadLatestRelease()
                    }
                case .downloading:
                    progressView(title: "Downloading update…")
                case .readyToInstall:
                    readyToInstallControls
                case .installing:
                    progressView(title: "Installing update…")
                case .installed:
                    Button("Relaunch Now") {
                        updater.relaunchApplicationFromPrompt()
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Update failed: \(message)")
                            .foregroundColor(.red)
                        Button("Retry Download") {
                            updater.downloadLatestRelease()
                        }
                    }
                default:
                    Text(updater.statusDescription)
                        .foregroundColor(.secondary)
                }
            }

            Text("Install later via Settings → General → Check for Updates.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func progressView(title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = updater.downloadProgress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var readyToInstallControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ProgressView(value: 1)
                    .frame(maxWidth: .infinity)
                Button("Install Update") {
                    updater.installReadyUpdate()
                }
            }
            Text("Download complete. Click Install to replace the app now.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Notes")
                .font(.headline)
            ScrollView {
                if let notes = releaseNotesText, !notes.isEmpty {
                    markdownView(notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                } else {
                    Text("No release notes provided.")
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                }
            }
            .frame(minHeight: 220)
            .textSelection(.enabled)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func markdownView(_ text: String) -> some View {
        if #available(macOS 15.0, *) {
            Markdown(text)
                .markdownTheme(.gitHub)
                .padding(.vertical, 4)
        } else if let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)) {
            Text(parsed)
        } else {
            Text(text)
                .font(.system(.body, design: .monospaced))
        }
    }
}
