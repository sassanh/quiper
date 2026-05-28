import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Carbon
import AppKit
import UserNotifications
import WebKit

struct SettingsView: View {
    @State private var selectedTab = "Engines"
    @StateObject private var shortcutState = ShortcutRecordingState()
    var appController: AppController?
    var initialServiceURL: String?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ServicesSettingsView(appController: appController,
                                 initialServiceURL: initialServiceURL)
            .tabItem {
                Label("Engines", systemImage: "list.bullet")
            }
            .tag("Engines")
            
            KeyBindingsSettingsView(appController: appController)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag("Shortcuts")

            GeneralSettingsView(appController: appController)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("General")
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag("Appearance")
            
            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
                .tag("Updates")
        }
        .frame(minWidth: 720, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: .startGlobalHotkeyCapture)) { _ in
            selectedTab = "Shortcuts"
        }
        .environmentObject(shortcutState)
        .overlay { ShortcutRecordingOverlay(state: shortcutState).allowsHitTesting(shortcutState.isPresenting) }
    }
}

struct GeneralSettingsView: View {
    var appController: AppController?
    @State private var launchAtLogin = Launcher.isInstalledAtLogin()
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var notificationDispatcher = NotificationDispatcher.shared

    @State private var showClearWebConfirmation = false
    @State private var showEraseEnginesConfirmation = false
    @State private var showEraseActionsConfirmation = false
    @State private var showImportConfirmation = false
    @State private var exportError: String?
    @State private var importError: String?
    @State private var exportSuccessMessage: String?

    
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
                    
                    SettingsDivider()
                    
                    SettingsToggleRow(
                        title: "Purge orphaned cache data",
                        message: "Identify and automatically delete orphaned, persistent WebKit caches left behind by deleted engines at startup to preserve disk space.",
                        isOn: $settings.shouldPurgeDanglingWebData
                    )
                    .onChange(of: settings.shouldPurgeDanglingWebData) { _, _ in
                        settings.saveSettings()
                    }
                }
                
                SettingsSection(title: "Behavior") {
                    SettingsToggleRow(
                        title: "Automatically switch engines",
                        message: "When you close the last session of an engine, automatically switch to the last active session of another engine instead of staying on the current engine.",
                        isOn: $settings.automaticallySwitchEngineOnLastSessionClose
                    )
                    .onChange(of: settings.automaticallySwitchEngineOnLastSessionClose) { _, _ in
                        settings.saveSettings()
                    }
                    SettingsToggleRow(
                        title: "Auto-create session on engine activation",
                        message: "When you switch to an engine that has no open sessions, automatically create a new session. When disabled, the empty state is shown instead.",
                        isOn: $settings.autoCreateSessionOnEmptyEngineActivation
                    )
                    .onChange(of: settings.autoCreateSessionOnEmptyEngineActivation) { _, _ in
                        settings.saveSettings()
                    }
                }
                
                SettingsSection(title: "Notifications") {
                    SettingsRow(
                        title: "Notification permission",
                        message: notificationPermissionMessage
                    ) {
                        HStack {
                            Text(notificationPermissionStatus)
                                .foregroundColor(notificationPermissionColor)
                                .font(.callout)
                            
                            Button("Open System Settings") {
                                notificationDispatcher.openSystemNotificationSettings()
                            }
                        }
                    }
                }
                
                SettingsSection(title: "Config") {
                    SettingsRow(
                        title: "Export Config",
                        message: "Save all settings and action scripts to a .quiper file."
                    ) {
                        Button("Export") {
                            ConfigPortManager.showExportPanel(in: NSApp.keyWindow) { result in
                                switch result {
                                case .success(let url):
                                    exportSuccessMessage = "Config exported to \(url.lastPathComponent)"
                                case .failure(let error):
                                    exportError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    SettingsRow(
                        title: "Import Config",
                        message: "Restore settings and action scripts from a .quiper file. This will overwrite your current configuration."
                    ) {
                        Button("Import") {
                            ConfigPortManager.showImportPanel(in: NSApp.keyWindow) { result in
                                if case .failure(let error) = result {
                                    importError = error.localizedDescription
                                } else {
                                    appController?.reloadServices()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                SettingsSection(title: "Danger Zone", cardBackground: Color.red.opacity(0.05)) {
                    SettingsRow(title: "Clear All Web Data",
                                message: "Delete cookies, caches, and storage for every engine so all sites behave like fresh logins.") {
                        Button(role: .destructive) {
                            showClearWebConfirmation = true
                        } label:{
                            Text("Clear All Web Data")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    
                    Divider()
                    
                    SettingsRow(title: "Erase All Engines",
                                message: "Remove every configured service and its stored scripts.") {
                        Button(role: .destructive) {
                            showEraseEnginesConfirmation = true
                        } label: {
                            Text("Erase All Engines")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    
                    Divider()
                    
                    SettingsRow(title: "Erase All Actions",
                                message: "Delete every custom action and its scripts across services.") {
                        Button(role: .destructive) {
                            showEraseActionsConfirmation = true
                        } label: {
                            Text("Erase All Actions")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLogin = Launcher.isInstalledAtLogin()
            Task { await notificationDispatcher.refreshNotificationStatus() }
        }
        .alert("Clear saved web data for all engines?", isPresented: $showClearWebConfirmation) {
            Button("Clear All", role: .destructive) {
                clearWebData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes cookies, caches, and storage for every service/engine.")
        }
        .alert("Erase all engines?", isPresented: $showEraseEnginesConfirmation) {
            Button("Erase", role: .destructive) {
                eraseAllEngines()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes every service and its local scripts.")
        }
        .alert("Erase all actions?", isPresented: $showEraseActionsConfirmation) {
            Button("Erase", role: .destructive) {
                eraseAllActions()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes every custom action and the scripts stored for them.")
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Export successful", isPresented: Binding(get: { exportSuccessMessage != nil }, set: { if !$0 { exportSuccessMessage = nil } })) {
            Button("OK", role: .cancel) { exportSuccessMessage = nil }
        } message: {
            Text(exportSuccessMessage ?? "")
        }
    }
    
    private func clearWebData() {
        appController?.clearWebViewData(nil)
    }
    
    private func eraseAllEngines() {
        let ids = settings.services.map { $0.id }
        settings.services.removeAll()
        ids.forEach { ActionScriptStorage.deleteScripts(for: $0) }
        settings.saveSettings()
        appController?.reloadServices()
    }
    
    private func eraseAllActions() {
        for index in settings.services.indices {
            let serviceID = settings.services[index].id
            settings.services[index].actionScripts.removeAll()
            ActionScriptStorage.deleteScripts(for: serviceID)
        }
        settings.customActions.removeAll()
        settings.saveSettings()
        settings.saveSettings()
        appController?.reloadServices()
    }
    
    private var notificationPermissionStatus: String {
        switch notificationDispatcher.authorizationStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    private var notificationPermissionColor: Color {
        switch notificationDispatcher.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
    
    private var notificationPermissionMessage: String {
        switch notificationDispatcher.authorizationStatus {
        case .authorized:
            return "Quiper can send notifications for engine responses."
        case .denied:
            return "Notifications are disabled. Enable them in System Settings to see engine responses."
        case .notDetermined:
            return "Permission has not been requested yet."
        default:
            return "Quiper needs notification access to show engine responses."
        }
    }
}

struct ServicesSettingsView: View {
    var appController: AppController?
    var initialServiceURL: String?
    @ObservedObject private var settings = Settings.shared
    @State private var selectedServiceID: Service.ID?
    @State private var pendingServiceDeletion: PendingServiceDeletion?
    
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
            serviceList
            Divider()
            serviceDetail
        }
        .alert(item: $pendingServiceDeletion) { pending in
            Alert(
                title: Text(pending.title),
                message: Text("Deleting a service clears its sessions and custom action scripts."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteServices(ids: pending.ids)
                },
                secondaryButton: .cancel()
            )
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

    private var serviceList: some View {
        List(selection: $selectedServiceID) {
            ForEach(settings.services) { service in
                HStack {
                    if let base64 = service.iconBase64,
                       let data = Data(base64Encoded: base64),
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .cornerRadius(3)
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                    Text(service.name)
                }
                .tag(service.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedServiceID = service.id
                }
            }
            .onDelete(perform: requestRemoveServices)
            .onMove(perform: moveServices)
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 140, idealWidth: 150, maxWidth: 160)
        .toolbar {
            ToolbarItemGroup {
                Button(role: .destructive, action: deleteSelectedService) {
                    Label("Delete Service", systemImage: "trash")
                }
                .disabled(selectedServiceID == nil)

                Menu {
                    Button("Blank Service") {
                        addService()
                    }
                    if !settings.defaultServiceTemplates.isEmpty {
                        Divider()
                        ForEach(settings.defaultServiceTemplates) { template in
                            Button(template.name) {
                                addService(from: template)
                            }
                        }
                        Divider()
                        Button {
                            addAllTemplates()
                        } label: {
                            Label("Add All Templates", systemImage: "plus.rectangle.on.rectangle")
                        }
                    }
                } label: {
                    Label("Add Service", systemImage: "plus")
                }
                .accessibilityIdentifier("Add Service")
                .help("Create a blank service or add one from templates")
            }
        }
    }

    private var serviceDetail: some View {
        Group {
            if let binding = bindingForSelectedService() {
                ServiceDetailView(service: binding,
                                  appController: appController,
                                  selectedServiceID: $selectedServiceID,
                                  requestDelete: { service in
                    confirmServiceDeletion(ids: [service.id])
                })
                .id(binding.id)
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
    
    func addService() {
        let newService = Service(name: "New Service", url: "https://example.com", focus_selector: "")
        settings.services.append(newService)
        selectedServiceID = newService.id
    }
    
    private func addService(from template: Service, enrichIcons: Bool = true) {
        var service = template
        service.id = UUID()
        service.actionScripts = [:]
        applyDefaultScripts(from: template, to: &service)
        settings.services.append(service)
        selectedServiceID = service.id
        settings.saveSettings()
        if enrichIcons {
            settings.enrichMissingIconsIfNeeded()
        }
    }
    
    private func addAllTemplates() {
        var knownNames = Set(settings.services.map { $0.name.lowercased() })
        var addedAny = false
        for template in settings.defaultServiceTemplates {
            let key = template.name.lowercased()
            guard !knownNames.contains(key) else { continue }
            addService(from: template, enrichIcons: false)
            knownNames.insert(key)
            addedAny = true
        }
        if addedAny {
            settings.enrichMissingIconsIfNeeded()
        }
    }
    
    private func applyDefaultScripts(from template: Service, to service: inout Service) {
        let trimmedActions = settings.customActions
        for action in trimmedActions {
            guard let defaultID = settings.defaultActionID(matching: action.name),
                  let templateScript = template.actionScripts[defaultID],
                  !templateScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            service.actionScripts[action.id] = templateScript
            ActionScriptStorage.saveScript(templateScript, serviceID: service.id, actionID: action.id)
        }
    }
    
    private func requestRemoveServices(at offsets: IndexSet) {
        let ids = offsets.compactMap { index -> Service.ID? in
            guard settings.services.indices.contains(index) else { return nil }
            return settings.services[index].id
        }
        confirmServiceDeletion(ids: ids)
    }
    
    private func confirmServiceDeletion(ids: [Service.ID]) {
        guard !ids.isEmpty else { return }
        let names = ids.compactMap { id in
            settings.services.first(where: { $0.id == id })?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title: String
        if ids.count == 1, let name = names.first, !name.isEmpty {
            title = "Delete \(name)?"
        } else if ids.count == 1 {
            title = "Delete this service?"
        } else {
            title = "Delete \(ids.count) services?"
        }
        pendingServiceDeletion = PendingServiceDeletion(ids: ids, title: title)
    }
    
    private func deleteServices(ids: [Service.ID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let removedServices = settings.services.filter { idSet.contains($0.id) }
        settings.services.removeAll { idSet.contains($0.id) }
        removedServices.forEach { service in
            ActionScriptStorage.deleteScripts(for: service.id)
            WKWebsiteDataStore.remove(forIdentifier: service.id) { _ in }
        }
        ensureSelectionExists()
        settings.saveSettings()
        appController?.reloadServices()
    }
    
    private func deleteSelectedService() {
        guard let selectedServiceID else { return }
        confirmServiceDeletion(ids: [selectedServiceID])
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
        case friendDomains
        case css
        case security
        case webData
        case action(UUID)
    }

    @Binding var service: Service
    var appController: AppController?
    @Binding var selectedServiceID: Service.ID?
    @State private var detailSelection: DetailSelection? = .security
    @ObservedObject private var settings = Settings.shared
    var requestDelete: (Service) -> Void

    @EnvironmentObject var shortcutState: ShortcutRecordingState
    
    @State private var isHoveringIcon = false
    @State private var currentFetchTask: Task<Void, Never>? = nil
    @FocusState private var isUrlFieldFocused: Bool
    @State private var showResetConfirmation = false
    @State private var showingDataMigrationAlert = false
    @State private var targetNewValue = false
    @State private var isMigratingData = false
    @State private var migrationMessage = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                // Interactive Icon Picker Button Menu
                Menu {
                    Button("Choose File...") {
                        chooseCustomIconFile()
                    }
                    Button("Fetch Automatically") {
                        Task {
                            await autoFetchIcon()
                        }
                    }
                    if service.iconBase64 != nil {
                        Button("Remove Icon", role: .destructive) {
                            service.iconBase64 = nil
                            service.iconManuallyUnset = true
                            settings.saveSettings()
                            NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
                        }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isHoveringIcon ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
                            )
                        
                        if let iconBase64 = service.iconBase64,
                           let data = Data(base64Encoded: iconBase64),
                           let nsImage = NSImage(data: data) {
                            let _ = { nsImage.size = NSSize(width: 40, height: 40) }()
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                        } else {
                            Image(systemName: "globe")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .padding(5)
                            }
                        }
                    }
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 64, height: 64)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isHoveringIcon = hovering
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Name:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField("Name", text: $service.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 8) {
                        Text("URL:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField("URL", text: $service.url)
                            .focused($isUrlFieldFocused)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
            
            // Layout below the divider handles floating hover preview seamlessly
            ZStack(alignment: .topLeading) {
                advancedPane
                
                if isHoveringIcon,
                   let iconBase64 = service.iconBase64,
                   let data = Data(base64Encoded: iconBase64),
                   let nsImage = NSImage(data: data) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("High-Res Preview")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: 160, height: 160)
                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 140, height: 140)
                                .cornerRadius(8)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.leading, 24)
                    .padding(.top, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading))
                    ))
                    .zIndex(100)
                }
            }
            
            Spacer()
        }
        .navigationTitle(service.name)
        .onChange(of: settings.customActions) { _, newActions in
            if case .action(let id)? = detailSelection,
               !newActions.contains(where: { $0.id == id }) {
                detailSelection = .focus
            }
        }
        .onDisappear {
            shortcutState.cancel()
        }
        .onChange(of: service.url) { _, newUrl in
            guard service.iconBase64 == nil && service.iconManuallyUnset != true else { return }
            guard !newUrl.isEmpty else { return }
            
            let serviceID = service.id
            currentFetchTask?.cancel()
            currentFetchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                    if Task.isCancelled { return }
                    
                    guard newUrl.contains(".") else { return }
                    
                    if let base64 = await FaviconFetcher.fetchFavicon(for: newUrl) {
                        if let idx = settings.services.firstIndex(where: { $0.id == serviceID }) {
                            if settings.services[idx].url == newUrl && settings.services[idx].iconBase64 == nil && settings.services[idx].iconManuallyUnset != true {
                                settings.services[idx].iconBase64 = base64
                                settings.saveSettings()
                                NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
                            }
                        }
                    }
                } catch {
                    // Task was cancelled
                }
            }
        }
        .onChange(of: isUrlFieldFocused) { _, isFocused in
            if !isFocused {
                guard service.iconBase64 == nil && service.iconManuallyUnset != true else { return }
                guard !service.url.isEmpty && service.url.contains(".") else { return }
                
                let serviceID = service.id
                let targetUrl = service.url
                currentFetchTask?.cancel()
                Task {
                    if let base64 = await FaviconFetcher.fetchFavicon(for: targetUrl) {
                        if let idx = settings.services.firstIndex(where: { $0.id == serviceID }) {
                            if settings.services[idx].iconBase64 == nil && settings.services[idx].iconManuallyUnset != true {
                                settings.services[idx].iconBase64 = base64
                                settings.saveSettings()
                                NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
                            }
                        }
                    }
                }
            }
            }
            
            if isMigratingData {
                ZStack {
                    Color.black.opacity(0.15)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.2)
                        
                        Text(migrationMessage)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(width: 280)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    private func chooseCustomIconFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg]
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let base64 = FaviconFetcher.encodePNG(data: data) {
                service.iconBase64 = base64
                service.iconManuallyUnset = false
                settings.saveSettings()
                NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
            }
        }
    }

    @MainActor
    private func autoFetchIcon() async {
        let url = service.url
        let serviceID = service.id
        guard !url.isEmpty else { return }
        if let base64 = await FaviconFetcher.fetchFavicon(for: url) {
            if let idx = settings.services.firstIndex(where: { $0.id == serviceID }) {
                settings.services[idx].iconBase64 = base64
                settings.services[idx].iconManuallyUnset = false
                settings.saveSettings()
                NotificationCenter.default.post(name: .servicesIconsUpdated, object: nil)
            }
        }
    }


    private var advancedPane: some View {
        HStack(spacing: 0) {
            List(selection: $detailSelection) {
                Section("Storage & Security") {
                    Label("Secure Storage", systemImage: "lock.shield.fill")
                        .tag(DetailSelection.security)
                    Label("Web Data", systemImage: "cylinder.split.1x2.fill")
                        .tag(DetailSelection.webData)
                }

                Section("Routing") {
                    Label("Focus Selector", systemImage: "eye.fill")
                        .tag(DetailSelection.focus)
                    Label("Friend Domains", systemImage: "link")
                        .tag(DetailSelection.friendDomains)
                }
                
                Section("Customization") {
                    Label("Custom CSS", systemImage: "paintpalette.fill")
                        .tag(DetailSelection.css)
                }
                
                if !settings.customActions.isEmpty {
                    Section("Custom Actions") {
                        ForEach(settings.customActions) { action in
                            Label(action.name.isEmpty ? "Action" : action.name, systemImage: "play.circle.fill")
                                .tag(DetailSelection.action(action.id))
                        }
                    }
                }
            }
            .frame(minWidth: 160, idealWidth: 165, maxWidth: 180)
            
            Divider()
            
            switch detailSelection ?? .security {
            case .focus:
                focusSelectorForm
            case .friendDomains:
                friendDomainsForm
            case .css:
                customCSSForm
            case .security:
                securityForm
            case .webData:
                webDataForm
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Focus Selector")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text("Specify a CSS selector (e.g. input[type='text']) to automatically target and focus a text input whenever this engine launches or gains activation.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            CodeTextEditor(text: $service.focus_selector)
                .frame(minHeight: 140)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var friendDomainsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Friend Domains")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text("Define regular expression patterns to allow link clicks, popups, and OAuth login flows matching these domains to stay inside this engine instead of routing to external apps.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(service.friendDomains.indices), id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("e.g. ^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", text: $service.friendDomains[index])
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button(role: .destructive) {
                            service.friendDomains.remove(at: index)
                            settings.saveSettings()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove domain pattern")
                    }
                }
                Button {
                    service.friendDomains.append("")
                } label: {
                    Label("Add Friend Domain", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var customCSSForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Custom CSS Stylesheet")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text("Inject raw CSS layout rules directly into the target webpage DOM at launch to customize colors, fonts, or hide unwanted UI elements.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            CodeTextEditor(text: Binding(
                get: { service.customCSS ?? "" },
                set: { service.customCSS = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 140)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor @ViewBuilder
    private var securityForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Secure Storage & Privacy")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text("Quiper isolates this engine's disk data inside a dedicated storage partition. You can protect it with military-grade encryption and auto-lock policies.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Experimental Warning Callout Card
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Experimental Security Feature")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("SparseBundle local storage encryption is currently in beta. While engineered for maximum privacy and TouchID protection, unexpected OS detaches, key failures, or filesystem errors could lead to session disruption or data loss. We strongly recommend regular backups of your critical account credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Encrypt Engine Local Storage")
                            .font(.body)
                        Text("Hardware-boosted APFS SparseBundle protected by Keychain & Touch ID.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { service.isEncrypted },
                        set: { newValue in
                            targetNewValue = newValue
                            showingDataMigrationAlert = true
                        }
                    ))
                    .toggleStyle(.switch)
                }
                
                if service.isEncrypted {
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Lock Policy")
                                .font(.body)
                            Text("Decide when this engine's storage locks and detaches.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { service.autoLockPolicy },
                            set: { newValue in
                                service.autoLockPolicy = newValue
                                settings.saveSettings()
                                appController?.reloadServices()
                            }
                        )) {
                            ForEach(AutoLockPolicy.allCases) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }
                    
                    if service.autoLockPolicy == .afterInactivity {
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inactivity Timeout")
                                    .font(.body)
                                Text("Specify minutes of idle time before this engine locks.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Stepper(value: Binding(
                                get: { service.autoLockInactivityTimeout },
                                set: { newValue in
                                    service.autoLockInactivityTimeout = max(1, newValue)
                                    settings.saveSettings()
                                    appController?.reloadServices()
                                }
                            ), in: 1...1440) {
                                Text("\(service.autoLockInactivityTimeout) min")
                                    .font(.body.monospacedDigit())
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Preserve Existing Web Data?", isPresented: $showingDataMigrationAlert) {
            Button("Yes, Transfer Data") {
                performDataMigration(transferData: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("No, Start Fresh", role: .destructive) {
                performDataMigration(transferData: false)
            }
            Button("Cancel", role: .cancel) {
                // Do nothing
            }
        } message: {
            Text(targetNewValue 
                ? "Do you want to transfer your current login sessions, cookies, and local storage into the encrypted partition, or start with a clean slate?"
                : "Do you want to extract your login sessions and web data out of the encrypted partition back to standard storage, or permanently discard all data?")
        }
    }

    @MainActor
    private func performDataMigration(transferData: Bool) {
        let isSecuring = targetNewValue
        let serviceID = service.id
        
        isMigratingData = true
        SecureDataMigrationManager.shared.isMigrationPending = true
        migrationMessage = isSecuring ? "Securing engine storage..." : "Unsecuring engine storage..."
        
        if isSecuring {
            // 1. Generate key first so we can mount/create
            let randomKey = SecureStorageManager.shared.generateRandomKey()
            _ = SecureStorageManager.shared.saveKeyToKeychain(randomKey, for: serviceID)
            
            // 2. Backup if requested
            let backupSuccess: Bool
            if transferData {
                migrationMessage = "Backing up session data..."
                backupSuccess = SecureDataMigrationManager.shared.backupData(for: serviceID)
            } else {
                backupSuccess = true
            }
            
            Task {
                do {
                    // 3. Create volume & mount
                    migrationMessage = "Creating encrypted volume..."
                    try await EncryptedVolumeManager.shared.createVolume(for: serviceID, passphrase: randomKey)
                    
                    migrationMessage = "Mounting encrypted partition..."
                    try await EncryptedVolumeManager.shared.mountVolume(for: serviceID, passphrase: randomKey)
                    
                    // 4. Restore backup if requested and backup succeeded
                    if transferData && backupSuccess {
                        migrationMessage = "Transferring session data..."
                        SecureDataMigrationManager.shared.restoreData(for: serviceID)
                    } else {
                        SecureDataMigrationManager.shared.discardBackup(for: serviceID)
                    }
                    
                    // 5. Update settings properties
                    service.isEncrypted = true
                    settings.saveSettings()
                    appController?.reloadServices()
                    
                    NSLog("[DataMigration] Engine \(serviceID) successfully secured (transferData: \(transferData))")
                } catch {
                    NSLog("[DataMigration] Securing failed with error: \(error.localizedDescription)")
                }
                
                isMigratingData = false
                SecureDataMigrationManager.shared.isMigrationPending = false
            }
        } else {
            // Unsecuring:
            Task {
                var backupSuccess = true
                if transferData {
                    // Check if it's currently locked
                    let isLocked = !EncryptedVolumeManager.shared.isUnlocked(for: serviceID)
                    if isLocked {
                        migrationMessage = "Authenticating to unlock partition..."
                        do {
                            // Retrieve key from Keychain (will trigger TouchID/Keychain prompt)
                            let key = try await SecureStorageManager.shared.retrieveKeyFromKeychain(for: serviceID)
                            
                            migrationMessage = "Unlocking encrypted partition..."
                            try await EncryptedVolumeManager.shared.mountVolume(for: serviceID, passphrase: key)
                        } catch {
                            // If user cancels or authentication fails, abort unsecuring!
                            NSLog("[DataMigration] Aborted unsecuring because authentication failed: \(error.localizedDescription)")
                            isMigratingData = false
                            SecureDataMigrationManager.shared.isMigrationPending = false
                            return
                        }
                    }
                    
                    migrationMessage = "Extracting session data..."
                    backupSuccess = SecureDataMigrationManager.shared.backupData(for: serviceID)
                }
                
                // 2. Unmount volume & delete physical bundle & keychain key
                migrationMessage = "Unmounting encrypted partition..."
                try? await EncryptedVolumeManager.shared.unmountVolume(for: serviceID)
                
                migrationMessage = "Deleting encrypted volume..."
                EncryptedVolumeManager.shared.deleteVolume(for: serviceID)
                SecureStorageManager.shared.deleteKeyFromKeychain(for: serviceID)
                
                // 3. Restore backup back to standard directory
                if transferData && backupSuccess {
                    migrationMessage = "Restoring session data..."
                    SecureDataMigrationManager.shared.restoreData(for: serviceID)
                } else {
                    SecureDataMigrationManager.shared.discardBackup(for: serviceID)
                }
                
                // 4. Update settings properties
                service.isEncrypted = false
                settings.saveSettings()
                appController?.reloadServices()
                
                NSLog("[DataMigration] Engine \(serviceID) successfully unsecured (transferData: \(transferData))")
                
                isMigratingData = false
                SecureDataMigrationManager.shared.isMigrationPending = false
            }
        }
    }

    @MainActor
    private var webDataPath: String {
        EncryptedVolumeManager.shared.getMountPointURL(for: service.id).path
    }

    @MainActor
    private var isWebDataLocked: Bool {
        service.isEncrypted && !EncryptedVolumeManager.shared.isUnlocked(for: service.id)
    }

    @MainActor @ViewBuilder
    private var webDataForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Web Data Management")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text("Quiper runs each engine inside a fully isolated sandboxed database. All cookies, local storage, databases, and caches are separated from other engines.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if isWebDataLocked {
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Text("Engine Storage is Locked")
                        .font(.headline)
                    
                    Text("This engine's storage is encrypted and locked. Please unlock the engine from the main overlay window in order to manage or reset its web data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Database Storage Path")
                        .font(.headline)
                    
                    HStack {
                        Text(webDataPath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(webDataPath, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .help("Copy full path to clipboard")
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            let url = URL(fileURLWithPath: webDataPath)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset Web Data...", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Reset all web data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetWebData()
            }
        } message: {
            Text("This will permanently clear all cookies, local storage, databases, and cache for '\(service.name)'. You will be logged out of all sites within this engine.")
        }
    }

    @MainActor
    private func resetWebData() {
        let serviceID = service.id
        let store = WKWebsiteDataStore(forIdentifier: serviceID)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        store.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
            Task { @MainActor in
                let mountPoint = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID)
                let fileManager = FileManager.default
                
                // Clear the directory contents
                if let contents = try? fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil) {
                    for item in contents {
                        try? fileManager.removeItem(at: item)
                    }
                }
                
                // Dispatch notification to reload live WebViews
                NotificationCenter.default.post(name: .webDataCleared, object: serviceID)
            }
        }
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

private struct PendingServiceDeletion: Identifiable {
    let id = UUID()
    let ids: [Service.ID]
    let title: String
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
                CodeTextEditor(text: $script)
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .autocorrectionDisabled(true) // Disable autocorrect
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

#if os(macOS)
private struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        init(parent: CodeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
#else
private struct CodeTextEditor: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
    }
}
#endif




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

