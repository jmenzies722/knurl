import Foundation
import KnurlLink
import Network

@MainActor
final class CrownServer {
    static let shared = CrownServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var ready = false

    private init() {}

    func start() {
        stop()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: KnurlBonjour.serviceName,
                type: KnurlBonjour.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.ready = {
                        if case .ready = state { return true }
                        return false
                    }()
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            ready = false
        }
    }

    func stop() {
        connections.forEach { $0.cancel() }
        connections = []
        listener?.cancel()
        listener = nil
        ready = false
    }

    func broadcast() {
        guard let payload = try? CrownJSON.encoder.encode(AppDelegate.shared?.state.crownHello()) else { return }
        for connection in connections {
            send(payload, on: connection)
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state {
                    self?.sendHello(connection)
                    self?.receive(connection)
                }
                if case .failed = state { self?.drop(connection) }
                if case .cancelled = state { self?.drop(connection) }
            }
        }
        connection.start(queue: .main)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, _ in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    let trimmed = data.prefix { $0 != 0x0A }
                    if let request = try? CrownJSON.decoder.decode(CrownRequest.self, from: Data(trimmed)) {
                        AppDelegate.shared?.state.applyCrown(request)
                        self.sendHello(connection)
                    }
                }
                if isComplete {
                    self.drop(connection)
                } else {
                    self.receive(connection)
                }
            }
        }
    }

    private func sendHello(_ connection: NWConnection) {
        guard let payload = try? CrownJSON.encoder.encode(AppDelegate.shared?.state.crownHello()) else { return }
        send(payload, on: connection)
    }

    private func send(_ payload: Data, on connection: NWConnection) {
        var line = payload
        line.append(contentsOf: [0x0A])
        connection.send(content: line, completion: .contentProcessed { _ in })
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
}
