import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct SettingsView: View {
    @State private var selectedTab = "Services"
    var appController: AppController?
    var initialServiceURL: String?

    var body: some View {
        TabView(selection: $selectedTab) {
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

            GeneralSettingsView(appController: appController)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("General")
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct GeneralSettingsView: View {
    var appController: AppController?
    @State private var launchAtLogin = Launcher.isInstalledAtLogin()
    private let versionDescription = Bundle.main.versionDisplayString

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        if value {
                            appController?.installAtLogin(nil)
                        } else {
                            appController?.uninstallFromLogin(nil)
                        }
                    }
            }

            Section {
                HStack {
                    Text("Current version")
                    Spacer()
                    Text(versionDescription)
                        .font(.body)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .accessibilityIdentifier("current-version-label")
            }
        }
        .padding()
        .onAppear {
            launchAtLogin = Launcher.isInstalledAtLogin()
        }
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
        .onChange(of: appController?.currentServiceURL ?? "__none__") { _ in
            syncSelectionWithCurrentService()
        }
        .onChange(of: settings.services) { _ in
            if let selectedServiceID,
               !settings.services.contains(where: { $0.id == selectedServiceID }) {
                self.selectedServiceID = settings.services.first?.id
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
    @State private var selectedTab = "General"
    @State private var detailSelection: DetailSelection? = .focus
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text("General").tag("General")
                Text("Advanced").tag("Advanced")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 8)

            if selectedTab == "General" {
                Form {
                    TextField("Name", text: $service.name)
                    TextField("URL", text: $service.url)
                }
                .padding()
            } else {
                advancedPane
            }

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
        .onChange(of: selectedTab) { tab in
            if tab != "Advanced" {
                detailSelection = .focus
            } else if detailSelection == nil {
                detailSelection = .focus
            }
        }
        .onChange(of: settings.customActions) { actions in
            if case .action(let id)? = detailSelection,
               !actions.contains(where: { $0.id == id }) {
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


private extension Bundle {
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
