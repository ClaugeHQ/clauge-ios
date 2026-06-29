import SwiftUI

/// Navigation for the paired app: Devices (root) → Home → Terminal, plus a
/// pushed Settings. Path-based so a push tap can deep-link straight to a
/// terminal.
@MainActor
final class Router: ObservableObject {
    enum Route: Hashable {
        case home
        case cockpit
        case deviceInfo
        case browser
        case terminal(String)
        case settings
    }

    @Published var path: [Route] = []

    func reset() { path = [] }
    func push(_ route: Route) { path.append(route) }
    func openCockpit() { push(.cockpit) }
    func openDeviceInfo() { push(.deviceInfo) }
    func openBrowser() { push(.browser) }
    func openTerminal(_ terminalId: String) { path = [.cockpit, .terminal(terminalId)] }
}
