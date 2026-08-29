import Foundation
@preconcurrency import Network

enum QuiperSyncClientError: LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .httpError(let code, let msg): return "Provider error (\(code)): \(msg)"
        case .emptyData: return "Provider returned empty data."
        }
    }
}

enum QuiperSyncClient {
    static func fetch(from endpoint: NWEndpoint) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let queue = DispatchQueue.main
            let connection = NWConnection(to: endpoint, using: .tcp)
            final class StateBox: @unchecked Sendable {
                var hasResumed = false
                var buffer = Data()
                let lock = NSLock()
            }
            let box = StateBox()

            func resumeOnce(_ result: Result<Data, Error>) {
                box.lock.lock()
                defer { box.lock.unlock() }
                guard !box.hasResumed else { return }
                box.hasResumed = true
                connection.cancel()
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = "GET \(QuiperSyncProtocol.httpPath) HTTP/1.1\r\nHost: quipersync\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                        if let error {
                            resumeOnce(.failure(QuiperSyncClientError.connectionFailed(error.localizedDescription)))
                        }
                    })
                case .failed(let error):
                    resumeOnce(.failure(QuiperSyncClientError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    break
                default: break
                }
            }

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { data, _, isComplete, error in
                    if let error {
                        resumeOnce(.failure(QuiperSyncClientError.connectionFailed(error.localizedDescription)))
                        return
                    }
                    if let data { box.buffer.append(data) }

                    if let headerEnd = box.buffer.range(of: Data("\r\n\r\n".utf8)) {
                        let headerData = box.buffer[..<headerEnd.lowerBound]
                        guard let headerText = String(data: headerData, encoding: .utf8) else {
                            resumeOnce(.failure(QuiperSyncClientError.invalidResponse("invalid headers")))
                            return
                        }
                        let headerLines = headerText.components(separatedBy: "\r\n")
                        let statusLine = headerLines.first ?? ""
                        let statusCode: Int = {
                            let parts = statusLine.split(separator: " ")
                            if parts.count >= 2, let code = Int(parts[1]) { return code }
                            return 0
                        }()
                        var contentLength: Int? = nil
                        for line in headerLines.dropFirst() {
                            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                            if parts.count == 2, parts[0].lowercased() == "content-length" {
                                contentLength = Int(parts[1])
                            }
                        }
                        let bodyStart = headerEnd.upperBound
                        let body = box.buffer[bodyStart...]

                        if let contentLength {
                            if body.count < contentLength {
                                if isComplete {
                                    resumeOnce(.failure(QuiperSyncClientError.invalidResponse("incomplete body")))
                                } else {
                                    receiveLoop()
                                }
                                return
                            }
                            let bodyData = Data(body.prefix(contentLength))
                            if statusCode != 200 {
                                let msg = String(data: bodyData, encoding: .utf8) ?? "unknown"
                                resumeOnce(.failure(QuiperSyncClientError.httpError(statusCode, msg)))
                            } else {
                                if bodyData.isEmpty {
                                    resumeOnce(.failure(QuiperSyncClientError.emptyData))
                                } else {
                                    resumeOnce(.success(bodyData))
                                }
                            }
                            return
                        } else {
                            if isComplete {
                                let bodyData = Data(body)
                                if statusCode != 200 {
                                    let msg = String(data: bodyData, encoding: .utf8) ?? "unknown"
                                    resumeOnce(.failure(QuiperSyncClientError.httpError(statusCode, msg)))
                                } else {
                                    resumeOnce(.success(bodyData))
                                }
                                return
                            } else {
                                receiveLoop()
                                return
                            }
                        }
                    }

                    if isComplete {
                        resumeOnce(.failure(QuiperSyncClientError.invalidResponse("no header terminator")))
                        return
                    }
                    receiveLoop()
                }
            }

            connection.start(queue: queue)
            receiveLoop()

            queue.asyncAfter(deadline: .now() + 30) {
                resumeOnce(.failure(QuiperSyncClientError.connectionFailed("timed out")))
            }
        }
    }

    static func sendAck(to endpoint: NWEndpoint) async {
        let receiverName = QuiperSyncProtocol.deviceDisplayName
        let payload: [String: String] = [
            "receiverName": receiverName,
            "version": Bundle.main.versionDisplayString
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let queue = DispatchQueue.main
                let connection = NWConnection(to: endpoint, using: .tcp)
                final class AckBox: @unchecked Sendable {
                    var hasResumed = false
                    let lock = NSLock()
                }
                let box = AckBox()
                func resumeOnce(_ result: Result<Void, Error>) {
                    box.lock.lock()
                    defer { box.lock.unlock() }
                    guard !box.hasResumed else { return }
                    box.hasResumed = true
                    connection.cancel()
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        var request = "POST \(QuiperSyncProtocol.ackPath) HTTP/1.1\r\n"
                        request += "Host: quipersync\r\n"
                        request += "Content-Type: application/json\r\n"
                        request += "Content-Length: \(body.count)\r\n"
                        request += "Connection: close\r\n"
                        request += "\r\n"
                        var reqData = Data(request.utf8)
                        reqData.append(body)
                        connection.send(content: reqData, completion: .contentProcessed { error in
                            if let error {
                                resumeOnce(.failure(error))
                            }
                        })
                    case .failed(let error):
                        resumeOnce(.failure(error))
                    default: break
                    }
                }

                var buffer = Data()
                func receiveLoop() {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { data, _, isComplete, error in
                        if let error { resumeOnce(.failure(error)); return }
                        if let data { buffer.append(data) }
                        if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                            let headerData = buffer[..<headerEnd.lowerBound]
                            guard let headerText = String(data: headerData, encoding: .utf8) else {
                                resumeOnce(.failure(QuiperSyncClientError.invalidResponse("invalid ack headers")))
                                return
                            }
                            let statusLine = headerText.components(separatedBy: "\r\n").first ?? ""
                            let code: Int = {
                                let parts = statusLine.split(separator: " ")
                                if parts.count >= 2, let c = Int(parts[1]) { return c }
                                return 0
                            }()
                            if code == 200 {
                                resumeOnce(.success(()))
                            } else {
                                resumeOnce(.failure(QuiperSyncClientError.httpError(code, "ack failed")))
                            }
                            return
                        }
                        if isComplete {
                            resumeOnce(.failure(QuiperSyncClientError.invalidResponse("no ack header")))
                            return
                        }
                        receiveLoop()
                    }
                }

                connection.start(queue: queue)
                receiveLoop()
                queue.asyncAfter(deadline: .now() + 10) {
                    resumeOnce(.failure(QuiperSyncClientError.connectionFailed("ack timeout")))
                }
            }
        } catch {
            // Best-effort, ignore ack failures
        }
    }
}
