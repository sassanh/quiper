import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct SettingsView: View {
    @State private var selectedTab = "Services"
    var appController: AppController?
    var initialServiceURL: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(appController: appController)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("General")

            ServicesSettingsView(appController: appController,
                                 initialServiceURL: initialServiceURL)
                .tabItem {
                    Label("Services", systemImage: "list.bullet")
                }
                .tag("Services")

            ActionsSettingsView()
                .tabItem {
                    Label("Actions", systemImage: "bolt")
                }
                .tag("Actions")
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct GeneralSettingsView: View {
    var appController: AppController?
    @State private var launchAtLogin = Launcher.isInstalledAtLogin()
    private let versionDescription = Bundle.main.versionDisplayString
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = UpdateManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection(title: "Startup") {
                    SettingsToggleRow(
                        title: "Launch at login",
                        message: "Install Quiper as a login item so it’s ready immediately after you sign in.",
                        isOn: $launchAtLogin
                    )
                    .onChange(of: launchAtLogin) { _, isEnabled in
                        if isEnabled {
                            appController?.installAtLogin(nil)
                        } else {
                            appController?.uninstallFromLogin(nil)
                        }
                    }
                }

                SettingsSection(title: "Updates") {
                    SettingsRow(
                        title: "Current version",
                        message: updater.statusDescription
                    ) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(versionDescription)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Manual check",
                        message: "Immediately trigger an update check from GitHub releases."
                    ) {
                        Button(action: { updater.checkForUpdates(userInitiated: true) }) {
                            Text(updater.isChecking ? "Checking…" : "Check for Updates")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isChecking)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Automatically check for updates",
                        message: "Poll in the background and notify you when a new build ships.",
                        isOn: autoCheckBinding
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Automatically download updates",
                        message: "Fetch new builds as soon as they’re found so installs are instant.",
                        isOn: autoDownloadBinding
                    )
                    .disabled(!settings.updatePreferences.automaticallyChecksForUpdates)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLogin = Launcher.isInstalledAtLogin()
        }
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { settings.updatePreferences.automaticallyChecksForUpdates },
            set: { newValue in
                settings.updatePreferences.automaticallyChecksForUpdates = newValue
                if !newValue && settings.updatePreferences.automaticallyDownloadsUpdates {
                    settings.updatePreferences.automaticallyDownloadsUpdates = false
                }
                settings.saveSettings()
            }
        )
    }

    private var autoDownloadBinding: Binding<Bool> {
        Binding(
            get: { settings.updatePreferences.automaticallyDownloadsUpdates },
            set: { newValue in
                settings.updatePreferences.automaticallyDownloadsUpdates = newValue
                settings.saveSettings()
            }
        )
    }

}

struct ServicesSettingsView: View {
    var appController: AppController?
    var initialServiceURL: String?
    @ObservedObject private var settings = Settings.shared
    @State private var selectedServiceID: Service.ID?

    init(appController: AppController?, initialServiceURL: String?) {
        self.appController = appController
        self.initialServiceURL = initialServiceURL
        if let url = initialServiceURL,
           let service = Settings.shared.services.first(where: { $0.url == url }) {
            _selectedServiceID = State(initialValue: service.id)
        } else if let url = appController?.currentServiceURL,
                  let service = Settings.shared.services.first(where: { $0.url == url }) {
            _selectedServiceID = State(initialValue: service.id)
        } else {
            _selectedServiceID = State(initialValue: Settings.shared.services.first?.id)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedServiceID) {
                ForEach(settings.services) { service in
                    HStack {
                        Image(systemName: "globe")
                        Text(service.name)
                    }
                    .tag(service.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedServiceID = service.id
                    }
                }
                .onDelete(perform: removeServices)
                .onMove(perform: moveServices)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 220, maxWidth: 260)
            .toolbar {
                ToolbarItem {
                    Button(action: addService) {
                        Label("Add Service", systemImage: "plus")
                    }
                }
            }

            Divider()

            Group {
                if let binding = bindingForSelectedService() {
                    ServiceDetailView(service: binding,
                                      appController: appController,
                                      selectedServiceID: $selectedServiceID)
                } else {
                    VStack {
                        Text("Select a service")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            syncSelectionWithCurrentService()
            ensureSelectionExists()
        }
        .onChange(of: appController?.currentServiceURL ?? "__none__") { _, _ in
            syncSelectionWithCurrentService()
        }
        .onChange(of: settings.services) { _, newServices in
            if let selectedServiceID,
               !newServices.contains(where: { $0.id == selectedServiceID }) {
                self.selectedServiceID = newServices.first?.id
            }
            settings.saveSettings()
            appController?.reloadServices()
        }
    }

    private func addService() {
        let newService = Service(name: "New Service", url: "https://example.com", focus_selector: "")
        settings.services.append(newService)
        selectedServiceID = newService.id
    }

    private func removeServices(at offsets: IndexSet) {
        let removedServices = offsets.compactMap { index -> Service? in
            guard settings.services.indices.contains(index) else { return nil }
            return settings.services[index]
        }
        settings.services.remove(atOffsets: offsets)
        removedServices.forEach { ActionScriptStorage.deleteScripts(for: $0.id) }
        ensureSelectionExists()
    }

    private func moveServices(from source: IndexSet, to destination: Int) {
        settings.services.move(fromOffsets: source, toOffset: destination)
        ensureSelectionExists()
    }

    private func bindingForSelectedService() -> Binding<Service>? {
        guard let selectedServiceID,
              let index = settings.services.firstIndex(where: { $0.id == selectedServiceID }) else {
            return nil
        }
        return $settings.services[index]
    }

    private func syncSelectionWithCurrentService() {
        guard let url = appController?.currentServiceURL,
              let service = settings.services.first(where: { $0.url == url }) else {
            ensureSelectionExists()
            return
        }
        selectedServiceID = service.id
    }

    private func ensureSelectionExists() {
        if let selectedServiceID,
           settings.services.contains(where: { $0.id == selectedServiceID }) {
            return
        }
        selectedServiceID = settings.services.first?.id
    }
}

struct ServiceDetailView: View {
    enum DetailSelection: Hashable {
        case focus
        case action(UUID)
    }

    @Binding var service: Service
    var appController: AppController?
    @Binding var selectedServiceID: Service.ID?
    @State private var detailSelection: DetailSelection? = .focus
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack {
            Form {
                TextField("Name", text: $service.name)
                TextField("URL", text: $service.url)
            }
            .padding()

            Divider()

            advancedPane

            Spacer()
        }
        .navigationTitle(service.name)
        .toolbar {
            ToolbarItem {
                Button(action: {
                    if let index = Settings.shared.services.firstIndex(where: { $0.id == service.id }) {
                        let removedServiceID = service.id
                        Settings.shared.services.remove(at: index)
                        ActionScriptStorage.deleteScripts(for: removedServiceID)
                        selectedServiceID = nil
                    }
                }) {
                    Label("Remove Service", systemImage: "trash")
                }
            }
        }
        .onChange(of: settings.customActions) { _, newActions in
            if case .action(let id)? = detailSelection,
               !newActions.contains(where: { $0.id == id }) {
                detailSelection = .focus
            }
        }
    }

    private var advancedPane: some View {
        HStack(spacing: 0) {
            List(selection: $detailSelection) {
                Text("Focus Selector").tag(DetailSelection.focus)
                if !settings.customActions.isEmpty {
                    Section("Custom Actions") {
                        ForEach(settings.customActions) { action in
                            Text(action.name.isEmpty ? "Action" : action.name)
                                .tag(DetailSelection.action(action.id))
                        }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            Divider()

            switch detailSelection ?? .focus {
            case .focus:
                focusSelectorForm
            case .action(let id):
                if let action = settings.customActions.first(where: { $0.id == id }) {
                    ActionScriptEditor(action: action,
                                       script: scriptBinding(for: id),
                                       openExternally: { openScriptInEditor(actionID: id) })
                } else {
                    emptySelectionView
                }
            }
        }
    }

    private var focusSelectorForm: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Focus Selector (CSS Selector)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $service.focus_selector)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                    .padding(.top, 15)
            }
        }
        .padding()
    }

    private var emptySelectionView: some View {
        VStack {
            Text("Select an action")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadScript(actionID: UUID) -> String {
        ActionScriptStorage.loadScript(
            serviceID: service.id,
            actionID: actionID,
            fallback: service.actionScripts[actionID] ?? ""
        )
    }

    private func scriptBinding(for actionID: UUID) -> Binding<String> {
        Binding(
            get: { loadScript(actionID: actionID) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    service.actionScripts.removeValue(forKey: actionID)
                    ActionScriptStorage.deleteScript(serviceID: service.id, actionID: actionID)
                } else {
                    service.actionScripts[actionID] = newValue
                    ActionScriptStorage.saveScript(newValue, serviceID: service.id, actionID: actionID)
                }
                Settings.shared.saveSettings()
            }
        )
    }

    private func openScriptInEditor(actionID: UUID) {
        let contents = loadScript(actionID: actionID)
        ActionScriptStorage.openInDefaultEditor(serviceID: service.id, actionID: actionID, contents: contents)
    }
}

private struct ActionScriptEditor: View {
    var action: CustomAction
    @Binding var script: String
    var openExternally: () -> Void

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 8) {
                Text("JavaScript for \(action.name.isEmpty ? "Action" : action.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $script)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                Text("Leave blank to log the default 'Action not implemented' message.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("Open in Text Editor", action: openExternally)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .padding(.vertical)
        }
        .padding()
    }
}

// MARK: - Settings helpers

private struct SettingsSection<Content: View>: View {
    var title: String
    var content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        } label: {
            Text(title)
                .font(.headline)
        }
        .groupBoxStyle(DefaultGroupBoxStyle())
    }
}

private struct SettingsRow<Content: View>: View {
    var title: String
    var message: String?
    var content: () -> Content
    private let labelWidth: CGFloat = 230

    init(title: String, message: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.message = message
        self.content = content
    }

    var body: some View {
        HStack(alignment: message == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: labelWidth, alignment: .leading)

            Spacer(minLength: 16)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var message: String?
    @Binding var isOn: Bool

    init(title: String, message: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.message = message
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title: title, message: message) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}


extension Bundle {
    var versionDisplayString: String {
        let shortVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case let (short?, build?) where short != build:
            return "\(short) (\(build))"
        case let (short?, _):
            return short
        case let (_, build?):
            return build
        default:
            return "Unknown"
        }
    }
}
