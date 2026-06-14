import SwiftUI

/// Navigation for the paired app: Devices (root) → Home → Terminal, plus a
/// pushed Settings. Path-based so a push tap can deep-link straight to a
/// terminal.
@MainActor
final class Router: ObservableObject {
    enum Route: Hashable {
        case home
        case terminal(String)
        case settings
    }

    @Published var path: [Route] = []

    func reset() { path = [] }
    func push(_ route: Route) { path.append(route) }
    func openTerminal(_ terminalId: String) { path = [.home, .terminal(terminalId)] }
}
