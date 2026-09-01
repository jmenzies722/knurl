import Foundation
import KnurlLink
import Network

@MainActor
final class CrownServer {
    static let shared = CrownServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var incoming: [ObjectIdentifier: Data] = [:]
    private var lastArtKey: [ObjectIdentifier: String] = [:]
    private(set) var ready = false
    var clientCount: Int { connections.count }

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
        incoming = [:]
        lastArtKey = [:]
        listener?.cancel()
        listener = nil
        ready = false
    }

    func broadcast() {
        for connection in connections {
            sendHello(connection, forceArt: false)
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state {
                    self?.sendHello(connection, forceArt: true)
                    self?.receive(connection)
                    AppDelegate.shared?.state.noteCrownClient()
                }
                if case .failed = state { self?.drop(connection) }
                if case .cancelled = state { self?.drop(connection) }
            }
        }
        connection.start(queue: .main)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, _ in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    let id = ObjectIdentifier(connection)
                    var buffer = self.incoming[id] ?? Data()
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let chunk = buffer[..<newline]
                        buffer.removeSubrange(...newline)
                        if let request = try? CrownJSON.decoder.decode(CrownRequest.self, from: Data(chunk)) {
                            AppDelegate.shared?.state.applyCrown(request)
                            self.sendHello(connection, forceArt: request.action == .hello)
                        }
                    }
                    self.incoming[id] = buffer
                }
                if isComplete {
                    self.drop(connection)
                } else {
                    self.receive(connection)
                }
            }
        }
    }

    private func sendHello(_ connection: NWConnection, forceArt: Bool) {
        guard var hello = AppDelegate.shared?.state.crownHello() else { return }
        let id = ObjectIdentifier(connection)
        if let cover = AppDelegate.shared?.state.coverJPEG() {
            hello.artKey = cover.key
            if forceArt || lastArtKey[id] != cover.key {
                hello.art = cover.jpeg.base64EncodedString()
                lastArtKey[id] = cover.key
            }
        }
        guard let payload = try? CrownJSON.encoder.encode(hello) else { return }
        send(payload, on: connection)
    }

    private func send(_ payload: Data, on connection: NWConnection) {
        var line = payload
        line.append(contentsOf: [0x0A])
        connection.send(content: line, completion: .contentProcessed { _ in })
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        let id = ObjectIdentifier(connection)
        incoming[id] = nil
        lastArtKey[id] = nil
        connections.removeAll { $0 === connection }
    }
}
