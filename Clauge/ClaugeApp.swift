import SwiftUI

@main
struct ClaugeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Services.shared.store
    @StateObject private var push = Services.shared.push

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(push)
                .tint(Theme.pink)
                .preferredColorScheme(.dark)
        }
    }
}
