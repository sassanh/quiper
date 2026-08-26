import SwiftUI
import UIKit

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
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in environment.registerUserActivity() }
        )
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
                        Spacer()
                        if service.isEncrypted {
                            Image(systemName: environment.isServiceLocked(service.id) ? "lock.fill" : "lock.open.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("settings-engine-\(service.id.uuidString)")
            }
            .onDelete { offsets in
                if let index = offsets.first, environment.services.indices.contains(index) {
                    pendingEngineDeletion = environment.services[index]
                }
            }
            let availableTemplates = environment.defaultServiceTemplates.filter { template in
                !environment.services.contains {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        == template.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
            }
            let cloudTemplates = availableTemplates.filter {
                !DefaultEngineDefinitions.localTemplateNames.contains(
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
            let localTemplates = availableTemplates.filter {
                DefaultEngineDefinitions.localTemplateNames.contains(
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
            Menu {
                Button("Blank Engine") {
                    environment.addService(
                        Service(name: "New Engine", url: "https://example.com", focus_selector: "")
                    )
                }
                if !cloudTemplates.isEmpty || !localTemplates.isEmpty {
                    Divider()
                    ForEach(cloudTemplates) { template in
                        Button(template.name) {
                            environment.addService(from: template)
                        }
                    }
                    if !cloudTemplates.isEmpty && !localTemplates.isEmpty {
                        Divider()
                    }
                    ForEach(localTemplates) { template in
                        Button(template.name) {
                            environment.addService(from: template)
                        }
                    }
                    Divider()
                    Button {
                        environment.addAllServiceTemplates()
                    } label: {
                        Label("Add All Templates", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
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
            Text("Actions run JavaScript in the active engine. Trigger them from the toolbar, App Shortcuts, or a configured hardware-keyboard shortcut.")
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
            if environment.iosHardwareKeyboardSettings.hasSeenHardwareKeyboard {
                NavigationLink {
                    HardwareKeyboardSettingsView()
                        .environmentObject(environment)
                } label: {
                    HStack {
                        Label("Hardware Keyboard", systemImage: "keyboard")
                        Spacer()
                        Text(environment.isHardwareKeyboardConnected ? "Connected" : "Not Connected")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("hardware-keyboard-settings")
            }
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Toolbar Position")
                ToolbarPositionPicker(selection: toolbarPositionBinding)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Places the browsing controls at the top or bottom edge.")
        }
    }

    private var toolbarPositionBinding: Binding<DragAreaPosition> {
        Binding(
            get: { environment.dragAreaPosition },
            set: { position in
                environment.dragAreaPosition = position
                environment.save()
            }
        )
    }
}

private struct ToolbarPositionPicker: View {
    @Binding var selection: DragAreaPosition

    var body: some View {
        HStack(spacing: 12) {
            positionButton(.top)
            positionButton(.bottom)
        }
    }

    private func positionButton(_ position: DragAreaPosition) -> some View {
        let isSelected = selection == position
        return Button {
            selection = position
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: position == .top ? .top : .bottom) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                        .frame(width: 44, height: 76)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: 36, height: 9)
                        .padding(.vertical, 4)
                }
                Text(position.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.12 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toolbar at \(position.rawValue.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EngineEditView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var service: Service
    @State private var originalService: Service
    @State private var showingDiscardConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isFetchingIcon = false
    @State private var protectionDisclosure: ProtectionDisclosure?
    @Environment(\.dismiss) private var dismiss

    init(service: Service) {
        _service = State(initialValue: service)
        _originalService = State(initialValue: service)
    }

    private var isDirty: Bool {
        service != originalService
    }

    private var isTemplateSelectorBacked: Bool {
        ActionScripts.defaultPromptInputSelector(for: service) != nil
    }

    private var isTemplateSelectorInSync: Bool {
        isTemplateSelectorBacked && service.templatePromptInputSelectorSync
    }

    private func toggleTemplateSelectorSync(_ newValue: Bool) {
        guard let defaultSelector = ActionScripts.defaultPromptInputSelector(for: service) else { return }
        service.templatePromptInputSelectorSync = newValue
        if newValue {
            service.focus_selector = ""
        } else {
            service.focus_selector = defaultSelector
        }
    }

    var body: some View {
        Form {
            if environment.isServiceLocked(service.id) {
                Section {
                    TextField("Name", text: $service.name)
                        .accessibilityIdentifier("engine-edit-name-\(service.id.uuidString)")
                    Label("Unlock this engine to edit its URL, prompt selector, icon, routing rules, or custom CSS.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Protected Details")
                }
            } else {
                Section("Details") {
                TextField("Name", text: $service.name)
                    .accessibilityIdentifier("engine-edit-name-\(service.id.uuidString)")
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
                if isTemplateSelectorBacked {
                    LatestDefaultToggle(
                        isInSync: isTemplateSelectorInSync,
                        syncedDescription: "This selector follows Quiper's bundled engine template and updates automatically.",
                        customDescription: "This engine uses a custom editable selector.",
                        setInSync: toggleTemplateSelectorSync
                    )
                }
                CodeEditorView(
                    code: Binding(
                        get: { ActionScripts.resolvedPromptInputSelector(for: service) },
                        set: { newValue in
                            guard !isTemplateSelectorInSync else { return }
                            service.focus_selector = newValue
                        }
                    ),
                    language: .cssSelector,
                    isReadOnly: isTemplateSelectorInSync
                )
                .frame(minHeight: 150)
                Toggle("Preserve Prompt", isOn: $service.preservePrompt)
            } header: {
                Text("Prompt Input")
            } footer: {
                Text(isTemplateSelectorInSync
                     ? "Quiper targets this engine's prompt input with the bundled template's selector."
                     : "The CSS selector Quiper uses to find the prompt input on this engine's page.")
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
            Section {
                NavigationLink {
                    CustomCSSEditView(service: $service)
                } label: {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                        Text("Custom CSS")
                        Spacer()
                        if service.templateCustomCSSSync {
                            Text("Latest Default")
                                .foregroundStyle(.secondary)
                        } else if let css = service.customCSS, !css.isEmpty {
                            Text("Custom")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Styling")
            } footer: {
                Text("Inject custom CSS into this engine's pages to adjust colors, fonts, or hide unwanted UI, or follow Quiper's bundled stylesheet for the engine.")
            }
            }
            securitySection
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
        .sheet(item: $protectionDisclosure) { disclosure in
            EngineProtectionDisclosureView(
                enabling: disclosure.enabling,
                engineName: service.name,
                isWorking: environment.securityOperationServiceIDs.contains(service.id),
                onConfirm: {
                    Task {
                        if disclosure.enabling {
                            await environment.enableProtection(for: service.id)
                        } else {
                            await environment.disableProtection(for: service.id)
                        }
                        syncFromEnvironment()
                        protectionDisclosure = nil
                    }
                },
                onCancel: { protectionDisclosure = nil }
            )
        }
        .onChange(of: environment.unlockedServiceIDs) {
            if environment.isServiceLocked(service.id) {
                syncFromEnvironment()
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        Section {
            if service.isEncrypted {
                LabeledContent("Status") {
                    Label(
                        environment.isServiceLocked(service.id) ? "Locked" : "Unlocked",
                        systemImage: environment.isServiceLocked(service.id) ? "lock.fill" : "lock.open.fill"
                    )
                    .foregroundStyle(environment.isServiceLocked(service.id) ? Color.secondary : Color.green)
                }
                Toggle("Lock When Leaving Engine", isOn: $service.lockOnSwitchAway)
                Toggle("Lock After Inactivity", isOn: $service.lockAfterInactivity)
                if service.lockAfterInactivity {
                    Stepper(value: $service.autoLockInactivityTimeout, in: 1...1440) {
                        Text("Inactivity: \(service.autoLockInactivityTimeout) min")
                    }
                }
                if environment.isServiceLocked(service.id) {
                    Button {
                        Task {
                            await environment.unlockService(service.id)
                            syncFromEnvironment()
                        }
                    } label: {
                        Label("Unlock Engine", systemImage: "lock.open")
                    }
                    .disabled(isDirty || environment.securityOperationServiceIDs.contains(service.id))
                } else {
                    Button {
                        environment.lockService(service.id)
                        syncFromEnvironment()
                    } label: {
                        Label("Lock Now", systemImage: "lock")
                    }
                    .disabled(isDirty)
                }
                Button("Remove Protection…", role: .destructive) {
                    protectionDisclosure = ProtectionDisclosure(enabling: false)
                }
                .disabled(isDirty || environment.securityOperationServiceIDs.contains(service.id))
            } else {
                Button {
                    protectionDisclosure = ProtectionDisclosure(enabling: true)
                } label: {
                    Label("Protect Engine…", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("protect-engine-\(service.id.uuidString)")
                .disabled(isDirty || environment.securityOperationServiceIDs.contains(service.id))
            }
            if let error = environment.securityError(for: service.id) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Security")
        } footer: {
            if isDirty {
                Text("Save or discard your current edits before changing protection.")
            } else if service.isEncrypted {
                Text("Protected engine details and browsing state are encrypted with a device-only key. Lock rules remain visible so iOS can enforce them.")
            } else {
                Text("Protect this engine’s configuration, drafts, prompt history, URLs, and titles with device authentication.")
            }
        }
    }

    private func syncFromEnvironment() {
        guard let updated = environment.services.first(where: { $0.id == service.id }) else { return }
        service = updated
        originalService = updated
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

private struct ProtectionDisclosure: Identifiable {
    let id = UUID()
    let enabling: Bool
}

private struct EngineProtectionDisclosureView: View {
    let enabling: Bool
    let engineName: String
    let isWorking: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: enabling ? "lock.shield.fill" : "lock.open.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(enabling ? Color.accentColor : Color.orange)
                    Text(enabling ? "Protect \(engineName)" : "Remove Protection")
                        .font(.largeTitle.bold())
                    Text(
                        enabling
                            ? "Review exactly what this protection covers before continuing."
                            : "Quiper will authenticate you, decrypt the protected profile, and return its contents to the shared settings document."
                    )
                    disclosureRow(
                        icon: "lock.doc.fill",
                        title: "Encrypted by Quiper",
                        detail: "The engine URL and configuration, custom scripts and CSS, routing rules, tab URLs and titles, drafts, and prompt history use AES-GCM with a unique key."
                    )
                    disclosureRow(
                        icon: "safari.fill",
                        title: "Website Data Is Isolated",
                        detail: "Cookies, local storage, IndexedDB, service workers, and caches live in this engine’s own WebKit store. iOS Complete Data Protection protects that store while the device is locked; it is not encrypted with Quiper’s AES key."
                    )
                    disclosureRow(
                        icon: "eye",
                        title: "What Remains Visible",
                        detail: "The engine name, protection status, and lock rules remain in settings so Quiper can identify and lock the engine. Protected notification previews are redacted."
                    )
                    disclosureRow(
                        icon: "arrow.down.doc",
                        title: "Downloads Are Separate",
                        detail: "Downloaded files remain in Quiper’s Files-accessible Downloads folder and are outside the AES-encrypted engine profile."
                    )
                    disclosureRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "No Recovery or Transfer",
                        detail: "The key stays on this device and requires its passcode. Removing the device passcode, replacing the device, or restoring a backup makes this protected profile permanently unrecoverable."
                    )
                    .foregroundStyle(.red)
                    Button(action: onConfirm) {
                        HStack {
                            if isWorking {
                                ProgressView()
                            }
                            Text(enabling ? "Authenticate and Protect" : "Authenticate and Remove Protection")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(enabling ? Color.accentColor : Color.red)
                    .controlSize(.large)
                    .disabled(isWorking)
                    Button("Cancel", action: onCancel)
                        .frame(maxWidth: .infinity)
                        .disabled(isWorking)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(28)
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func disclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                        HStack {
                            Text(service.name)
                            Spacer()
                            if environment.isServiceLocked(service.id) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(environment.isServiceLocked(service.id))
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
    @State private var savedCode: String
    @State private var isInSync: Bool
    @State private var isTemplateBacked: Bool
    @State private var showingDiscardConfirmation = false

    init(action: CustomAction, service: Service, environment: AppEnvironment) {
        self.action = action
        self.service = service
        let defaultScript = ActionScripts.defaultScript(for: service, action: action)
        let initial = environment.actionScript(for: service, action: action)
        _isTemplateBacked = State(initialValue: defaultScript != nil)
        _isInSync = State(initialValue: defaultScript != nil && service.templateActionScriptSync[action.id] == true)
        _code = State(initialValue: initial)
        _savedCode = State(initialValue: initial)
    }

    private var isDirty: Bool {
        !isInSync && code != savedCode
    }

    var body: some View {
        Form {
            if isTemplateBacked {
                Section {
                    LatestDefaultToggle(
                        isInSync: isInSync,
                        syncedDescription: "This action runs Quiper's bundled template script and updates automatically.",
                        customDescription: "This action uses a custom editable script.",
                        setInSync: toggleSync
                    )
                } header: {
                    Text("Source")
                }
            }
            Section {
                CodeEditorView(code: $code, language: .javaScript, isReadOnly: isInSync)
                    .frame(minHeight: 300)
            } header: {
                Text("Script")
            } footer: {
                Text(isInSync
                     ? "This action runs Quiper's bundled template script and updates automatically. Disable latest default to edit it."
                     : "JavaScript executed in \(service.name) when this action runs.")
            }
        }
        .navigationTitle("\(action.name.isEmpty ? "Action" : action.name) · \(service.name)")
        .navigationBarTitleDisplayMode(.inline)
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
                    environment.saveCustomActionScript(code, serviceID: service.id, actionID: action.id)
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .disabled(!isDirty)
            }
        }
        .background {
            NavigationPopGestureLock(isLocked: isDirty)
                .frame(width: 0, height: 0)
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
            Text("Your unsaved script changes will be lost.")
        }
    }

    private func toggleSync(_ newValue: Bool) {
        guard let defaultScript = ActionScripts.defaultScript(for: service, action: action) else { return }
        environment.setTemplateActionScriptSync(newValue, serviceID: service.id, actionID: action.id)
        isInSync = newValue
        code = defaultScript
        savedCode = defaultScript
    }
}

private struct NavigationPopGestureLock: UIViewControllerRepresentable {
    let isLocked: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let isLocked = isLocked
        DispatchQueue.main.async { [weak controller] in
            controller?.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isLocked
        }
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

struct RoutingRulesEditView: View {
    @Binding var service: Service
    @FocusState private var focusedRuleID: UUID?

    var body: some View {
        Form {
            Section {
                if service.routingRules.isEmpty {
                    Text("No routing rules defined. Links will open externally by default.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(service.routingRules.indices), id: \.self) { index in
                        RoutingRuleField(
                            rule: $service.routingRules[index],
                            ruleID: service.routingRules[index].id,
                            focusedRuleID: $focusedRuleID
                        )
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

struct CustomCSSEditView: View {
    @Binding var service: Service
    @State private var code: String
    @State private var isInSync: Bool
    @State private var isTemplateBacked: Bool

    init(service: Binding<Service>) {
        _service = service
        let defaultCSS = ActionScripts.defaultCustomCSS(for: service.wrappedValue)
        _isTemplateBacked = State(initialValue: defaultCSS != nil)
        _isInSync = State(initialValue: defaultCSS != nil && service.wrappedValue.templateCustomCSSSync)
        _code = State(initialValue: ActionScripts.resolvedCustomCSS(for: service.wrappedValue))
    }

    var body: some View {
        Form {
            if isTemplateBacked {
                Section {
                    LatestDefaultToggle(
                        isInSync: isInSync,
                        syncedDescription: "This stylesheet follows Quiper's bundled engine template and updates automatically.",
                        customDescription: "This engine uses a custom editable stylesheet.",
                        setInSync: toggleSync
                    )
                } header: {
                    Text("Source")
                } footer: {
                    Text("Use Latest Default keeps this engine's stylesheet in sync with Quiper's bundled template. Disable it to edit a custom stylesheet.")
                }
            }
            Section {
                CodeEditorView(code: $code, language: .css, isReadOnly: isInSync)
                    .frame(minHeight: 300)
            } header: {
                Text("Custom CSS")
            } footer: {
                Text(isInSync
                     ? "This engine follows Quiper's bundled stylesheet and cannot be edited."
                     : "Custom CSS injected into this engine's pages to adjust colors, fonts, or hide unwanted UI.")
            }
        }
        .navigationTitle("Custom CSS")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: code) { _, newValue in
            guard !isInSync else { return }
            service.customCSS = newValue
            service.templateCustomCSSSync = false
        }
    }

    private func toggleSync(_ newValue: Bool) {
        guard let defaultCSS = ActionScripts.defaultCustomCSS(for: service) else { return }
        isInSync = newValue
        service.templateCustomCSSSync = newValue
        if newValue {
            service.customCSS = nil
        } else {
            service.customCSS = defaultCSS
        }
        code = defaultCSS
    }
}
