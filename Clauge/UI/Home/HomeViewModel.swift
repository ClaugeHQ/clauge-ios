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

    /// The open can hang if the desktop app is backgrounded/asleep (the frontend
    /// that drives auth modals isn't running). Bound the spawn so the loader never
    /// sticks forever; Cancel aborts immediately.
    private let spawnTimeout: Duration = .seconds(45)
    private var spawnTask: Task<Void, Never>?
    private var spawnRequestId: String?

    private struct TimeoutError: Error {}

    /// Consecutive failed refreshes since the last success.
    private var consecutiveFailures = 0
    /// Cold-load retry backoff. The first navigation has to resolve the desktop's
    /// address and hit a possibly-busy server; a single transient miss must not
    /// drop straight to the "Can't reach" state — retry a few times first.
    private let firstLoadBackoffs: [Duration] = [.seconds(0.8), .seconds(1.6), .seconds(3.2)]
    /// Once loaded, how many CONSECUTIVE refresh failures to absorb before
    /// flagging offline, so a flaky-network blip doesn't flap the loaded list.
    private let steadyFailureGrace = 2

    /// Kick a first load as soon as the model exists so a cockpit tab never
    /// shows an empty list before `start()` runs.
    init() {
        Task { await refresh() }
    }

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
                // Task cancellation (view teardown, poll stop) isn't a real
                // failure — bail without counting it or flagging offline.
                if Task.isCancelled { return }
                if retryable && attempt < firstLoadBackoffs.count {
                    try? await Task.sleep(for: firstLoadBackoffs[attempt])
                    attempt += 1
                    continue
                }
                consecutiveFailures += 1
                // Hold a loaded list through a brief blip — only show "Can't
                // reach" once failures are sustained. A cold load (never loaded)
                // surfaces immediately.
                if !loaded || consecutiveFailures > steadyFailureGrace {
                    offline = true
                }
                return
            }
        }
    }

    /// Resolve a tapped agent row to a terminalId, spawning if needed. Live
    /// sessions open immediately; a spawn shows the cancellable "Starting…"
    /// overlay and calls `onReady` with the returned terminalId on success.
    func openAgent(_ session: AgentSessionDto, onReady: @escaping (String) -> Void) {
        switch AttachDecision.forAgent(session) {
        case .live(let id):
            onReady(id)
        case .spawn:
            startSpawn(title: session.title, onReady: onReady) { [client] rid in
                try await client.spawnAgent(sessionId: session.id, requestId: rid)
            }
        }
    }

    func openSsh(_ profile: SshProfileDto, onReady: @escaping (String) -> Void) {
        switch AttachDecision.forSsh(profile) {
        case .live(let id):
            onReady(id)
        case .spawn:
            startSpawn(title: profile.name, onReady: onReady) { [client] rid in
                try await client.spawnSsh(profileId: profile.id, requestId: rid)
            }
        }
    }

    /// Run the spawn handshake under a timeout with a fresh requestId. On
    /// Cancel or timeout we tell the desktop to abort the open — otherwise a
    /// lidded/backgrounded desktop opens the tab anyway when it wakes.
    private func startSpawn(title: String,
                            onReady: @escaping (String) -> Void,
                            spawn: @escaping (String) async throws -> String) {
        let requestId = UUID().uuidString
        spawningTitle = title
        spawnRequestId = requestId
        spawnTask = Task { [weak self] in
            guard let self else { return }
            do {
                let terminalId = try await self.withTimeout { try await spawn(requestId) }
                self.clearSpawn()
                onReady(terminalId)
            } catch is CancellationError {
                // User tapped Cancel; cleanup already done in cancelSpawn().
            } catch is TimeoutError {
                self.clearSpawn()
                try? await self.client.cancelOpen(requestId: requestId)
                self.toast = "\(title) is taking too long — open the desktop app and try again"
            } catch {
                self.clearSpawn()
                self.toast = "Couldn't start \(title) — check the desktop is reachable"
            }
        }
    }

    /// Cancel an in-flight spawn from the loader's Cancel button.
    func cancelSpawn() {
        let rid = spawnRequestId
        spawnTask?.cancel()
        clearSpawn()
        if let rid { Task { [client] in try? await client.cancelOpen(requestId: rid) } }
    }

    private func clearSpawn() {
        spawningTitle = nil
        spawnRequestId = nil
        spawnTask = nil
    }

    private func withTimeout(_ operation: @escaping () async throws -> String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await operation() }
            group.addTask { [spawnTimeout] in
                try await Task.sleep(for: spawnTimeout)
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
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
