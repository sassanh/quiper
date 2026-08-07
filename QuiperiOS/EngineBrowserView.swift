import Combine
import SwiftUI
import UIKit

struct EngineBrowserView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingEnginePicker = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isScrollCollapsed = false
    @State private var isFindBarVisible = false
    @FocusState private var isFindFieldFocused: Bool

    private static let findBarBottomInset: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .bottom) {
                webContent
                    .padding(.bottom, isFindBarVisible ? Self.findBarBottomInset : 0)
                if !isMinimized {
                    if isFindBarVisible {
                        findBar
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    } else {
                        bottomControls(landscape: landscape)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    }
                }
                if isMinimized {
                    island
                        .padding(.bottom, islandBottomPadding(bottomInset: geo.safeAreaInsets.bottom))
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea(isFindBarVisible ? [] : .keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let height = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            withAnimation(islandAnimation) {
                isKeyboardVisible = true
                keyboardHeight = height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(islandAnimation) {
                isKeyboardVisible = false
                keyboardHeight = 0
            }
        }
        .onReceive(activeSession?.$isBarCollapsed.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { collapsed in
            withAnimation(islandAnimation) {
                isScrollCollapsed = collapsed
            }
        }
        .onChange(of: activeSession?.id) {
            isScrollCollapsed = false
            if isFindBarVisible {
                closeFindBar()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(environment)
        }
        .sheet(isPresented: $showingHistory) {
            PromptHistoryView()
                .environmentObject(environment)
        }
        .sheet(isPresented: $showingEnginePicker) {
            EnginePickerView()
                .environmentObject(environment)
                .presentationDetents([.medium, .large])
        }
    }

    private var isMinimized: Bool {
        guard !isFindBarVisible else { return false }
        return isKeyboardVisible || isScrollCollapsed
    }

    private func islandBottomPadding(bottomInset: CGFloat) -> CGFloat {
        isKeyboardVisible ? max(0, keyboardHeight - bottomInset) : 12
    }

    private var islandTapAction: () -> Void {
        {
            if isKeyboardVisible {
                dismissKeyboard()
            }
            activeSession?.expandBar()
        }
    }

    private var activeServiceID: UUID {
        environment.activeService?.id ?? environment.services.first?.id ?? UUID()
    }

    private var activeSessionIndex: Int {
        environment.activeSessionIndex(for: activeServiceID)
    }

    private var activeSession: WebViewSession? {
        guard let service = environment.activeService else { return nil }
        return environment.webViewSession(
            for: service.id,
            sessionIndex: activeSessionIndex,
            initialURL: environment.activeSessionURL(for: service.id)
        )
    }

    private var islandAnimation: Animation {
        .spring(response: 0.45, dampingFraction: 0.68)
    }

    @ViewBuilder
    private var island: some View {
        if let session = activeSession {
            Island(
                session: session,
                service: environment.activeService,
                sessionIndex: activeSessionIndex,
                tapAction: islandTapAction
            )
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openFindBar() {
        isFindBarVisible = true
        activeSession?.expandBar()
        isFindFieldFocused = true
    }

    private func closeFindBar() {
        isFindBarVisible = false
        isFindFieldFocused = false
        activeSession?.resetFind()
        dismissKeyboard()
    }

    private func clearFindQuery() {
        activeSession?.setFindQuery("")
    }

    private func bottomControls(landscape: Bool) -> some View {
        VStack(spacing: 10) {
            if landscape {
                landscapeControls
            } else {
                portraitControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassContainer()
    }

    private var portraitControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                engineSelectorButton
                actionsMenu
                Spacer(minLength: 4)
                navigationControls
            }
            sessionSelector(flexible: false)
        }
    }

    private var landscapeControls: some View {
        HStack(spacing: 10) {
            engineSelectorButton
            actionsMenu
            sessionSelector(flexible: true)
            navigationControls
        }
        .frame(maxWidth: .infinity)
    }

    private var findBar: some View {
        HStack(spacing: 10) {
            findField
            if let session = activeSession, let status = session.findStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            findIconButton(systemImage: "chevron.up", label: "Previous match") {
                activeSession?.stepFind(forward: false)
            }
            findIconButton(systemImage: "chevron.down", label: "Next match") {
                activeSession?.stepFind(forward: true)
            }
            findIconButton(systemImage: "xmark", label: "Close find") {
                closeFindBar()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassContainer()
    }

    private var findField: some View {
        HStack(spacing: 2) {
            TextField("Find in page", text: findQueryBinding)
                .focused($isFindFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.leading, 10)
            if !(activeSession?.findQuery.isEmpty ?? true) {
                Button {
                    clearFindQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Clear find text")
            } else {
                Spacer().frame(width: 6)
            }
        }
        .frame(height: 34)
        .glassIsland(in: Capsule(), interactive: true)
    }

    private var findQueryBinding: Binding<String> {
        Binding(
            get: { activeSession?.findQuery ?? "" },
            set: { activeSession?.setFindQuery($0) }
        )
    }

    private func findIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34)
                .glassIsland(in: Circle(), interactive: true)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var navigationControls: some View {
        if let session = activeSession {
            NavigationControls(session: session)
        } else {
            EmptyView()
        }
    }

    private var actionsMenu: some View {
        Menu {
            if environment.customActions.isEmpty {
                Text("No Actions")
            } else {
                ForEach(environment.customActions) { action in
                    Button {
                        environment.runAction(action, for: activeServiceID)
                    } label: {
                        Label(action.name.isEmpty ? "Action" : action.name, systemImage: "bolt.fill")
                    }
                }
            }
            Divider()
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                showingHistory = true
            } label: {
                Label("Prompt History", systemImage: "clock.arrow.circlepath")
            }
            Button {
                openFindBar()
            } label: {
                Label("Find in Page", systemImage: "magnifyingglass")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt")
                    .font(.system(size: 15))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .accessibilityLabel("Actions")
    }

    private var engineSelectorButton: some View {
        Button {
            showingEnginePicker = true
        } label: {
            HStack(spacing: 8) {
                EngineIconView(service: environment.activeService, size: 18)
                Text(environment.activeService?.name ?? "Select Engine")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .accessibilityLabel("Select engine")
    }

    private func sessionSelector(flexible: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(SessionSlots.range, id: \.self) { slot in
                let isActive = slot == activeSessionIndex
                let isLoaded = environment.isSessionLoaded(for: activeServiceID, slot: slot)
                Button {
                    environment.setActiveSession(for: activeServiceID, index: slot)
                } label: {
                    Text(SessionSlots.label(for: slot))
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .frame(
                            minWidth: flexible ? 24 : 30,
                            idealWidth: 30,
                            maxWidth: flexible ? .infinity : 30
                        )
                        .frame(height: 30)
                        .foregroundStyle(segmentForeground(isActive: isActive, isLoaded: isLoaded))
                        .glassIsland(
                            in: RoundedRectangle(cornerRadius: 8),
                            tint: isActive ? Color.accentColor : nil,
                            interactive: true
                        )
                }
                .contextMenu {
                    Button("Close Session", role: .destructive) {
                        environment.closeSession(for: activeServiceID, at: slot)
                    }
                }
                .accessibilityLabel(SessionSlots.tooltipTitle(for: slot))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func segmentForeground(isActive: Bool, isLoaded: Bool) -> Color {
        if isActive { return .white }
        if !isLoaded { return .primary.opacity(0.3) }
        return .primary
    }

    private var webContent: some View {
        ZStack {
            if let session = activeSession {
                WebKitBrowserView(session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView("No Engines", systemImage: "globe", description: Text("Add an engine in Settings."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct EnginePickerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(environment.services) { service in
                    Button {
                        environment.setActiveService(service.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            EngineIconView(service: service, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .foregroundStyle(Color.primary)
                                if let url = URL(string: service.url), let host = url.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if service.id == environment.activeService?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct NavigationControls: View {
    @ObservedObject var session: WebViewSession

    var body: some View {
        HStack(spacing: 10) {
            if session.canGoBack {
                Button {
                    session.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassIsland(in: Circle(), interactive: true)
                }
                .accessibilityLabel("Back")
            }

            if session.canGoForward {
                Button {
                    session.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassIsland(in: Circle(), interactive: true)
                }
                .accessibilityLabel("Forward")
            }

            Button {
                if session.isLoading {
                    session.stopLoading()
                } else {
                    session.reload()
                }
            } label: {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 34, height: 34)
                    .glassIsland(in: Circle(), interactive: true)
            }
            .padding(4)
            .overlay {
                if session.isLoading {
                    LoadingRing(shape: Circle(), lineWidth: 3)
                }
            }
            .accessibilityLabel(session.isLoading ? "Stop" : "Reload")
        }
    }
}

private struct Island: View {
    @ObservedObject var session: WebViewSession
    let service: Service?
    let sessionIndex: Int
    let tapAction: () -> Void

    var body: some View {
        Button(action: tapAction) {
            HStack(spacing: 10) {
                Text(SessionSlots.label(for: sessionIndex))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor)
                    )
                HStack(spacing: 6) {
                    EngineIconView(service: service, size: 18)
                    Text(service?.name ?? "Select Engine")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassIsland(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(4)
        .overlay {
            if session.isLoading {
                LoadingRing(shape: Capsule(), lineWidth: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Hide keyboard")
    }
}

private struct LoadingRing<S: Shape>: View {
    let shape: S
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation) { context in
            RingCanvas(
                shape: shape,
                lineWidth: lineWidth,
                phase: phase(at: context.date)
            )
        }
        .allowsHitTesting(false)
    }

    private func phase(at date: Date) -> CGFloat {
        let seconds = date.timeIntervalSinceReferenceDate
        let progress = seconds.truncatingRemainder(dividingBy: 1.5) / 1.5
        return CGFloat(progress)
    }
}

private struct RingCanvas<S: Shape>: View {
    let shape: S
    let lineWidth: CGFloat
    let phase: CGFloat

    var body: some View {
        Canvas { canvas, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let path = shape.path(in: rect)
            let segmentFraction: CGFloat = 0.16
            let start = phase
            let end = phase + segmentFraction
            canvas.stroke(path, with: .color(Color.accentColor.opacity(0.25)), lineWidth: lineWidth)
            if end <= 1 {
                canvas.stroke(
                    path.trim(from: start, to: end).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            } else {
                canvas.stroke(
                    path.trim(from: start, to: 1).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                canvas.stroke(
                    path.trim(from: 0, to: end - 1).path(in: rect),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}
