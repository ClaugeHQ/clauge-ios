import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    enum Tab: Hashable { case agent, ssh }

    @Published var tab: Tab = .agent
    @Published var agents: [AgentSessionDto] = []
    @Published var ssh: [SshProfileDto] = []
    @Published var loaded = false
    @Published var offline = false
    @Published var spawningTitle: String?
    @Published var toast: String?

    private let client = Services.shared.client
    private var poll: Task<Void, Never>?

    /// Consecutive failed refreshes since the last success.
    private var consecutiveFailures = 0
    /// Cold-load retry backoff. The first navigation has to resolve the desktop's
    /// address and hit a possibly-busy server; a single transient miss must not
    /// drop straight to the "Can't reach" state — retry a few times first.
    private let firstLoadBackoffs: [Duration] = [.seconds(0.8), .seconds(1.6), .seconds(3.2)]
    /// Once loaded, how many CONSECUTIVE refresh failures to absorb before
    /// flagging offline, so a flaky-network blip doesn't flap the loaded list.
    private let steadyFailureGrace = 2

    func start() {
        Task { await refresh() }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refresh()
            }
        }
    }

    func stop() { poll?.cancel(); poll = nil }

    func refresh() async {
        // Retry only the cold first load (nothing on screen yet); a loaded list
        // takes the single-attempt + grace path below.
        let retryable = !loaded
        var attempt = 0
        while true {
            do {
                let a = try await client.listAgentSessions()
                let s = try await client.listSshProfiles()
                agents = a
                ssh = s
                consecutiveFailures = 0
                offline = false
                loaded = true
                return
            } catch {
                if retryable && attempt < firstLoadBackoffs.count {
                    try? await Task.sleep(for: firstLoadBackoffs[attempt])
                    attempt += 1
                    continue
                }
                consecutiveFailures += 1
                // Hold a loaded list through a brief blip — only show "Can't
                // reach" once failures are sustained. A cold load (never loaded)
                // surfaces immediately.
                if !loaded || consecutiveFailures >= steadyFailureGrace {
                    offline = true
                }
                return
            }
        }
    }

    /// Resolve a tapped agent row to a terminalId, spawning if needed.
    func openAgent(_ session: AgentSessionDto) async -> String? {
        switch AttachDecision.forAgent(session) {
        case .live(let id):
            return id
        case .spawn:
            spawningTitle = session.title
            defer { spawningTitle = nil }
            do { return try await client.spawnAgent(sessionId: session.id) }
            catch {
                toast = "Couldn't start \(session.title) — check the desktop is reachable"
                return nil
            }
        }
    }

    func openSsh(_ profile: SshProfileDto) async -> String? {
        switch AttachDecision.forSsh(profile) {
        case .live(let id):
            return id
        case .spawn:
            spawningTitle = profile.name
            defer { spawningTitle = nil }
            do { return try await client.spawnSsh(profileId: profile.id) }
            catch {
                toast = "Couldn't start \(profile.name) — check the desktop is reachable"
                return nil
            }
        }
    }

    // Agents grouped by project basename, sorted; ungrouped last under "Ungrouped".
    struct Group: Identifiable {
        let id: String
        let label: String
        let sessions: [AgentSessionDto]
    }

    var agentGroups: [Group] {
        var buckets: [String: [AgentSessionDto]] = [:]
        for s in agents {
            let base = (s.projectPath as NSString).lastPathComponent
            let key = base.isEmpty ? " ungrouped" : base
            buckets[key, default: []].append(s)
        }
        return buckets.keys.sorted().map { key in
            Group(id: key,
                  label: key == " ungrouped" ? "Ungrouped" : key,
                  sessions: buckets[key]!.sorted { $0.id < $1.id })
        }
    }
}
