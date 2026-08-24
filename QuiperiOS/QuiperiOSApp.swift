import AppIntents
import Combine
import SwiftUI
import UserNotifications

@main
struct QuiperiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment: AppEnvironment
    @StateObject private var notificationDelegate = IOSNotificationDelegate()

    init() {
        let isUnitTestHost = UITestSupport.isUnitTestHost
        let privacyShieldController = isUnitTestHost ? nil : PrivacyShieldWindowController.shared

        let appEnvironment: AppEnvironment
        if UITestSupport.isEnabled {
            appEnvironment = UITestSupport.makeEnvironment()
        } else if isUnitTestHost {
            appEnvironment = UITestSupport.makeUnitTestHostEnvironment()
        } else {
            appEnvironment = AppEnvironment()
        }
        _environment = StateObject(wrappedValue: appEnvironment)
        if !isUnitTestHost {
            privacyShieldController?.bind(
                activeServiceLockState: appEnvironment.activeServiceLockStatePublisher
            )
            AppDependencyManager.shared.add(
                dependency: IOSAppIntentDependency(environment: appEnvironment)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            if UITestSupport.isUnitTestHost {
                Color.clear
                    .accessibilityHidden(true)
            } else {
                IOSAppRootView()
                    .environmentObject(environment)
                    .preferredColorScheme(environment.colorScheme.colorScheme)
                    .task {
                        guard !UITestSupport.isEnabled else { return }
                        notificationDelegate.configure(environment: environment)
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                            options: [.alert, .badge, .sound]
                        )
                    }
                    .onChange(of: scenePhase) { _, phase in
                        environment.handleScenePhase(phase)
                    }
                    .onAppear {
                        environment.handleScenePhase(scenePhase)
                    }
            }
        }
        .commands {
            IOSKeyboardCommands(environment: environment)
        }
    }
}

private struct IOSAppRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            switch environment.startupState {
            case .loading:
                ProgressView("Preparing Quiper…")
            case .waitingForProtectedData:
                StartupMessageView(
                    title: "Quiper Is Locked",
                    systemImage: "lock.fill",
                    message: "Unlock this device to make Quiper's protected settings available."
                )
            case .needsWebsiteDataReset:
                WebsiteDataResetView()
            case .ready:
                EngineBrowserView()
                    .fullScreenCover(isPresented: onboardingPresentationBinding) {
                        IOSOnboardingSheet(environment: environment)
                    }
                    .alert(
                        "Update Default Action Scripts?",
                        isPresented: Bindings.unwrap(environment.needsTemplateActionSyncMigrationPrompt)
                    ) {
                        Button("Update") {
                            environment.resolveTemplateActionSyncMigration(updateScripts: true)
                        }
                        Button("Keep Custom", role: .cancel) {
                            environment.resolveTemplateActionSyncMigration(updateScripts: false)
                        }
                    } message: {
                        Text("Quiper can reconnect actions that match built-in templates to the latest bundled scripts. Choose Update to keep those template scripts in sync automatically. Choose Keep Custom to leave existing scripts editable and unchanged.")
                    }
            case .failed(let message):
                StartupMessageView(
                    title: "Quiper Couldn’t Start",
                    systemImage: "exclamationmark.triangle.fill",
                    message: message,
                    retry: environment.retryStartup
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            environment.retryStartup()
        }
    }
}

/// Bridges published flags into `isPresented` bindings. The onboarding sheet is
/// suppressed for UI-test runs; the underlying state stays untouched.
private enum Bindings {
    static func unwrap(_ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { _ in })
    }
}

private extension IOSAppRootView {
    var onboardingPresentationBinding: Binding<Bool> {
        Bindings.unwrap(environment.needsIOSOnboarding && !UITestSupport.isEnabled)
    }
}

private struct StartupMessageView: View {
    let title: String
    let systemImage: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct WebsiteDataResetView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isResetting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "lock.square.stack.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                Text("Engine Isolation Upgrade")
                    .font(.largeTitle.bold())
                Text("Quiper now gives every engine its own isolated website-data store. Existing shared cookies and site storage must be removed once before browsing can continue.")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 12) {
                    Label("You will need to sign in to websites again once.", systemImage: "person.crop.circle.badge.exclamationmark")
                    Label("Engine settings, drafts, and prompt history are not deleted.", systemImage: "checkmark.shield")
                    Label("Afterward, one engine can no longer read another engine’s cookies or site storage.", systemImage: "rectangle.3.group.bubble.left.fill")
                }
                .font(.body)
                Button {
                    isResetting = true
                    Task {
                        await environment.completeWebsiteDataReset()
                        isResetting = false
                    }
                } label: {
                    HStack {
                        if isResetting {
                            ProgressView()
                        }
                        Text(isResetting ? "Resetting Website Sessions…" : "Reset Website Sessions and Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isResetting)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(32)
        }
    }
}

private final class IOSNotificationDelegate: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private weak var environment: AppEnvironment?

    @MainActor
    func configure(environment: AppEnvironment) {
        self.environment = environment
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let destination = NotificationDestination(userInfo: userInfo)

        Task { @MainActor [weak self, destination] in
            self?.environment?.activateNotification(
                serviceID: destination.serviceID,
                serviceURL: destination.serviceURL,
                sessionIndex: destination.sessionIndex
            )
        }
        completionHandler()
    }
}

extension IOSNotificationDelegate: @unchecked Sendable {}
