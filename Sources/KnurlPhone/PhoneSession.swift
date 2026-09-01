import Foundation
import KnurlCore
import KnurlLink
import Network
import Observation

struct DiscoveredMac: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var endpoint: NWEndpoint
}

@MainActor
@Observable
final class PhoneSession {
    var macs: [DiscoveredMac] = []
    var hello: CrownHello?
    var lastError: String?
    var browsing = false
    var connectedName: String?
    var dragging = false
    var helloAt = Date()
    var detentTick = 0
    var confirmTick = 0
    var faceTick = 0
    var face = DialMode.volume.rawValue
    var art: Data?

    var isConnected: Bool { connection != nil && hello != nil }

    var currentMode: DialMode { DialMode(rawValue: face) ?? .volume }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var browseGeneration = 0
    private var incoming = Data()
    private var artByKey: [String: Data] = [:]
    private var artOrder: [String] = []
    private var lastFaceTap = Date.distantPast

    func start() {
        startBrowsing()
    }

    func refresh() {
        lastError = nil
        startBrowsing()
    }

    func startBrowsing() {
        stopBrowsing()
        browsing = true
        browseGeneration += 1
        let generation = browseGeneration
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: KnurlBonjour.serviceType, domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, generation == self.browseGeneration else { return }
                if case .failed(let error) = state {
                    self.lastError = error.localizedDescription
                    self.browsing = false
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, generation == self.browseGeneration else { return }
                self.macs = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        return DiscoveredMac(name: name, endpoint: result.endpoint)
                    default:
                        return nil
                    }
                }
                .sorted { $0.name < $1.name }
                if self.connection == nil, let first = self.macs.first {
                    self.connect(first)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        browsing = false
    }

    func connect(_ mac: DiscoveredMac) {
        lastError = nil
        hello = nil
        connectedName = mac.name
        connection?.cancel()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: mac.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.send(CrownRequest(action: .hello), on: connection)
                    self?.receive(connection)
                case .failed(let error):
                    self?.lastError = error.localizedDescription
                    self?.connection = nil
                    self?.hello = nil
                    self?.retryFirstMac()
                case .cancelled:
                    if self?.connection === connection {
                        self?.connection = nil
                        self?.hello = nil
                    }
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }

    func rotate(_ detents: Int) {
        send(CrownRequest(action: .rotate, detents: detents))
        detentTick += 1
    }

    func setProgress(_ progress: Double) {
        send(CrownRequest(action: .rotate, progress: progress))
    }

    func tickDetent() {
        detentTick += 1
    }

    func confirm() {
        send(CrownRequest(action: .confirm))
        confirmTick += 1
    }

    func select(_ mode: String) {
        face = mode
        lastFaceTap = Date()
        faceTick += 1
        send(CrownRequest(action: .select, mode: mode))
    }

    func cycleFace(_ delta: Int) {
        let current = DialMode(rawValue: face) ?? .volume
        select(current.advanced(by: delta).rawValue)
    }

    func skip(_ direction: Int) {
        send(CrownRequest(action: .skip, detents: direction))
        confirmTick += 1
    }

    func shuffle() {
        send(CrownRequest(action: .shuffle))
        confirmTick += 1
    }

    func cycleRepeat() {
        send(CrownRequest(action: .repeat))
        confirmTick += 1
    }

    func pick(_ name: String) {
        send(CrownRequest(action: .pick, name: name))
        confirmTick += 1
    }

    private func apply(_ hello: CrownHello) {
        if hello.progress != self.hello?.progress || hello.playing != self.hello?.playing {
            helloAt = Date()
        }
        if Date().timeIntervalSince(lastFaceTap) > 0.45 {
            face = hello.mode
        }
        if let key = hello.artKey {
            if let raw = hello.art, let data = Data(base64Encoded: raw) {
                artByKey[key] = data
                artOrder.removeAll { $0 == key }
                artOrder.append(key)
                while artOrder.count > 4 {
                    artByKey[artOrder.removeFirst()] = nil
                }
            }
            art = artByKey[key]
        } else if hello.mode != "media" {
            art = nil
        }
        self.hello = hello
        lastError = nil
    }

    private func retryFirstMac() {
        guard connection == nil, !macs.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard self.connection == nil, let mac = self.macs.first else { return }
            self.connect(mac)
        }
    }

    private func send(_ request: CrownRequest, on connection: NWConnection? = nil) {
        guard let connection = connection ?? self.connection,
              var payload = try? CrownJSON.encoder.encode(request)
        else { return }
        payload.append(contentsOf: [0x0A])
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, _ in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    self.incoming.append(data)
                    while let newline = self.incoming.firstIndex(of: 0x0A) {
                        let chunk = self.incoming[..<newline]
                        self.incoming.removeSubrange(...newline)
                        if let hello = try? CrownJSON.decoder.decode(CrownHello.self, from: Data(chunk)) {
                            self.apply(hello)
                        }
                    }
                }
                if isComplete {
                    if self.connection === connection {
                        self.connection = nil
                        self.hello = nil
                    }
                } else {
                    self.receive(connection)
                }
            }
        }
    }
}
