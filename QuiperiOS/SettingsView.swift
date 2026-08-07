import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                enginesSection
                actionsSection
                promptHistorySection
                appearanceSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var enginesSection: some View {
        Section {
            ForEach(environment.services) { service in
                NavigationLink {
                    EngineEditView(service: service)
                        .environmentObject(environment)
                } label: {
                    HStack {
                        EngineIconView(service: service, size: 24)
                        Text(service.name)
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    let service = environment.services[offset]
                    environment.removeService(service.id)
                }
            }
            Button {
                environment.addService(
                    Service(name: "New Engine", url: "https://example.com", focus_selector: "")
                )
            } label: {
                Label("Add Engine", systemImage: "plus")
            }
        } header: {
            Text("Engines")
        } footer: {
            Text("Engines are the AI services Quiper opens. The focus selector targets the prompt input on each site.")
        }
    }

    private var actionsSection: some View {
        Section {
            ForEach(environment.customActions.indices, id: \.self) { index in
                let action = environment.customActions[index]
                NavigationLink {
                    ActionEditView(action: action)
                        .environmentObject(environment)
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text(action.name.isEmpty ? "Action" : action.name)
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    environment.removeAction(id: environment.customActions[offset].id)
                }
            }
            Menu {
                Button("Blank Action") {
                    environment.addBlankAction()
                }
                Divider()
                ForEach(environment.defaultActionTemplates) { template in
                    Button(template.name) {
                        environment.addAction(from: template)
                    }
                }
                Divider()
                Button {
                    environment.addAllActionTemplates()
                } label: {
                    Label("Add All Templates", systemImage: "plus.rectangle.on.rectangle")
                }
            } label: {
                Label("Add Action", systemImage: "plus")
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Actions run JavaScript in the active engine. iOS has no keyboard, so trigger them from the Actions button in the bottom bar.")
        }
    }

    private var promptHistorySection: some View {
        Section {
            Toggle("Enable Prompt History", isOn: $environment.enablePromptHistory)
            Toggle("Record Submitted Prompts", isOn: $environment.promptHistoryRecordOnSubmit)
            Stepper(value: $environment.promptHistoryLimit, in: 10...500, step: 10) {
                Text("History Limit: \(environment.promptHistoryLimit)")
            }
        } header: {
            Text("Prompt History")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Color Scheme", selection: $environment.colorScheme) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
        } header: {
            Text("Appearance")
        }
    }
}

struct EngineEditView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var service: Service
    @State private var originalService: Service
    @State private var showingDiscardConfirmation = false
    @State private var isFetchingIcon = false
    @Environment(\.dismiss) private var dismiss

    init(service: Service) {
        _service = State(initialValue: service)
        _originalService = State(initialValue: service)
    }

    private var isDirty: Bool {
        service != originalService
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $service.name)
                TextField("URL", text: $service.url)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section {
                HStack(spacing: 16) {
                    EngineIconView(service: service, size: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await fetchIconFromWebsite() }
                        } label: {
                            Label("Fetch from Website", systemImage: "arrow.down.circle")
                        }
                        .disabled(isFetchingIcon || service.url.isEmpty)
                        if service.iconBase64 != nil {
                            Button("Remove Icon", role: .destructive) {
                                service.iconBase64 = nil
                                service.iconManuallyUnset = true
                            }
                        }
                    }
                }
            } header: {
                Text("Icon")
            } footer: {
                Text("Automatically fetched from the engine's site when available, otherwise provided by the bundled defaults.")
            }
            Section {
                TextField("Focus Selector", text: $service.focus_selector)
                    .autocorrectionDisabled()
                Toggle("Preserve Prompt", isOn: $service.preservePrompt)
            } header: {
                Text("Prompt Input")
            } footer: {
                Text("The CSS selector Quiper uses to find the prompt input on this engine's page.")
            }
        }
        .navigationTitle(service.name)
        .navigationBarBackButtonHidden(isDirty)
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isDirty {
                    Button {
                        showingDiscardConfirmation = true
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    environment.updateService(service)
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .disabled(!isDirty)
            }
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes to this engine.")
        }
    }

    private func fetchIconFromWebsite() async {
        guard !isFetchingIcon else { return }
        isFetchingIcon = true
        defer { isFetchingIcon = false }
        if let base64 = await FaviconFetcher.fetchFavicon(for: service.url) {
            service.iconBase64 = base64
            service.iconManuallyUnset = false
        }
    }
}

struct ActionEditView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var action: CustomAction
    @State private var originalName: String
    @State private var showingDiscardConfirmation = false

    init(action: CustomAction) {
        _action = State(initialValue: action)
        _originalName = State(initialValue: action.name)
    }

    private var isDirty: Bool {
        action.name != originalName
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $action.name)
            }
            Section {
                ForEach(environment.services) { service in
                    NavigationLink {
                        ActionScriptEditView(action: action, service: service, environment: environment)
                    } label: {
                        Text(service.name)
                    }
                }
            } header: {
                Text("Engine Scripts")
            } footer: {
                Text("The JavaScript each engine runs when this action is triggered.")
            }
        }
        .navigationTitle(action.name.isEmpty ? "Action" : action.name)
        .navigationBarBackButtonHidden(isDirty)
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isDirty {
                    Button {
                        showingDiscardConfirmation = true
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    environment.renameAction(id: action.id, name: action.name)
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .disabled(!isDirty)
            }
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes to this action.")
        }
    }
}

struct ActionScriptEditView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let action: CustomAction
    let service: Service
    @State private var code: String
    @State private var originalCode: String

    init(action: CustomAction, service: Service, environment: AppEnvironment) {
        self.action = action
        self.service = service
        let initial = environment.actionScript(for: service, action: action)
        _code = State(initialValue: initial)
        _originalCode = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $code)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 300)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Script")
            } footer: {
                Text("JavaScript executed in \(service.name) when this action runs.")
            }
        }
        .navigationTitle("\(action.name.isEmpty ? "Action" : action.name) · \(service.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    environment.saveCustomActionScript(code, serviceID: service.id, actionID: action.id)
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .disabled(code == originalCode)
            }
        }
    }
}
