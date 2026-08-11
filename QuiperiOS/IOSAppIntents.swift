import AppIntents
import Foundation

@MainActor
final class IOSAppIntentDependency {
    private let environment: AppEnvironment

    nonisolated init(environment: AppEnvironment) {
        self.environment = environment
    }

    func engines(ids: Set<String>? = nil) -> [EngineEntity] {
        environment.services.compactMap { engine in
            guard ids == nil || ids?.contains(engine.id.uuidString) == true else { return nil }
            return EngineEntity(id: engine.id.uuidString, name: engine.name)
        }
    }

    func actions(ids: Set<String>? = nil) -> [ActionEntity] {
        environment.customActions.compactMap { action in
            guard ids == nil || ids?.contains(action.id.uuidString) == true else { return nil }
            return ActionEntity(id: action.id.uuidString, name: action.name)
        }
    }

    func execute(_ command: IOSAppCommand) async throws -> IOSCommandOutcome {
        try await environment.commandExecutor.execute(command)
    }
}

struct EngineEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Quiper Engine")
    static let defaultQuery = EngineEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "globe"))
    }
}

struct EngineEntityQuery: EntityStringQuery {
    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(dependency: IOSAppIntentDependency) {
        _dependency = AppDependency()
        self.dependency = dependency
    }

    func entities(for identifiers: [EngineEntity.ID]) async throws -> [EngineEntity] {
        await dependency.engines(ids: Set(identifiers))
    }

    func suggestedEntities() async throws -> [EngineEntity] {
        await dependency.engines()
    }

    func entities(matching string: String) async throws -> [EngineEntity] {
        let engines = await dependency.engines()
        guard !string.isEmpty else { return engines }
        return engines.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

struct ActionEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Quiper Action")
    static let defaultQuery = ActionEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "bolt.fill"))
    }
}

struct ActionEntityQuery: EntityStringQuery {
    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(dependency: IOSAppIntentDependency) {
        _dependency = AppDependency()
        self.dependency = dependency
    }

    func entities(for identifiers: [ActionEntity.ID]) async throws -> [ActionEntity] {
        await dependency.actions(ids: Set(identifiers))
    }

    func suggestedEntities() async throws -> [ActionEntity] {
        await dependency.actions()
    }

    func entities(matching string: String) async throws -> [ActionEntity] {
        let actions = await dependency.actions()
        guard !string.isEmpty else { return actions }
        return actions.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

struct OpenEngineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Engine"
    static let description = IntentDescription("Open a configured Quiper engine.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Engine")
    var engine: EngineEntity

    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(engine: EngineEntity, dependency: IOSAppIntentDependency) {
        self.engine = engine
        _dependency = AppDependency()
        self.dependency = dependency
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$engine)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let engineID = UUID(uuidString: engine.id) else { throw IOSCommandError.engineNotFound }
        let outcome = try await dependency.execute(.openEngine(engineID))
        return .result(dialog: "\(outcome.message)")
    }
}

struct OpenNewQuiperSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open New Quiper Session"
    static let description = IntentDescription("Open the lowest available session slot.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Engine")
    var engine: EngineEntity?

    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(engine: EngineEntity?, dependency: IOSAppIntentDependency) {
        self.engine = engine
        _dependency = AppDependency()
        self.dependency = dependency
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open a new session in \(\.$engine)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engineID = try engine.map { entity in
            guard let id = UUID(uuidString: entity.id) else { throw IOSCommandError.engineNotFound }
            return id
        }
        let outcome = try await dependency.execute(.openNewSession(engineID: engineID))
        return .result(dialog: "\(outcome.message)")
    }
}

struct RunQuiperActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Action"
    static let description = IntentDescription("Run a configured action in Quiper.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Action")
    var action: ActionEntity

    @Parameter(title: "Engine")
    var engine: EngineEntity?

    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(
        action: ActionEntity,
        engine: EngineEntity?,
        dependency: IOSAppIntentDependency
    ) {
        self.action = action
        self.engine = engine
        _dependency = AppDependency()
        self.dependency = dependency
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) in \(\.$engine)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let actionID = UUID(uuidString: action.id) else { throw IOSCommandError.actionNotFound }
        let engineID = try engine.map { entity in
            guard let id = UUID(uuidString: entity.id) else { throw IOSCommandError.engineNotFound }
            return id
        }
        let outcome = try await dependency.execute(
            .runAction(actionID: actionID, engineID: engineID)
        )
        return .result(dialog: "\(outcome.message)")
    }
}

enum LockEngineScope: String, AppEnum {
    case current
    case selected
    case allProtected

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lock Scope")
    static let caseDisplayRepresentations: [LockEngineScope: DisplayRepresentation] = [
        .current: "Current Engine",
        .selected: "Selected Engine",
        .allProtected: "All Protected Engines"
    ]
}

struct LockEngineIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Engine"
    static let description = IntentDescription("Lock one engine or every protected engine.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Scope", default: .current)
    var scope: LockEngineScope

    @Parameter(title: "Engine")
    var engine: EngineEntity?

    @AppDependency private var dependency: IOSAppIntentDependency

    init() { }

    init(
        scope: LockEngineScope,
        engine: EngineEntity?,
        dependency: IOSAppIntentDependency
    ) {
        self.scope = scope
        self.engine = engine
        _dependency = AppDependency()
        self.dependency = dependency
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\.$scope) {
            Case(.selected) {
                Summary("Lock \(\.$engine)")
            }
            DefaultCase {
                Summary("Lock \(\.$scope)")
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: IOSLockTarget
        switch scope {
        case .current:
            target = .current
        case .selected:
            let selectedEngine = if let engine {
                engine
            } else {
                try await $engine.requestValue("Which engine do you want to lock?")
            }
            guard let engineID = UUID(uuidString: selectedEngine.id) else {
                throw IOSCommandError.engineNotFound
            }
            target = .engine(engineID)
        case .allProtected:
            target = .allProtected
        }
        let outcome = try await dependency.execute(.lock(target))
        return .result(dialog: "\(outcome.message)")
    }
}

struct QuiperAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEngineIntent(),
            phrases: [
                "Open \(\.$engine) in \(.applicationName)",
                "Switch to \(\.$engine) in \(.applicationName)"
            ],
            shortTitle: "Open Engine",
            systemImageName: "globe"
        )
        AppShortcut(
            intent: OpenNewQuiperSessionIntent(),
            phrases: [
                "Open a new session in \(.applicationName)",
                "New \(.applicationName) session",
                "Open a new session in \(\.$engine) with \(.applicationName)"
            ],
            shortTitle: "New Session",
            systemImageName: "plus.square.on.square"
        )
        AppShortcut(
            intent: RunQuiperActionIntent(),
            phrases: [
                "Run \(\.$action) in \(.applicationName)",
                "Use \(\.$action) in \(.applicationName)"
            ],
            shortTitle: "Run Action",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: LockEngineIntent(),
            phrases: [
                "Lock \(.applicationName)",
                "Protect \(.applicationName)"
            ],
            shortTitle: "Lock Engine",
            systemImageName: "lock.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
