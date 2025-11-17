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
        settings.services.remove(atOffsets: offsets)
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
    @Binding var service: Service

    var appController: AppController?

    @Binding var selectedServiceID: Service.ID?

    @State private var selectedTab = "General"



    var body: some View {

        VStack {

            Picker("", selection: $selectedTab) {

                Text("General").tag("General")

                Text("Advanced").tag("Advanced")

            }

            .pickerStyle(SegmentedPickerStyle())

            .padding()



            if selectedTab == "General" {

                Form {

                    TextField("Name", text: $service.name)

                    TextField("URL", text: $service.url)

                }

                .padding()

            } else {

                Form {

                    VStack(alignment: .leading) {

                        Text("Focus Selector (CSS Selector)")

                            .font(.caption)

                            .foregroundColor(.secondary)

                        TextEditor(text: $service.focus_selector)

                            .font(.system(.body, design: .monospaced))

                            .frame(minHeight: 100)

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

            

            Spacer()

        }

        .navigationTitle(service.name)

        .toolbar {

            ToolbarItem {

                Button(action: {
                    if let index = Settings.shared.services.firstIndex(where: { $0.id == service.id }) {
                        Settings.shared.services.remove(at: index)
                        selectedServiceID = nil
                    }
                }) {

                    Label("Remove Service", systemImage: "trash")

                }

            }

        }

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
