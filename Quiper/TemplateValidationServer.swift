import AppKit
import Foundation
@preconcurrency import Network
import WebKit

#if DEBUG
@MainActor
final class TemplateValidationServer {
    nonisolated static let launchFlag = Constants.LaunchMode.templateValidationServerFlag

    nonisolated private static let validationBundleID = "app.sassanh.quiper.QuiperDev"
    nonisolated private static let portFilename = "quiper-template-validation-port.json"

    private weak var windowController: MainWindowController?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.sassanh.quiper.template-validation")

    init(windowController: MainWindowController) {
        self.windowController = windowController
    }

    nonisolated static func shouldStart(
        bundleIdentifier: String = Constants.BUNDLE_ID,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        canStart(bundleIdentifier: bundleIdentifier, arguments: arguments)
    }

    nonisolated static func canStart(bundleIdentifier: String, arguments: [String]) -> Bool {
        bundleIdentifier == validationBundleID && arguments.contains(launchFlag)
    }

    static var portFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(portFilename)
    }

    func start() throws {
        guard Self.shouldStart() else {
            throw TemplateValidationError.notAllowed
        }
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            DispatchQueue.main.async {
                guard let self, let port = listener.port?.rawValue else { return }
                self.writePortFile(port: port)
                NSLog("[Quiper] Template validation server listening on 127.0.0.1:%d", port)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            DispatchQueue.main.async {
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(at: Self.portFileURL)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(from: connection, buffer: Data())
    }

    nonisolated private func readRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let error {
                Self.sendJSON(["ok": false, "error": error.localizedDescription], status: 400, on: connection)
                return
            }

            if let request = HTTPRequest(data: nextBuffer) {
                DispatchQueue.main.async {
                    self?.handle(request, on: connection)
                }
                return
            }

            if isComplete {
                Self.sendJSON(["ok": false, "error": "incomplete request"], status: 400, on: connection)
                return
            }

            self?.readRequest(from: connection, buffer: nextBuffer)
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard Self.shouldStart() else {
            Self.sendJSON(["ok": false, "error": "template validation server is disabled"], status: 403, on: connection)
            return
        }

        Task { @MainActor in
            do {
                let payload = try await route(request)
                Self.sendJSON(["ok": true, "result": payload], status: 200, on: connection)
            } catch let error as TemplateValidationError {
                Self.sendJSON(["ok": false, "error": error.message], status: error.statusCode, on: connection)
            } catch {
                Self.sendJSON(["ok": false, "error": error.localizedDescription], status: 500, on: connection)
            }
        }
    }

    private func route(_ request: HTTPRequest) async throws -> JSONDictionary {
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return statusPayload()
        case ("POST", "/engine/select"):
            return try selectEngine(request.bodyDictionary)
        case ("POST", "/session/start-current"):
            return try startCurrentSession(request.bodyDictionary)
        case ("POST", "/viewport"):
            return try setViewport(request.bodyDictionary)
        case ("POST", "/dom/query"):
            return try await runDOMQuery(request.bodyDictionary)
        case ("POST", "/action/run"):
            return try await runAction(request.bodyDictionary)
        case ("POST", "/templates/apply-defaults"):
            return try applyDefaultTemplates(request.bodyDictionary)
        default:
            throw TemplateValidationError.notFound("Unknown endpoint \(request.method) \(request.path)")
        }
    }

    private func statusPayload() -> JSONDictionary {
        guard let controller = windowController else {
            return ["ready": false]
        }

        let service = controller.currentService()
        let webView = controller.currentWebView()
        let frame = controller.window?.frame ?? .zero
        let dataStore = webView?.configuration.websiteDataStore

        return [
            "ready": true,
            "bundleIdentifier": Constants.BUNDLE_ID,
            "isDev": Constants.IS_DEV,
            "isRunningTests": NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil,
            "currentService": jsonOrNull(service?.name),
            "currentServiceURL": jsonOrNull(service?.url),
            "currentServiceID": jsonOrNull(service?.id.uuidString),
            "currentServiceEncrypted": service?.isEncrypted ?? false,
            "currentServiceIndex": jsonOrNull(service.flatMap { activeIndex(for: $0, in: controller) }),
            "currentSessionIndex": jsonOrNull(service.map { controller.activeIndicesByURL[$0.url] ?? 0 }),
            "pageURL": jsonOrNull(webView?.url?.absoluteString),
            "pageTitle": jsonOrNull(webView?.title),
            "isLoading": webView?.isLoading ?? false,
            "websiteDataStorePersistent": dataStore?.isPersistent ?? false,
            "window": [
                "width": Int(frame.width),
                "height": Int(frame.height),
                "visible": controller.window?.isVisible ?? false
            ]
        ]
    }

    private func selectEngine(_ body: JSONDictionary) throws -> JSONDictionary {
        guard let controller = windowController else {
            throw TemplateValidationError.unavailable("Window controller is unavailable")
        }

        let index: Int?
        if let name = body["name"] as? String {
            index = controller.services.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } else if let url = body["url"] as? String {
            index = controller.services.firstIndex { $0.url == url }
        } else {
            throw TemplateValidationError.badRequest("Expected name or url")
        }

        guard let index else {
            throw TemplateValidationError.notFound("Engine not found")
        }

        controller.show()
        controller.selectService(at: index, focusWebView: false)
        return statusPayload()
    }

    private func startCurrentSession(_ body: JSONDictionary) throws -> JSONDictionary {
        guard let controller = windowController, let service = controller.currentService() else {
            throw TemplateValidationError.unavailable("No active engine")
        }

        let sessionIndex = controller.activeIndicesByURL[service.url] ?? 0
        let webView = controller.getOrCreateWebview(for: service, sessionIndex: sessionIndex)
        if (body["reload"] as? Bool) == true, let url = URL(string: service.url) {
            webView.load(URLRequest(url: url))
        }
        controller.switchSession(to: sessionIndex, forceCreate: true)
        return statusPayload()
    }

    private func setViewport(_ body: JSONDictionary) throws -> JSONDictionary {
        guard let window = windowController?.window else {
            throw TemplateValidationError.unavailable("Window is unavailable")
        }

        let sizeName = (body["size"] as? String) ?? "large"
        let size: NSSize
        switch sizeName {
        case "small":
            size = NSSize(width: 390, height: 720)
        case "medium":
            size = NSSize(width: 760, height: 720)
        case "large":
            size = NSSize(width: 1180, height: 820)
        default:
            throw TemplateValidationError.badRequest("Unsupported viewport size \(sizeName)")
        }

        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true, animate: false)
        return statusPayload()
    }

    private func runDOMQuery(_ body: JSONDictionary) async throws -> JSONDictionary {
        guard let webView = windowController?.currentWebView() else {
            throw TemplateValidationError.unavailable("No active web view")
        }

        let probe = (body["probe"] as? String) ?? "pageFacts"
        let argument = body["argument"] as? String
        let script: String

        switch probe {
        case "pageFacts":
            script = Self.pageFactsScript
        case "focusSelector":
            guard let selector = argument, !selector.isEmpty else {
                throw TemplateValidationError.badRequest("focusSelector probe requires argument")
            }
            script = Self.focusSelectorScript(selector: selector, shouldFocus: (body["focus"] as? Bool) ?? false)
        case "buttons":
            script = Self.buttonsScript(limit: (body["limit"] as? Int) ?? 80)
        case "geminiState":
            script = Self.geminiStateScript
        default:
            throw TemplateValidationError.badRequest("Unsupported DOM probe \(probe)")
        }

        return try await evaluateDictionary(script, in: webView)
    }

    private func runAction(_ body: JSONDictionary) async throws -> JSONDictionary {
        guard let controller = windowController,
              let service = controller.currentService(),
              let webView = controller.currentWebView() else {
            throw TemplateValidationError.unavailable("No active engine")
        }

        let actionName = body["action"] as? String
        let action = actionName.flatMap { name in
            Settings.shared.customActions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let action else {
            throw TemplateValidationError.notFound("Action not found")
        }

        let storedScript = (body["script"] as? String) ?? ActionScriptStorage.loadScript(
            serviceID: service.id,
            actionID: action.id,
            fallback: service.actionScripts[action.id] ?? ""
        )
        let rawScript = storedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawScript.isEmpty else {
            throw TemplateValidationError.notFound("Action \(action.name) is not implemented for \(service.name)")
        }

        let wrappedScript = """
        try {
          const wrapper = async () => {
            \(rawScript)
          };
          await wrapper();
          return { actionStatus: "ok" };
        } catch (err) {
          return { quiperError: (err && err.message) ? err.message : String(err) };
        }
        """

        let result = try await evaluateDictionary(wrappedScript, in: webView)
        if let message = result["quiperError"] as? String {
            throw TemplateValidationError.scriptFailure(message)
        }
        return [
            "action": action.name,
            "service": service.name,
            "scriptResult": result,
            "page": try await evaluateDictionary(Self.pageFactsScript, in: webView)
        ]
    }

    private func applyDefaultTemplates(_ body: JSONDictionary) throws -> JSONDictionary {
        guard let controller = windowController else {
            throw TemplateValidationError.unavailable("No active engine")
        }

        let settings = Settings.shared
        let requestedServiceName = (body["service"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceIndex: Int?
        if let requestedServiceName, !requestedServiceName.isEmpty {
            serviceIndex = settings.services.firstIndex {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(requestedServiceName) == .orderedSame
            }
        } else if let current = controller.currentService() {
            serviceIndex = settings.services.firstIndex { $0.id == current.id }
        } else {
            serviceIndex = nil
        }

        guard let serviceIndex else {
            throw TemplateValidationError.notFound("Service not found")
        }

        let service = settings.services[serviceIndex]
        guard let template = settings.defaultServiceTemplates.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(service.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }) else {
            throw TemplateValidationError.notFound("Default template not found for \(service.name)")
        }

        let requestedActionNames = Set((body["actions"] as? [String] ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })

        var applied: [String] = []
        for action in settings.customActions {
            let normalizedActionName = action.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard requestedActionNames.isEmpty || requestedActionNames.contains(normalizedActionName),
                  let defaultID = settings.defaultActionID(matching: action.name),
                  let defaultScript = template.actionScripts[defaultID]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !defaultScript.isEmpty else { continue }

            settings.services[serviceIndex].templateActionScriptSync[action.id] = true
            settings.services[serviceIndex].actionScripts.removeValue(forKey: action.id)
            ActionScriptStorage.deleteScript(serviceID: service.id, actionID: action.id)
            applied.append(action.name)
        }

        settings.saveSettings()
        return [
            "service": settings.services[serviceIndex].name,
            "appliedActions": applied,
            "appliedCount": applied.count
        ]
    }

    private func evaluateDictionary(_ script: String, in webView: WKWebView) async throws -> JSONDictionary {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let dictionary = value as? JSONDictionary {
                        continuation.resume(returning: dictionary)
                    } else {
                        continuation.resume(returning: ["value": value as Any])
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func sendJSON(_ object: JSONDictionary, status: Int, on connection: NWConnection) {
        let normalized = normalizeForJSON(object)
        let body = (try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let reason = HTTPStatus.reason(for: status)
        var response = Data()
        response.append("HTTP/1.1 \(status) \(reason)\r\n")
        response.append("Content-Type: application/json; charset=utf-8\r\n")
        response.append("Content-Length: \(body.count)\r\n")
        response.append("Connection: close\r\n")
        response.append("\r\n")
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func writePortFile(port: UInt16) {
        let payload: JSONDictionary = [
            "host": "127.0.0.1",
            "port": Int(port),
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundleIdentifier": Constants.BUNDLE_ID
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: Self.portFileURL, options: [.atomic])
    }

    private func jsonOrNull<T>(_ value: T?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }

    private func activeIndex(for service: Service, in controller: MainWindowController) -> Int? {
        controller.services.firstIndex { $0.id == service.id }
    }

    nonisolated private static func normalizeForJSON(_ value: Any) -> Any {
        switch value {
        case Optional<Any>.none:
            return NSNull()
        case let dictionary as [String: Any]:
            return dictionary.mapValues { normalizeForJSON($0) }
        case let array as [Any]:
            return array.map { normalizeForJSON($0) }
        case let value as String:
            return value
        case let value as NSNumber:
            return value
        case let value as Bool:
            return value
        case is NSNull:
            return NSNull()
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let value as CGFloat:
            return Double(value)
        case let value as URL:
            return value.absoluteString
        default:
            return String(describing: value)
        }
    }
}

private typealias JSONDictionary = [String: Any]

private enum TemplateValidationError: Error {
    case notAllowed
    case badRequest(String)
    case notFound(String)
    case unavailable(String)
    case scriptFailure(String)

    var statusCode: Int {
        switch self {
        case .notAllowed:
            return 403
        case .badRequest:
            return 400
        case .notFound:
            return 404
        case .unavailable:
            return 409
        case .scriptFailure:
            return 422
        }
    }

    var message: String {
        switch self {
        case .notAllowed:
            return "Template validation server is only available in QuiperDev with --template-validation-server"
        case .badRequest(let message), .notFound(let message), .unavailable(let message), .scriptFailure(let message):
            return message
        }
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let bodyDictionary: JSONDictionary

    init?(data: Data) {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        var contentLength = 0
        for line in headerLines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }

        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let bodyData = data[bodyStart..<(bodyStart + contentLength)]

        self.method = requestParts[0]
        self.path = requestParts[1].components(separatedBy: "?").first ?? requestParts[1]
        if bodyData.isEmpty {
            self.bodyDictionary = [:]
        } else if let object = try? JSONSerialization.jsonObject(with: bodyData),
                  let dictionary = object as? JSONDictionary {
            self.bodyDictionary = dictionary
        } else {
            self.bodyDictionary = [:]
        }
    }
}

private enum HTTPStatus {
    nonisolated static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        default: return "Internal Server Error"
        }
    }
}

private extension TemplateValidationServer {
    static let pageFactsScript = """
    return {
      url: location.href,
      title: document.title,
      readyState: document.readyState,
      activeElement: elementSummary(document.activeElement)
    };

    function elementSummary(el) {
      if (!el) { return null; }
      return {
        tagName: el.tagName ? el.tagName.toLowerCase() : null,
        role: el.getAttribute ? el.getAttribute('role') : null,
        ariaLabel: shortText(el.getAttribute ? el.getAttribute('aria-label') : ''),
        placeholder: shortText(el.getAttribute ? el.getAttribute('placeholder') : ''),
        id: shortText(el.id || ''),
        classes: shortText(el.className || '')
      };
    }

    function shortText(value) {
      const text = sanitizeText(String(value || '').replace(/\\s+/g, ' ').trim());
      return text.length > 80 ? `${text.slice(0, 77)}...` : text;
    }

    function sanitizeText(value) {
      const text = String(value || '').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/gi, '[email]');
      if (/^Google Account:/i.test(text)) { return 'Google Account: [redacted]'; }
      return text;
    }
    """

    static func focusSelectorScript(selector: String, shouldFocus: Bool) -> String {
        """
        const selector = \(jsonString(selector));
        const matches = Array.from(document.querySelectorAll(selector));
        const firstVisible = matches.find(isVisible) || null;
        if (firstVisible && \(shouldFocus ? "true" : "false")) {
          firstVisible.focus();
        }
        return {
          selector,
          count: matches.length,
          visibleCount: matches.filter(isVisible).length,
          firstVisible: elementSummary(firstVisible),
          activeElement: elementSummary(document.activeElement),
          focused: firstVisible ? firstVisible === document.activeElement : false
        };

        function isVisible(el) {
          if (!el) { return false; }
          const style = window.getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          return style.visibility !== 'hidden' &&
            style.display !== 'none' &&
            rect.width > 0 &&
            rect.height > 0;
        }

        function elementSummary(el) {
          if (!el) { return null; }
          return {
            tagName: el.tagName ? el.tagName.toLowerCase() : null,
            role: el.getAttribute ? el.getAttribute('role') : null,
            ariaLabel: shortText(el.getAttribute ? el.getAttribute('aria-label') : ''),
            placeholder: shortText(el.getAttribute ? el.getAttribute('placeholder') : ''),
            title: shortText(el.getAttribute ? el.getAttribute('title') : ''),
            disabled: Boolean(el.disabled || el.getAttribute?.('aria-disabled') === 'true')
          };
        }

        function shortText(value) {
          const text = sanitizeText(String(value || '').replace(/\\s+/g, ' ').trim());
          return text.length > 80 ? `${text.slice(0, 77)}...` : text;
        }

        function sanitizeText(value) {
          const text = String(value || '').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/gi, '[email]');
          if (/^Google Account:/i.test(text)) { return 'Google Account: [redacted]'; }
          return text;
        }
        """
    }

    static func buttonsScript(limit: Int) -> String {
        let bounded = max(1, min(limit, 120))
        return """
        const candidates = Array.from(document.querySelectorAll('button, [role="button"], a, [aria-label], [data-testid], input, textarea'));
        return {
          count: candidates.length,
          visibleCount: candidates.filter(isVisible).length,
          items: candidates.filter(isVisible).slice(0, \(bounded)).map(elementSummary)
        };

        function isVisible(el) {
          if (!el) { return false; }
          const style = window.getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          return style.visibility !== 'hidden' &&
            style.display !== 'none' &&
            rect.width > 0 &&
            rect.height > 0;
        }

        function elementSummary(el) {
          const ariaLabel = shortText(el.getAttribute ? el.getAttribute('aria-label') : '');
          const accountLike = /^Google Account:/i.test(ariaLabel) || el.getAttribute?.('data-testid') === 'accounts-profile-button';
          const historyLike = Boolean(el.closest?.("nav[aria-label='Chat history'], [aria-label='Chat history']"));
          return {
            tagName: el.tagName ? el.tagName.toLowerCase() : null,
            role: el.getAttribute ? el.getAttribute('role') : null,
            ariaLabel,
            title: shortText(el.getAttribute ? el.getAttribute('title') : ''),
            text: accountLike || historyLike ? '[redacted]' : shortText(el.innerText || el.value || ''),
            testID: shortText(el.getAttribute ? el.getAttribute('data-testid') : ''),
            classes: shortText(el.className || ''),
            ariaPressed: shortText(el.getAttribute ? el.getAttribute('aria-pressed') : ''),
            ariaChecked: shortText(el.getAttribute ? el.getAttribute('aria-checked') : ''),
            disabled: Boolean(el.disabled || el.getAttribute?.('aria-disabled') === 'true')
          };
        }

        function shortText(value) {
          const text = sanitizeText(String(value || '').replace(/\\s+/g, ' ').trim());
          return text.length > 80 ? `${text.slice(0, 77)}...` : text;
        }

        function sanitizeText(value) {
          const text = String(value || '').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/gi, '[email]');
          if (/^Google Account:/i.test(text)) { return 'Google Account: [redacted]'; }
          return text;
        }
        """
    }

    static let geminiStateScript = """
    const temporaryToggle = document.querySelector([
      ".temp-chat-on button[aria-label='Temporary chat']",
      ".temp-chat-on [aria-label='Temporary chat']",
      "button[aria-label='Turn off temporary chat']",
      "[aria-label='Turn off temporary chat']",
      "button[aria-label='Temporary chat'][aria-pressed='true']",
      "[aria-label='Temporary chat'][aria-checked='true']"
    ].join(","));
    const temporaryHeader = Array.from(document.querySelectorAll(".temporary-chat-header, [role='heading'], h1, h2, h3, span, div")).some((element) =>
      shortText(element.innerText || element.textContent || element.getAttribute?.("aria-label") || "") === "Temporary Chat"
    );
    const shareConversation = Array.from(document.querySelectorAll("button, [role='menuitem'], [aria-label]")).some((element) =>
      shortText(element.getAttribute?.("aria-label") || element.innerText || element.textContent || "") === "Share conversation"
    );
    return {
      temporaryActive: Boolean(temporaryToggle || temporaryHeader),
      temporaryToggleVisible: Boolean(temporaryToggle && isVisible(temporaryToggle)),
      temporaryHeaderVisible: temporaryHeader,
      sidebarOpen: Boolean(document.querySelector("button[aria-label='Close sidebar'], button[aria-label='Close navigation menu']")),
      sidebarOpenButtonVisible: Boolean(document.querySelector("button[aria-label='Open sidebar'], button[aria-label='Open navigation menu']")),
      shareConversationVisible: shareConversation,
      dialogVisible: Boolean(document.querySelector("[role='dialog']"))
    };

    function isVisible(el) {
      if (!el) { return false; }
      const style = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.visibility !== 'hidden' &&
        style.display !== 'none' &&
        rect.width > 0 &&
        rect.height > 0;
    }

    function shortText(value) {
      return String(value || '').replace(/\\s+/g, ' ').trim();
    }
    """

    static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}

private extension Data {
    nonisolated mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
#endif
