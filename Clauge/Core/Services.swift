import Foundation

/// Process-wide service container. Built once and shared between the SwiftUI
/// app and the UIKit `AppDelegate` (which handles push). Everything here is
/// main-actor isolated.
@MainActor
final class Services {
    static let shared = Services()

    let store: ServerStore
    let client: CompanionClient
    let push: PushCoordinator

    private init() {
        let store = ServerStore()
        let client = CompanionClient(store: store)
        client.onUnauthorized = { [weak store] in store?.clearActiveDevice() }
        self.store = store
        self.client = client
        self.push = PushCoordinator()
    }
}

/// Bridges push taps (handled in the UIKit delegate) into SwiftUI navigation.
@MainActor
final class PushCoordinator: ObservableObject {
    /// A terminal the user asked to open by tapping a notification.
    @Published var pendingDeepLink: DeepLink?

    func deliver(_ link: DeepLink) { pendingDeepLink = link }
    func consume() -> DeepLink? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }
}
