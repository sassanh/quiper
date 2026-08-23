import SwiftUI

/// SwiftUI counterpart of the macOS `WebLoadErrorView`: covers a session's web
/// content when a main-frame load fails, showing the reason and a Retry button.
/// The material background adapts to light and dark mode automatically.
struct WebLoadErrorOverlay: View {
    let error: WebLoadError
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("web-load-error-icon")
                Text(error.kind.title)
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("web-load-error-title")
                Text(error.kind.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("web-load-error-message")
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("web-load-error-retry")
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("web-load-error-view")
    }
}

/// Observes a session so its load error appears and disappears reactively.
struct SessionLoadErrorOverlay: View {
    @ObservedObject var session: WebViewSession

    var body: some View {
        if let error = session.loadError {
            WebLoadErrorOverlay(error: error) {
                session.retryFailedLoad()
            }
            .transition(.opacity)
        }
    }
}
