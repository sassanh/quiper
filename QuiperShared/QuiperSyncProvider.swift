import Combine
import Foundation
#if os(iOS)
import UIKit
#endif
@preconcurrency import Network

struct QuiperSyncTransfer: Identifiable, Equatable {
    let id = UUID()
    let peerName: String
    let timestamp: Date
}

@MainActor
final class QuiperSyncProvider: ObservableObject, @unchecked Sendable {
    @Published var isAdvertising: Bool = false
    @Published var errorMessage: String?
    @Published var advertisedName: String = ""
    @Published var servedCount: Int = 0
    @Published var transfers: [QuiperSyncTransfer] = []

    private var listener: NWListener?
    private let syncData: Data
    private let queue = DispatchQueue.main
    private var connections: [NWConnection] = []

    private final class WeakBox: @unchecked Sendable {
        weak var target: QuiperSyncProvider?
        init(_ target: QuiperSyncProvider) { self.target = target }
    }

    init(data: Data) {
        self.syncData = data
        let baseName = QuiperSyncProtocol.deviceDisplayName
        let suffix = String(UUID().uuidString.prefix(4))
        self.advertisedName = "Quiper \(baseName) \(suffix)"
    }

    func start() {
        guard listener == nil else { return }
        errorMessage = nil
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            parameters.allowLocalEndpointReuse = true

            let txt = NWTXTRecord([
                "v": "1",
                "displayName": QuiperSyncProtocol.deviceDisplayName,
                "quiperVersion": Bundle.main.versionDisplayString,
                "id": UUID().uuidString
            ])
            let service = NWListener.Service(
                name: advertisedName,
                type: QuiperSyncProtocol.serviceType,
                domain: QuiperSyncProtocol.serviceDomain,
                txtRecord: txt
            )
            let listener = try NWListener(service: service, using: parameters)
            let box = WeakBox(self)
            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    guard let self = box.target else { return }
                    switch state {
                    case .setup:
                        break
                    case .waiting:
                        // Still waiting for Bonjour/TCC – keep spinner; do not clear a hint already shown by timeout
                        self.isAdvertising = false
                        if self.errorMessage == nil {
                            // keep nil until timeout fires; if hint already set, preserve it
                        }
                    case .ready:
                        self.isAdvertising = true
                        self.errorMessage = nil
                    case .failed(let error):
                        self.isAdvertising = false
                        self.errorMessage = error.localizedDescription
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            let newBox = WeakBox(self)
            listener.newConnectionHandler = { connection in
                Task { @MainActor in
                    guard let self = newBox.target else { return }
                    self.handle(connection: connection)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            // If still not ready after 10s, surface a helpful hint (covers hidden TCC dialog)
            let waitBox = WeakBox(self)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self = waitBox.target, !self.isAdvertising, self.errorMessage == nil else { return }
                self.errorMessage = "Still waiting for local network. If the system permission dialog is hidden behind this window, check System Settings → Privacy & Security → Local Network and allow Quiper, then close and re-open sharing."
            }
        } catch {
            errorMessage = error.localizedDescription
            isAdvertising = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
    }

    private func handle(connection: NWConnection) {
        connections.append(connection)
        let box = WeakBox(self)
        connection.stateUpdateHandler = { state in
            if case .cancelled = state {
                Task { @MainActor in
                    guard let self = box.target else { return }
                    self.connections.removeAll { $0 === connection }
                }
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        let box = WeakBox(self)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let nextBuffer: Data = {
                var b = buffer
                if let data { b.append(data) }
                return b
            }()
            if let error {
                Task { @MainActor in
                    guard let self = box.target else { return }
                    self.sendError(on: connection, status: 400, message: error.localizedDescription)
                }
                return
            }
            if let request = QuiperSyncHTTPRequest(data: nextBuffer) {
                Task { @MainActor in
                    guard let self = box.target else { return }
                    self.handleRequest(request, on: connection)
                }
                return
            }
            if isComplete {
                Task { @MainActor in
                    guard let self = box.target else { return }
                    self.sendError(on: connection, status: 400, message: "incomplete request")
                }
                return
            }
            Task { @MainActor in
                guard let self = box.target else { return }
                self.receiveRequest(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func handleRequest(_ request: QuiperSyncHTTPRequest, on connection: NWConnection) {
        if request.method == "GET" && (request.path == QuiperSyncProtocol.httpPath || request.path == "/config" || request.path == "/quiper-config") {
            serveConfig(on: connection)
            return
        }
        if request.method == "POST" && (request.path == QuiperSyncProtocol.ackPath) {
            handleAck(request, on: connection)
            return
        }
        sendError(on: connection, status: 404, message: "not found")
    }

    private func handleAck(_ request: QuiperSyncHTTPRequest, on connection: NWConnection) {
        var peerName = "Device"
        if !request.body.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
           let name = json["receiverName"] as? String, !name.isEmpty {
            peerName = name
        } else if let name = request.headers["x-receiver-name"], !name.isEmpty {
            peerName = name
        }
        let transfer = QuiperSyncTransfer(peerName: peerName, timestamp: Date())
        transfers.append(transfer)
        servedCount += 1

        let body = try? JSONSerialization.data(withJSONObject: ["ok": true])
        let bodyData = body ?? Data("{\"ok\":true}".utf8)
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func serveConfig(on connection: NWConnection) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Content-Length: \(syncData.count)\r\n"
        header += "Connection: close\r\n"
        header += "X-Quiper-Version: \(Bundle.main.versionDisplayString)\r\n"
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(syncData)
        // Do not count as served yet; wait for ack
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendError(on connection: NWConnection, status: Int, message: String) {
        let body = "{\"error\":\"\(message)\"}".data(using: .utf8) ?? Data()
        var header = "HTTP/1.1 \(status) Error\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    deinit {
        listener?.cancel()
    }
}

private struct QuiperSyncHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        self.method = parts[0]
        let rawPath = parts[1]
        self.path = rawPath.components(separatedBy: "?").first ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let comps = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if comps.count == 2 {
                headers[comps[0].lowercased()] = comps[1]
            }
        }
        self.headers = headers

        let bodyStart = headerRange.upperBound
        let bodyData = data[bodyStart...]
        if let contentLengthStr = headers["content-length"], let contentLength = Int(contentLengthStr) {
            guard bodyData.count >= contentLength else { return nil }
            self.body = Data(bodyData.prefix(contentLength))
        } else {
            // No Content-Length; for GET, body is empty; for POST without length, treat remaining as body if present, else empty
            if method == "POST" && !bodyData.isEmpty {
                // If body present but no length, wait for completion in receive loop will handle; here we treat as not complete unless connection closed
                // For now, require Content-Length for POST to know completeness
                return nil
            }
            self.body = Data()
        }
    }
}
