import Foundation
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

    private var browser: NWBrowser?
    private var connection: NWConnection?

    func start() {
        startBrowsing()
    }

    func startBrowsing() {
        stopBrowsing()
        browsing = true
        let browser = NWBrowser(
            for: .bonjour(type: KnurlBonjour.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed(let error) = state {
                    self?.lastError = error.localizedDescription
                    self?.browsing = false
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.macs = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        return DiscoveredMac(name: name, endpoint: result.endpoint)
                    default:
                        return nil
                    }
                }
                .sorted { $0.name < $1.name }
                if self?.connection == nil, let first = self?.macs.first {
                    self?.connect(first)
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
        connection?.cancel()
        let connection = NWConnection(to: mac.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.send(CrownRequest(action: .hello), on: connection)
                    self?.receive(connection)
                case .failed(let error):
                    self?.lastError = error.localizedDescription
                    self?.connection = nil
                case .cancelled:
                    if self?.connection === connection {
                        self?.connection = nil
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
    }

    func confirm() {
        send(CrownRequest(action: .confirm))
    }

    func select(_ mode: String) {
        send(CrownRequest(action: .select, mode: mode))
    }

    private func send(_ request: CrownRequest, on connection: NWConnection? = nil) {
        guard let connection = connection ?? self.connection,
              var payload = try? CrownJSON.encoder.encode(request)
        else { return }
        payload.append(contentsOf: [0x0A])
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, _ in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    let trimmed = data.prefix { $0 != 0x0A }
                    if let hello = try? CrownJSON.decoder.decode(CrownHello.self, from: Data(trimmed)) {
                        self.hello = hello
                        self.lastError = nil
                    }
                }
                if isComplete {
                    if self.connection === connection {
                        self.connection = nil
                    }
                } else {
                    self.receive(connection)
                }
            }
        }
    }
}
