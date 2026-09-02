import AppKit
import Foundation
import KnurlAgents

/// Watches which application is frontmost. This is the fallback that makes
/// basic integration work: it gives session duration, human-vs-agent split and
/// context switches for any agent, with no hooks and no screen recording.
///
/// Event-driven via NSWorkspace notifications — the session layer must not add
/// a fourth poll loop.
@MainActor
final class ActivityMonitor {
    /// Fires when the frontmost app changes. `agent` is non-nil when the new
    /// frontmost app is a known agent.
    var onSwitch: ((_ agent: AgentKind?, _ bundleID: String?, _ appName: String) -> Void)?

    private var observer: (any NSObjectProtocol)?
    private(set) var currentBundleID: String?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handle(app)
            }
        }
        handle(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func handle(_ app: NSRunningApplication?) {
        guard let app else { return }
        let bundleID = app.bundleIdentifier
        guard bundleID != currentBundleID else { return }
        currentBundleID = bundleID
        // Knurl activating itself is not a context switch out of the work.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        onSwitch?(Self.agent(for: bundleID), bundleID, app.localizedName ?? "Unknown")
    }

    static func agent(for bundleID: String?) -> AgentKind? {
        guard let bundleID else { return nil }
        return AgentKind.allCases.first { $0.bundleIdentifiers.contains(bundleID) }
    }
}

/// Resolves the project and repository for a working directory. Read-only: it
/// runs `git rev-parse`, never mutates a repo, and refuses to look inside
/// sealed work directories.
enum RepositoryMonitor {
    /// Paths the session layer must never inspect. `~/Nectar-Work` is day-job
    /// infrastructure owned by another tool.
    static let sealedPrefixes: [String] = [
        NSString(string: "~/Nectar-Work").expandingTildeInPath,
    ]

    static func isSealed(_ path: String) -> Bool {
        let resolved = NSString(string: path).expandingTildeInPath
        return sealedPrefixes.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
    }

    struct Repository: Sendable, Equatable {
        var root: String
        var name: String
        var branch: String?
    }

    static func repository(at path: String) -> Repository? {
        guard !isSealed(path) else { return nil }
        guard let root = git(["rev-parse", "--show-toplevel"], in: path), !root.isEmpty else { return nil }
        guard !isSealed(root) else { return nil }
        let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        return Repository(
            root: root,
            name: URL(fileURLWithPath: root).lastPathComponent,
            branch: branch?.isEmpty == false ? branch : nil
        )
    }

    /// Commits on the current branch since a point in time, newest first.
    /// Returns subject lines only — never diffs or file contents.
    static func commits(in root: String, since: Date) -> [(hash: String, subject: String)] {
        guard !isSealed(root) else { return [] }
        let stamp = ISO8601DateFormatter().string(from: since)
        guard let output = git(["log", "--since=\(stamp)", "--pretty=format:%h%x1f%s"], in: root) else {
            return []
        }
        return output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\u{1f}", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            }
    }

    static func isRevert(_ subject: String) -> Bool {
        let lowered = subject.lowercased()
        return lowered.hasPrefix("revert ") || lowered.hasPrefix("revert:")
    }

    private static func git(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
