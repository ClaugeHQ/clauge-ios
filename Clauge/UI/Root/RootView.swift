import SwiftUI

/// Top-level phase switch: onboarding → pairing → paired app. Also routes
/// notification-tap deep links to the right terminal once paired.
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
        } else if !store.isPaired {
            NavigationStack { WelcomeView() }
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
