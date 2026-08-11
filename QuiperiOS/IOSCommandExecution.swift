import Foundation
import Observation
import WebKit

enum IOSReloadKind: Hashable, Sendable {
    case normal
    case force
    case fromOrigin
}

enum IOSFindCommand: Hashable, Sendable {
    case show
    case next
    case previous
}

enum IOSZoomCommand: Hashable, Sendable {
    case inStep
    case outStep
    case reset
}

enum IOSLockTarget: Hashable, Sendable {
    case current
    case engine(UUID)
    case allProtected
}

enum IOSScenePresentationCommand: Hashable, Sendable {
    case showSettings
    case showHistory
    case showFind
}

enum IOSAppCommand: Hashable, Sendable {
    case openEngine(UUID)
    case openNewSession(engineID: UUID?)
    case runAction(actionID: UUID, engineID: UUID?)
    case lock(IOSLockTarget)
    case nextSession
    case previousSession
    case selectSession(Int)
    case nextEngine
    case previousEngine
    case selectEngine(Int)
    case closeSession
    case closeSessionAt(serviceID: UUID, index: Int)
    case reload(IOSReloadKind)
    case find(IOSFindCommand)
    case showHistory
    case showSettings
    case zoom(IOSZoomCommand)
    case cycleMRU(reverse: Bool)
}

struct IOSCommandOutcome: Equatable, Sendable {
    let message: String
}

enum IOSCommandError: LocalizedError, Equatable, Sendable {
    case appNotReady
    case noEngines
    case engineNotFound
    case noActiveSession
    case allSessionSlotsOccupied
    case actionNotFound
    case actionFailed(String)
    case authenticationFailed(String)
    case engineLockFailed(String)
    case engineIsNotProtected
    case noUnlockedProtectedEngines
    case presentationUnavailable

    var errorDescription: String? {
        switch self {
        case .appNotReady:
            return "Quiper is not ready yet."
        case .noEngines:
            return "Quiper has no configured engines."
        case .engineNotFound:
            return "The selected engine is no longer available."
        case .noActiveSession:
            return "Open a session before running this command."
        case .allSessionSlotsOccupied:
            return "All ten session slots are already occupied."
        case .actionNotFound:
            return "The selected action is no longer available."
        case .actionFailed(let message):
            return message
        case .authenticationFailed(let message):
            return message
        case .engineLockFailed(let message):
            return message
        case .engineIsNotProtected:
            return "The selected engine is not protected."
        case .noUnlockedProtectedEngines:
            return "There are no unlocked protected engines."
        case .presentationUnavailable:
            return "This command requires an active Quiper window."
        }
    }
}

@MainActor
@Observable
final class IOSSceneCommandContext {
    var errorMessage: String?
    var isRecordingShortcut = false

    @ObservationIgnored
    var presentationHandler: ((IOSScenePresentationCommand) -> Void)?

    func present(_ command: IOSScenePresentationCommand) throws {
        guard let presentationHandler else {
            throw IOSCommandError.presentationUnavailable
        }
        presentationHandler(command)
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

@MainActor
final class IOSCommandExecutor {
    private unowned let environment: AppEnvironment
    private let actionReadinessTimeout: Duration
    private var isExecuting = false
    private var executionWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var executionWaiterOrder: [UUID] = []

    init(environment: AppEnvironment, actionReadinessTimeout: Duration = .seconds(15)) {
        self.environment = environment
        self.actionReadinessTimeout = actionReadinessTimeout
    }

    func execute(
        _ command: IOSAppCommand,
        sceneContext: IOSSceneCommandContext? = nil
    ) async throws -> IOSCommandOutcome {
        try await acquireExecutionTurn()
        defer { releaseExecutionTurn() }
        try Task.checkCancellation()
        guard environment.startupState == .ready else {
            throw IOSCommandError.appNotReady
        }
        return try await perform(command, sceneContext: sceneContext)
    }

    private func perform(
        _ command: IOSAppCommand,
        sceneContext: IOSSceneCommandContext?
    ) async throws -> IOSCommandOutcome {
        switch command {
        case .openEngine(let engineID):
            let engine = try await activateEngine(engineID)
            return IOSCommandOutcome(message: "Opened \(engine.name).")

        case .openNewSession(let engineID):
            let resolvedID = try resolveEngineID(engineID)
            let engine = try await activateEngine(
                resolvedID,
                createSessionIfNeeded: false
            )
            let occupied = Set(
                environment.persistedTabState.openTabs[resolvedID]?.keys.map { $0 } ?? []
            )
            guard let slot = SessionSlots.range.first(where: { !occupied.contains($0) }) else {
                throw IOSCommandError.allSessionSlotsOccupied
            }
            environment.setActiveSession(for: resolvedID, index: slot)
            _ = environment.activeWebSession()
            return IOSCommandOutcome(
                message: "Opened session \(SessionSlots.label(for: slot)) in \(engine.name)."
            )

        case .runAction(let actionID, let engineID):
            guard let action = environment.customActions.first(where: { $0.id == actionID }) else {
                throw IOSCommandError.actionNotFound
            }
            let resolvedID = try resolveEngineID(engineID)
            let engine = try await activateEngine(resolvedID)
            if environment.hasNoSessions(for: resolvedID) {
                guard environment.autoCreateSessionOnEmptyEngineActivation else {
                    throw IOSCommandError.noActiveSession
                }
                environment.ensureSessions(for: resolvedID)
                environment.setActiveSession(for: resolvedID, index: 0)
            }
            guard let session = environment.activeWebSession() else {
                throw IOSCommandError.noActiveSession
            }
            session.loadIfNeeded()
            do {
                try await session.waitUntilNavigationReady(timeout: actionReadinessTimeout)
                try await run(action: action, in: engine, session: session)
            } catch let error as IOSCommandError {
                throw error
            } catch {
                throw IOSCommandError.actionFailed(error.localizedDescription)
            }
            return IOSCommandOutcome(message: "Ran \(action.name) in \(engine.name).")

        case .lock(let target):
            return try lock(target)

        case .nextSession:
            try await stepSession(by: 1)
            return IOSCommandOutcome(message: "Opened the next session.")
        case .previousSession:
            try await stepSession(by: -1)
            return IOSCommandOutcome(message: "Opened the previous session.")
        case .selectSession(let index):
            guard SessionSlots.range.contains(index), let serviceID = environment.activeService?.id else {
                throw IOSCommandError.noActiveSession
            }
            _ = try await activateEngine(serviceID, createSessionIfNeeded: false)
            environment.setActiveSession(for: serviceID, index: index)
            return IOSCommandOutcome(message: "Opened session \(SessionSlots.label(for: index)).")

        case .nextEngine:
            try await stepEngine(by: 1)
            return IOSCommandOutcome(message: "Opened the next engine.")
        case .previousEngine:
            try await stepEngine(by: -1)
            return IOSCommandOutcome(message: "Opened the previous engine.")
        case .selectEngine(let index):
            guard environment.services.indices.contains(index) else {
                throw IOSCommandError.engineNotFound
            }
            let engine = try await activateEngine(environment.services[index].id)
            return IOSCommandOutcome(message: "Opened \(engine.name).")

        case .closeSession:
            guard let serviceID = environment.activeService?.id else {
                throw IOSCommandError.noActiveSession
            }
            return try await closeSession(
                serviceID: serviceID,
                index: environment.activeSessionIndex(for: serviceID)
            )

        case .closeSessionAt(let serviceID, let index):
            return try await closeSession(serviceID: serviceID, index: index)

        case .reload(let kind):
            try await unlockActiveEngineIfNeeded()
            try reload(kind)
            return IOSCommandOutcome(message: "Reloaded the active session.")

        case .find(let command):
            try await unlockActiveEngineIfNeeded()
            try find(command, sceneContext: sceneContext)
            return IOSCommandOutcome(message: "Updated find in page.")

        case .showHistory:
            guard let sceneContext else { throw IOSCommandError.presentationUnavailable }
            try sceneContext.present(.showHistory)
            return IOSCommandOutcome(message: "Opened prompt history.")

        case .showSettings:
            guard let sceneContext else { throw IOSCommandError.presentationUnavailable }
            try sceneContext.present(.showSettings)
            return IOSCommandOutcome(message: "Opened Settings.")

        case .zoom(let command):
            try await unlockActiveEngineIfNeeded()
            try zoom(command)
            return IOSCommandOutcome(message: "Updated page zoom.")

        case .cycleMRU(let reverse):
            try await cycleMRU(reverse: reverse)
            return IOSCommandOutcome(message: "Switched recent session.")
        }
    }

    private func activateEngine(
        _ engineID: UUID,
        createSessionIfNeeded: Bool = true
    ) async throws -> Service {
        guard environment.services.contains(where: { $0.id == engineID }) else {
            throw IOSCommandError.engineNotFound
        }
        environment.setActiveService(
            engineID,
            createSessionIfNeeded: createSessionIfNeeded
        )
        if environment.isServiceLocked(engineID) {
            let unlocked = await environment.unlockService(
                engineID,
                createSessionIfNeeded: createSessionIfNeeded
            )
            guard unlocked, !environment.isServiceLocked(engineID) else {
                throw IOSCommandError.authenticationFailed(
                    environment.securityError(for: engineID) ?? "The engine could not be unlocked."
                )
            }
        }
        environment.setActiveService(
            engineID,
            createSessionIfNeeded: createSessionIfNeeded
        )
        guard let engine = environment.services.first(where: { $0.id == engineID }) else {
            throw IOSCommandError.engineNotFound
        }
        return engine
    }

    private func resolveEngineID(_ requestedID: UUID?) throws -> UUID {
        if let requestedID {
            guard environment.services.contains(where: { $0.id == requestedID }) else {
                throw IOSCommandError.engineNotFound
            }
            return requestedID
        }
        guard let engineID = environment.activeService?.id ?? environment.services.first?.id else {
            throw IOSCommandError.noEngines
        }
        return engineID
    }

    private func unlockActiveEngineIfNeeded() async throws {
        guard let engineID = environment.activeService?.id else {
            throw IOSCommandError.noEngines
        }
        _ = try await activateEngine(engineID, createSessionIfNeeded: false)
    }

    private func lock(_ target: IOSLockTarget) throws -> IOSCommandOutcome {
        switch target {
        case .allProtected:
            let unlocked = environment.services.filter {
                $0.isEncrypted && !environment.isServiceLocked($0.id)
            }
            guard !unlocked.isEmpty else {
                throw IOSCommandError.noUnlockedProtectedEngines
            }
            var failedNames: [String] = []
            for engine in unlocked {
                environment.lockService(engine.id)
                if !environment.isServiceLocked(engine.id) {
                    failedNames.append(engine.name)
                }
            }
            if !failedNames.isEmpty {
                throw IOSCommandError.engineLockFailed(
                    "Quiper could not lock \(failedNames.joined(separator: ", "))."
                )
            }
            return IOSCommandOutcome(message: "Locked all protected engines.")

        case .current:
            guard let engineID = environment.activeService?.id else {
                throw IOSCommandError.engineNotFound
            }
            return try lock(.engine(engineID))

        case .engine(let engineID):
            guard let engine = environment.services.first(where: { $0.id == engineID }) else {
                throw IOSCommandError.engineNotFound
            }
            guard engine.isEncrypted else {
                throw IOSCommandError.engineIsNotProtected
            }
            if !environment.isServiceLocked(engineID) {
                environment.lockService(engineID)
            }
            guard environment.isServiceLocked(engineID) else {
                throw IOSCommandError.engineLockFailed(
                    environment.securityError(for: engineID) ?? "Quiper could not lock \(engine.name)."
                )
            }
            return IOSCommandOutcome(message: "Locked \(engine.name).")
        }
    }

    private func stepSession(by delta: Int) async throws {
        guard let serviceID = environment.activeService?.id else {
            throw IOSCommandError.noActiveSession
        }
        _ = try await activateEngine(serviceID, createSessionIfNeeded: false)
        let current = environment.activeSessionIndex(for: serviceID)
        let next = (current + delta + SessionSlots.count) % SessionSlots.count
        environment.setActiveSession(for: serviceID, index: next)
    }

    private func closeSession(serviceID: UUID, index: Int) async throws -> IOSCommandOutcome {
        guard SessionSlots.range.contains(index) else {
            throw IOSCommandError.noActiveSession
        }
        _ = try await activateEngine(serviceID, createSessionIfNeeded: false)
        guard environment.isSessionLoaded(for: serviceID, slot: index) else {
            throw IOSCommandError.noActiveSession
        }
        environment.closeSession(for: serviceID, at: index)
        return IOSCommandOutcome(message: "Closed session \(SessionSlots.label(for: index)).")
    }

    private func stepEngine(by delta: Int) async throws {
        guard !environment.services.isEmpty else { throw IOSCommandError.noEngines }
        let currentID = environment.activeService?.id
        let current = environment.services.firstIndex(where: { $0.id == currentID }) ?? 0
        let next = (current + delta + environment.services.count) % environment.services.count
        _ = try await activateEngine(environment.services[next].id)
    }

    private func reload(_ kind: IOSReloadKind) throws {
        switch kind {
        case .normal:
            guard let session = environment.activeWebSession() else {
                throw IOSCommandError.noActiveSession
            }
            session.reload()
        case .force:
            guard let serviceID = environment.activeService?.id,
                  environment.isSessionLoaded(
                      for: serviceID,
                      slot: environment.activeSessionIndex(for: serviceID)
                  ) else {
                throw IOSCommandError.noActiveSession
            }
            guard environment.recreateActiveWebSession() != nil else {
                throw IOSCommandError.noActiveSession
            }
        case .fromOrigin:
            guard let session = environment.activeWebSession() else {
                throw IOSCommandError.noActiveSession
            }
            _ = session.webView.reloadFromOrigin()
        }
    }

    private func find(
        _ command: IOSFindCommand,
        sceneContext: IOSSceneCommandContext?
    ) throws {
        switch command {
        case .show:
            guard let sceneContext else { throw IOSCommandError.presentationUnavailable }
            guard environment.activeWebSession() != nil else {
                throw IOSCommandError.noActiveSession
            }
            try sceneContext.present(.showFind)
        case .next:
            guard let session = environment.activeWebSession() else {
                throw IOSCommandError.noActiveSession
            }
            session.stepFind(forward: true)
        case .previous:
            guard let session = environment.activeWebSession() else {
                throw IOSCommandError.noActiveSession
            }
            session.stepFind(forward: false)
        }
    }

    private func zoom(_ command: IOSZoomCommand) throws {
        guard let session = environment.activeWebSession() else {
            throw IOSCommandError.noActiveSession
        }
        switch command {
        case .inStep:
            session.webView.pageZoom = min(Zoom.max, session.webView.pageZoom + Zoom.step)
        case .outStep:
            session.webView.pageZoom = max(Zoom.min, session.webView.pageZoom - Zoom.step)
        case .reset:
            session.webView.pageZoom = Zoom.default
        }
    }

    private func cycleMRU(reverse: Bool) async throws {
        let items = environment.navigationRingItems()
        guard items.count > 1 else { throw IOSCommandError.noActiveSession }
        let target = reverse ? items[items.count - 1] : items[1]
        _ = try await activateEngine(target.serviceID, createSessionIfNeeded: false)
        environment.setActiveSession(for: target.serviceID, index: target.sessionIndex)
    }

    private func run(
        action: CustomAction,
        in engine: Service,
        session: WebViewSession
    ) async throws {
        let storedScript = environment.actionScript(for: engine, action: action)
        let rawScript = storedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = rawScript.isEmpty
            ? WebScripts.makeActionFallbackScript(actionName: action.name, serviceName: engine.name)
            : rawScript
        let wrappedScript = WebScripts.makeActionRunnerScript(script: script)

        let value: Any? = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Any?, Error>) in
            session.webView.callAsyncJavaScript(wrappedScript, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        if let dictionary = value as? [String: Any],
           let message = dictionary["quiperError"] as? String {
            throw IOSCommandError.actionFailed(message)
        }
    }

    private func acquireExecutionTurn() async throws {
        try Task.checkCancellation()
        if !isExecuting {
            isExecuting = true
            if Task.isCancelled {
                isExecuting = false
                throw CancellationError()
            }
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    executionWaiters[waiterID] = continuation
                    executionWaiterOrder.append(waiterID)
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelExecutionWaiter(waiterID)
            }
        })

        if Task.isCancelled {
            releaseExecutionTurn()
            throw CancellationError()
        }
    }

    private func releaseExecutionTurn() {
        while !executionWaiterOrder.isEmpty {
            let waiterID = executionWaiterOrder.removeFirst()
            guard let waiter = executionWaiters.removeValue(forKey: waiterID) else { continue }
            waiter.resume()
            return
        }
        isExecuting = false
    }

    private func cancelExecutionWaiter(_ waiterID: UUID) {
        executionWaiterOrder.removeAll { $0 == waiterID }
        executionWaiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
    }
}
