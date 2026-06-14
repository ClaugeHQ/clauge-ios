import SwiftUI

/// Top-level phase switch: onboarding → device list. The device list is home
/// even with no devices (it shows an empty state); pairing is reached from
/// there. Also routes notification-tap deep links to the right terminal.
struct RootView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var push: PushCoordinator
    @StateObject private var router = Router()

    var body: some View {
        content
            .onAppear { routeDeepLinkIfPossible() }
            .onChange(of: push.pendingDeepLink) { _ in routeDeepLinkIfPossible() }
            .onChange(of: store.isPaired) { _ in routeDeepLinkIfPossible() }
    }

    @ViewBuilder
    private var content: some View {
        if !store.onboarded {
            OnboardingView()
        } else {
            NavigationStack(path: $router.path) {
                DevicesView()
                    .navigationDestination(for: Router.Route.self) { route in
                        switch route {
                        case .home: HomeView()
                        case .terminal(let id): TerminalView(terminalId: id)
                        case .settings: SettingsView()
                        }
                    }
            }
            .environmentObject(router)
        }
    }

    private func routeDeepLinkIfPossible() {
        guard store.isPaired, let link = push.pendingDeepLink else { return }
        if let name = link.serverName, let id = store.deviceId(byName: name) {
            store.setActive(id)
        }
        router.openTerminal(link.terminalId)
        _ = push.consume()
    }
}
