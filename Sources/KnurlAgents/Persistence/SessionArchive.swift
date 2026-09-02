import Foundation

/// Codable JSON, one file per session, actor-serialised. Deliberately not
/// SwiftData: KNURL_SESSION_LAYER_PLAN.md holds that until receipts prove they
/// need a query engine, and the archive is append-mostly with small reads.
public actor SessionArchive {
    private let directory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory(bundleID: String = "com.shualabs.knurl") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: bundleID).appending(path: "sessions")
    }

    public func save(_ session: AgentSession) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(session.id.uuidString).json")
            try encoder.encode(session).write(to: url, options: .atomic)
        } catch {
            // A failed write must never take the desk down with it.
        }
    }

    /// Skips unreadable or malformed files rather than failing the whole load.
    public func loadAll() -> [AgentSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let sessions = names
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AgentSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(AgentSession.self, from: data)
            }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(_ id: UUID) {
        let url = directory.appending(path: "\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// Retention sweep. `nil` days means keep forever.
    public func prune(olderThan days: Int?, now: Date = Date()) {
        guard let days else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        for session in loadAll() where session.startedAt < cutoff {
            delete(session.id)
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
