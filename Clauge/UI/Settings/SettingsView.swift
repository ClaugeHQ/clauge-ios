import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ServerStore
    @State private var nameDraft = ""

    private let remoteGuideURL = URL(string: "https://clauge.in/docs.html#mobile")!

    var body: some View {
        List {
            device
            remoteAccess
            about
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .onAppear { nameDraft = store.deviceName }
    }

    // MARK: Sections

    private var device: some View {
        Section("DEVICE") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How this phone appears on your desktop")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                HStack {
                    TextField("Device name", text: $nameDraft)
                        .foregroundStyle(Theme.textPrimary)
                    if nameDraft != store.deviceName && !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Save") { store.deviceName = nameDraft.trimmingCharacters(in: .whitespaces) }
                            .foregroundStyle(Theme.pink)
                    }
                }
            }
            Toggle(isOn: $store.notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push notifications").foregroundStyle(Theme.textPrimary)
                    Text("Alerts when a session exits or needs attention")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.pink)
            .onChange(of: store.notificationsEnabled) { enabled in
                if enabled {
                    PushManager.requestAuthorizationIfEnabled()
                    PushManager.syncTokenToDesktop()
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var remoteAccess: some View {
        Section("REMOTE ACCESS") {
            Link(destination: remoteGuideURL) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote access guide").foregroundStyle(Theme.textPrimary)
                    Text("Reach your desktop from a different network")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var about: some View {
        Section("ABOUT") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version").foregroundStyle(Theme.textPrimary)
                    Text("Clauge for iOS").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(AppInfo.version).foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surface)
    }
}
