import Foundation

/// App-scoped store of the generic shell terminals opened from the Terminal nav
/// item. Tabs persist across navigation until explicitly closed.
@MainActor
final class TerminalsViewModel: ObservableObject {
    static let shared = TerminalsViewModel()

    @Published private(set) var tabs: [String] = []
    @Published private(set) var currentId: String?
    @Published private(set) var spawning = false
    @Published var error: String?

    private let client = Services.shared.client

    private init() {}

    func setCurrent(_ id: String) {
        currentId = id
    }

    /// The shell to reopen when the Terminal nav item is tapped, or nil if none.
    func currentOrLast() -> String? {
        if let id = currentId, tabs.contains(id) { return id }
        return tabs.last
    }

    /// Reopen the current/last shell if one is open, else spawn a new one.
    /// Returns the tab id to route to, or nil on failure.
    func openCurrentOrSpawn() async -> String? {
        if let id = currentOrLast() {
            currentId = id
            return id
        }
        return await spawn()
    }

    /// Spawn a new shell, record it, and return its id (nil on failure).
    func spawn() async -> String? {
        if spawning { return currentOrLast() }
        spawning = true
        error = nil
        defer { spawning = false }
        do {
            let id = try await client.spawnShell()
            if !tabs.contains(id) { tabs.append(id) }
            currentId = id
            return id
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func remove(_ id: String) {
        tabs.removeAll { $0 == id }
        if currentId == id { currentId = tabs.last }
    }
}
