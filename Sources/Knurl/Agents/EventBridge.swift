import Foundation
import KnurlAgents
import Network
import os

/// Loopback-only receiver for agent hook events.
///
/// Security posture, per KNURL_SESSION_LAYER_PLAN.md: 127.0.0.1 only, one route
/// (`POST /event`), 64 KB body cap, typed JSON, unknown fields ignored, bad
/// input answered with 400 and never crashed on. There is deliberately no
/// /run, /exec or /shell — nothing in a payload is ever executed.
@MainActor
final class EventBridge {
    static let defaultPort: UInt16 = 51_741
    private static let maxBody = 64 * 1024

    private let log = Logger(subsystem: "Knurl.Agent", category: "Bridge")
    private var listener: NWListener?
    private var onEvent: ((HookPayload) -> Void)?

    private(set) var isRunning = false
    private(set) var lastError: String?

    /// What a hook script is allowed to send. Anything else is ignored.
    struct HookPayload: Codable, Sendable {
        var provider: String
        var sessionID: String
        var kind: String
        var project: String?
        var repository: String?
        var workingDirectory: String?
        var branch: String?
        var tool: String?
        var path: String?
        var summary: String?

        enum CodingKeys: String, CodingKey {
            case provider
            case sessionID = "session_id"
            case kind
            case project
            case repository
            case workingDirectory = "working_directory"
            case branch
            case tool
            case path
            case summary
        }
    }

    func start(port: UInt16 = EventBridge.defaultPort, onEvent: @escaping (HookPayload) -> Void) {
        guard listener == nil else { return }
        self.onEvent = onEvent
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                lastError = "Invalid bridge port"
                return
            }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            // Binding the loopback endpoint is what makes this local-only;
            // there is no interface on which this listener is reachable.
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastError = error.localizedDescription
                        self?.log.error("Bridge failed: \(error.localizedDescription, privacy: .public)")
                    case .ready where false:
                        break
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            log.error("Bridge failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }

                if buffer.count > Self.maxBody {
                    self.respond(connection, status: "413 Payload Too Large")
                    return
                }
                if let request = Self.parse(buffer) {
                    self.handle(request, on: connection)
                    return
                }
                if isComplete {
                    self.respond(connection, status: "400 Bad Request")
                    return
                }
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private struct Request {
        var method: String
        var path: String
        var body: Data
    }

    /// Returns nil while the request is still arriving.
    private static func parse(_ buffer: Data) -> Request? {
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self)
        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].lowercased() == "content-length" else { continue }
            length = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let body = buffer[separator.upperBound...]
        guard body.count >= length else { return nil }
        return Request(
            method: String(parts[0]),
            path: String(parts[1]),
            body: Data(body.prefix(length))
        )
    }

    private func handle(_ request: Request, on connection: NWConnection) {
        guard request.method == "POST", request.path == "/event" else {
            respond(connection, status: "404 Not Found")
            return
        }
        guard let payload = try? JSONDecoder().decode(HookPayload.self, from: request.body) else {
            respond(connection, status: "400 Bad Request")
            return
        }
        onEvent?(payload)
        respond(connection, status: "204 No Content")
    }

    private func respond(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
