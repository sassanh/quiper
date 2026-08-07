import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var pendingEngineDeletion: Service?
    @State private var pendingActionDeletion: CustomAction?

    var body: some View {
        NavigationStack {
            Form {
                enginesSection
                actionsSection
                promptHistorySection
                behaviorSection
                appearanceSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete \(pendingEngineDeletion?.name ?? "Engine")?",
                isPresented: engineDeletePresented
            ) {
                Button("Delete Engine", role: .destructive) {
                    if let service = pendingEngineDeletion {
                        environment.removeService(service.id)
                    }
                    pendingEngineDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingEngineDeletion = nil
                }
            } message: {
                Text("This engine's sessions, drafts, and prompt history will be removed.")
            }
            .alert(
                "Delete \(pendingActionDeletion?.name.isEmpty == false ? pendingActionDeletion!.name : "Action")?",
                isPresented: actionDeletePresented
            ) {
                Button("Delete Action", role: .destructive) {
                    if let action = pendingActionDeletion {
                        environment.removeAction(id: action.id)
                    }
                    pendingActionDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingActionDeletion = nil
                }
            } message: {
                Text("This action and its engine scripts will be removed.")
            }
        }
    }

    private var engineDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingEngineDeletion != nil },
            set: { if !$0 { pendingEngineDeletion = nil } }
        )
    }

    private var actionDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingActionDeletion != nil },
            set: { if !$0 { pendingActionDeletion = nil } }
        )
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
                if let index = offsets.first, environment.services.indices.contains(index) {
                    pendingEngineDeletion = environment.services[index]
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
                if let index = offsets.first, environment.customActions.indices.contains(index) {
                    pendingActionDeletion = environment.customActions[index]
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
            Toggle("Record Cleared Drafts", isOn: $environment.promptHistoryRecordOnCmdBackspace)
            Toggle("Record on Selection Clear", isOn: $environment.promptHistoryRecordOnSelectionClear)
            Stepper(value: $environment.promptHistoryLimit, in: 10...500, step: 10) {
                Text("History Limit: \(environment.promptHistoryLimit)")
            }
        } header: {
            Text("Prompt History")
        } footer: {
            Text("A prompt is saved when it's sent, when the draft is cleared with Cmd+Backspace, or when its text is replaced.")
        }
    }

    private var behaviorSection: some View {
        Section {
            Picker("Tab Survival", selection: $environment.tabSurvivalPolicy) {
                ForEach(TabSurvivalPolicy.allCases.filter { $0 != .askOnExit }) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            Stepper(value: $environment.tabNavigationRingSize, in: 2...10) {
                Text("Tab Navigation Ring Size: \(environment.tabNavigationRingSize)")
            }
            Toggle("Automatically Switch Engine", isOn: $environment.automaticallySwitchEngineOnLastSessionClose)
            Toggle("Auto-Create Session on Empty Engine", isOn: $environment.autoCreateSessionOnEmptyEngineActivation)
            Toggle("Purge Dangling Web Data", isOn: $environment.shouldPurgeDanglingWebData)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Closing the last session of an engine switches to the nearest engine with sessions. Tabs reopen on launch unless Tab Survival is set to Never Restore.")
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
    @State private var showingDeleteConfirmation = false
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
            Section {
                NavigationLink {
                    RoutingRulesEditView(service: $service)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Routing Rules")
                        Spacer()
                        if !service.routingRules.isEmpty {
                            Text("\(service.routingRules.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Link Routing")
            } footer: {
                Text("Rules decide how links are opened. They run from top to bottom and the first match wins; unmatched links open externally.")
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
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete engine")
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
        .alert(
            "Delete \(service.name)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Engine", role: .destructive) {
                environment.removeService(service.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This engine's sessions, drafts, and prompt history will be removed.")
        }
        .alert(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation
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
    @State private var showingDeleteConfirmation = false

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
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete action")
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
        .alert(
            "Delete \(action.name.isEmpty ? "Action" : action.name)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Action", role: .destructive) {
                environment.removeAction(id: action.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action and its engine scripts will be removed.")
        }
        .alert(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation
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

struct RoutingRulesEditView: View {
    @Binding var service: Service

    var body: some View {
        Form {
            Section {
                if service.routingRules.isEmpty {
                    Text("No routing rules defined. Links will open externally by default.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(service.routingRules.indices), id: \.self) { index in
                        RoutingRuleField(rule: $service.routingRules[index])
                    }
                    .onDelete { offsets in
                        service.routingRules.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        service.routingRules.move(fromOffsets: source, toOffset: destination)
                    }
                }
                Button {
                    service.routingRules.append(RoutingRule(pattern: "", action: .internalStay))
                } label: {
                    Label("Add Routing Rule", systemImage: "plus")
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules are evaluated from top to bottom. The first matching pattern determines the action. Reorder rules to adjust their priority.")
            }
        }
        .navigationTitle("Routing Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}
