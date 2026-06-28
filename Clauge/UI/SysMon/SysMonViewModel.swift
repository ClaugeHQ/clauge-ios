import Foundation
import SwiftUI

@MainActor
final class SysMonViewModel: ObservableObject {
    @Published var metrics: SysMetricsDto?
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []
    @Published var loading = false
    @Published var error: String?

    private let client = Services.shared.client
    private var poll: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    private let historyLimit = 40

    func start() {
        refresh()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                self?.refresh()
            }
        }
    }

    func stop() {
        poll?.cancel(); poll = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    /// Serialized refresh: a single in-flight poll at a time. Re-entrant calls
    /// (poll tick + manual tap) collapse into the running one instead of
    /// stacking overlapping requests.
    func refresh() {
        if refreshTask != nil { return }
        refreshTask = Task { [weak self] in
            await self?.load()
            self?.refreshTask = nil
        }
    }

    private func load() async {
        if metrics == nil { loading = true }
        do {
            let m = try await client.sysMetrics()
            let memPct = m.memory.totalBytes > 0
                ? Double(m.memory.usedBytes) / Double(m.memory.totalBytes) * 100
                : 0
            metrics = m
            loading = false
            error = nil
            cpuHistory = Array((cpuHistory + [m.cpu.usagePct]).suffix(historyLimit))
            memHistory = Array((memHistory + [memPct]).suffix(historyLimit))
        } catch is CancellationError {
            // View teardown / poll stop — not a real failure.
        } catch {
            if Task.isCancelled { return }
            loading = false
            // Surface the error even once metrics have loaded so a stalled
            // desktop is visible behind the last good snapshot.
            self.error = error.localizedDescription
        }
    }
}
