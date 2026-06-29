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
            .onChange(of: store.isPaired) { paired in
                if !paired { popIfDeviceScoped() }
                routeDeepLinkIfPossible()
            }
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
                        case .cockpit: CockpitView()
                        case .deviceInfo: DeviceInfoView()
                        case .browser: BrowserView()
                        // .id(id) forces a fresh view + ViewModel when the shell id
                        // changes (New Terminal / switch), so it doesn't reuse the
                        // previous terminal's screen.
                        case .terminal(let id): TerminalView(terminalId: id).id(id)
                        case .settings: SettingsView()
                        }
                    }
            }
            .environmentObject(router)
        }
    }

    private func routeDeepLinkIfPossible() {
        guard store.isPaired, let link = push.pendingDeepLink else { return }
        if let name = link.serverName {
            guard let id = store.deviceId(byName: name) else {
                // The push named a device we can't resolve. Consume the link
                // without routing rather than opening against the wrong desktop.
                _ = push.consume()
                return
            }
            if id != store.activeDeviceId {
                // The push named a different paired device. Activate it and drop
                // the previous device's cockpit so backing out of the terminal
                // doesn't land on a stale screen scoped to the old device.
                store.setActive(id)
                router.reset()
            }
        }
        router.openTerminal(link.terminalId)
        _ = push.consume()
    }

    /// Lost the active device (disconnect / 401) while inside a device-scoped
    /// screen — fall back to the device list, which shows its empty state.
    /// App-level screens (Settings) work unpaired, so they stay put.
    private func popIfDeviceScoped() {
        switch router.path.last {
        case .cockpit, .browser, .deviceInfo, .terminal:
            router.reset()
        default:
            break
        }
    }
}
