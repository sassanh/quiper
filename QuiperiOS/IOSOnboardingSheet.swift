import SwiftUI

/// First-run onboarding for Quiper on iOS: the standard paged carousel with
/// dots and back navigation. Fresh installs finish by picking which bundled
/// engines to add—each optionally protected with device authentication—while
/// existing installs get the macOS wizard's "Secure Your Engines" step for
/// the engines they already have.
struct IOSOnboardingSheet: View {
    @ObservedObject var environment: AppEnvironment

    @State private var page: Page = .welcome
    @State private var selectedEngineIDs: Set<UUID> = []
    @State private var selectedTemplateIDs: Set<UUID> = []
    @State private var secureTemplateIDs: Set<UUID> = []
    @State private var protectionStatusText = ""
    @State private var isProcessing = false

    enum Page: Int, CaseIterable {
        case welcome
        case sessions
        case gestures
        case setup
    }

    /// Fresh installs pick engines from the bundled templates; existing
    /// installs only protect the engines they already have.
    private var offersEngineSetup: Bool {
        environment.services.isEmpty
    }

    private var unprotectedEngines: [Service] {
        environment.services.filter { !$0.isEncrypted }
    }

    private var templateCatalog: [Service] {
        environment.defaultServiceTemplates
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if isProcessing {
                processingView
            } else {
                TabView(selection: $page) {
                    welcomePage.tag(Page.welcome)
                    sessionsPage.tag(Page.sessions)
                    gesturesPage.tag(Page.gestures)
                    setupPage.tag(Page.setup)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .safeAreaInset(edge: .bottom) { controls }
                .overlay(alignment: .topTrailing) {
                    if page != .setup {
                        Button("Skip", action: finish)
                            .font(.subheadline)
                            .padding(.trailing, 20)
                            .padding(.top, 8)
                            .accessibilityIdentifier("ios-onboarding-skip")
                    }
                }
            }
        }
        .accessibilityIdentifier("ios-onboarding-sheet")
    }

    // MARK: - Pages

    private var welcomePage: some View {
        introPage(
            graphic: "square.stack.3d.up.fill",
            title: "Welcome to Quiper",
            text: "All your AI engines—ChatGPT, Claude, Gemini, and your own—together in one place. Every engine keeps its own chat sessions, and your drafts are saved automatically."
        )
    }

    private var sessionsPage: some View {
        introPage(
            graphic: "rectangle.on.rectangle.angled",
            title: "Independent Sessions",
            text: "Each engine holds isolated chat slots, so you can run parallel conversations. Double-tap the page to open your recent tabs—hold to keep the ring open, then release over a tab to switch."
        )
    }

    private var gesturesPage: some View {
        introPage(
            graphic: "hand.tap.fill",
            title: "Fast by Gesture",
            text: "The bar at the edge of the screen switches engines and sessions. The actions menu holds Find in Page, new sessions, your custom actions, and Settings."
        )
    }

    @ViewBuilder
    private var setupPage: some View {
        if offersEngineSetup {
            engineSetupPage
        } else {
            protectionPage
        }
    }

    // MARK: - Engine setup (fresh installs)

    private var addCount: Int {
        selectedTemplateIDs.count
    }

    private var engineSetupPage: some View {
        VStack(spacing: 14) {
            graphic("square.grid.2x2.fill")
            Text("Choose Your Engines")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Tap the engines you want to add. Turning on a secure switch protects that engine with your device authentication. You can change this anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(templateCatalog) { template in
                        templateRow(template)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func templateRow(_ template: Service) -> some View {
        let isSelected = selectedTemplateIDs.contains(template.id)
        let isSecure = secureTemplateIDs.contains(template.id)
        return HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { toggleTemplate(template) }
            } label: {
                HStack(spacing: 10) {
                    EngineIconView(service: template, size: 28)
                        .frame(width: 30)
                    Text(template.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { toggleSecure(template) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSecure ? Color.green : Color.secondary.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: isSecure ? "lock.fill" : "lock.open")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSecure ? .white : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.7, anchor: .trailing).combined(with: .opacity))
                .accessibilityLabel(isSecure ? "Secure storage on" : "Secure storage off")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("ios-onboarding-secure-\(template.id.uuidString)")
            }

            selectionCircle(isSelected)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) { toggleTemplate(template) }
                }
                .accessibilityIdentifier("ios-onboarding-check-\(template.id.uuidString)")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func toggleTemplate(_ template: Service) {
        if selectedTemplateIDs.contains(template.id) {
            selectedTemplateIDs.remove(template.id)
            secureTemplateIDs.remove(template.id)
        } else {
            selectedTemplateIDs.insert(template.id)
        }
    }

    private func toggleSecure(_ template: Service) {
        if secureTemplateIDs.contains(template.id) {
            secureTemplateIDs.remove(template.id)
        } else {
            secureTemplateIDs.insert(template.id)
        }
    }

    private func selectionCircle(_ isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.green : Color.clear)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
        .overlay(
            Circle()
                .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.5)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Protection (existing installs)

    private var protectionPage: some View {
        VStack(spacing: 16) {
            graphic("lock.shield.fill")
            Text("Secure Your Engines")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Protect sensitive engines with your device authentication. Protected engines lock when you switch away, and their data is sealed with encryption only this device can open. You can change this anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if unprotectedEngines.isEmpty {
                Spacer()
                Label("Every engine is already protected.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(unprotectedEngines) { engine in
                            engineRow(engine)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func engineRow(_ engine: Service) -> some View {
        Toggle(isOn: Binding(
            get: { selectedEngineIDs.contains(engine.id) },
            set: { isSelected in
                if isSelected {
                    selectedEngineIDs.insert(engine.id)
                } else {
                    selectedEngineIDs.remove(engine.id)
                }
            }
        )) {
            HStack(spacing: 12) {
                EngineIconView(service: engine, size: 30)
                Text(engine.name)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("ios-onboarding-engine-\(engine.id.uuidString)")
    }

    // MARK: - Bottom controls

    private var controls: some View {
        HStack(spacing: 16) {
            if page != .welcome {
                Button {
                    withAnimation { goBack() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("ios-onboarding-back")
            }
            Spacer()
            primaryControl
        }
        .font(.subheadline)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch page {
        case .setup:
            if offersEngineSetup {
                Button(
                    addCount == 0
                        ? "Get Started"
                        : "Add \(addCount) Engine\(addCount == 1 ? "" : "s")"
                ) {
                    confirmEngineSetup()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ios-onboarding-finish")
            } else if selectedEngineIDs.isEmpty {
                Button("Get Started", action: finish)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ios-onboarding-finish")
            } else {
                Button("Protect \(selectedEngineIDs.count) Engine\(selectedEngineIDs.count == 1 ? "" : "s")") {
                    protectSelectedEngines()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ios-onboarding-protect-confirm")
            }
        case .welcome, .sessions, .gestures:
            Button("Next") {
                withAnimation { goForward() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("ios-onboarding-next")
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.4)
            Text(protectionStatusText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func introPage(graphic: String, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            self.graphic(graphic)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func graphic(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 8)
            Image(systemName: systemName)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private func goBack() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        page = previous
    }

    private func goForward() {
        guard let next = Page(rawValue: page.rawValue + 1) else { return }
        page = next
    }

    /// Fresh installs: adds the chosen bundled engines (optionally protecting
    /// each) through the same paths as Settings.
    private func confirmEngineSetup() {
        let orderedTemplates = templateCatalog.filter { selectedTemplateIDs.contains($0.id) }
        guard !orderedTemplates.isEmpty else {
            finish()
            return
        }
        isProcessing = true
        Task {
            var addedServiceIDs: [UUID: UUID] = [:]
            for template in orderedTemplates {
                protectionStatusText = "Adding \(template.name)…"
                environment.addService(from: template)
                if let added = environment.services.last(where: { $0.name == template.name }) {
                    addedServiceIDs[template.id] = added.id
                }
            }
            for template in orderedTemplates {
                guard secureTemplateIDs.contains(template.id),
                      let serviceID = addedServiceIDs[template.id] else { continue }
                protectionStatusText = "Protecting \(template.name)…"
                await environment.enableProtection(for: serviceID)
            }
            finish()
        }
    }

    /// Existing installs: protects the chosen engines.
    private func protectSelectedEngines() {
        let orderedEngines = unprotectedEngines.filter { selectedEngineIDs.contains($0.id) }
        guard !orderedEngines.isEmpty else { return }
        isProcessing = true
        Task {
            for engine in orderedEngines {
                protectionStatusText = "Protecting \(engine.name)…"
                await environment.enableProtection(for: engine.id)
            }
            finish()
        }
    }

    private func finish() {
        environment.completeIOSOnboarding()
    }
}
