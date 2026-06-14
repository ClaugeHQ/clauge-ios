import Foundation
import SwiftUI

@MainActor
final class DevicesViewModel: ObservableObject {
    /// deviceId → reachable (nil = still checking)
    @Published var online: [String: Bool] = [:]

    private let client = Services.shared.client
    private let store = Services.shared.store
    private var poll: Task<Void, Never>?

    func start() {
        Task { await probeAll() }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.probeAll()
            }
        }
    }

    func stop() { poll?.cancel(); poll = nil }

    func refresh() async { await probeAll() }

    private func probeAll() async {
        let devices = store.devices
        var result: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for d in devices {
                group.addTask { (d.id, await self.client.reachable(d)) }
            }
            for await (id, ok) in group { result[id] = ok }
        }
        online = result
    }
}
