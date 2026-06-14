import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ServerStore
    @StateObject private var vm = SettingsViewModel()

    @State private var nameDraft = ""
    @State private var showPair = false
    @State private var pairBaselineActive: String?
    @State private var confirmDisconnect = false

    private let remoteGuideURL = URL(string: "https://clauge.in/docs.html#mobile")!

    private var serverName: String { store.activeDevice?.name ?? "Clauge desktop" }
    private var hostLine: String {
        guard let d = store.activeDevice, let host = d.hosts.first else { return "Not connected" }
        return "\(host):\(d.port)"
    }

    var body: some View {
        List {
            connection
            device
            remoteAccess
            about
            actions
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .onAppear { nameDraft = store.deviceName; Task { await vm.check() } }
        .sheet(isPresented: $showPair) {
            NavigationStack { WelcomeView() }.tint(Theme.pink)
        }
        .onChange(of: store.activeDeviceId) { newValue in
            if showPair && newValue != pairBaselineActive { showPair = false }
        }
        .confirmationDialog("Disconnect?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the pairing with \(serverName). You'll need to pair again to reconnect.")
        }
    }

    // MARK: Sections

    private var connection: some View {
        Section("CONNECTION") {
            VStack(alignment: .leading, spacing: 4) {
                Text(serverName).foregroundStyle(Theme.textPrimary)
                Text(hostLine).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Button { Task { await vm.check() } } label: {
                HStack {
                    Text("Status")
                    Spacer()
                    statusPill
                }
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .listRowBackground(Theme.surface)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch vm.status {
            case .checking: return ("Checking…", Theme.deviceChecking)
            case .online: return ("Online", Theme.statusRunning)
            case .offline: return ("Offline", Theme.statusExited)
            }
        }()
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

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

    private var actions: some View {
        Section {
            Button("Pair new device") {
                pairBaselineActive = store.activeDeviceId
                showPair = true
            }
            .foregroundStyle(Theme.pink)

            Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                .foregroundStyle(Theme.error)
        }
        .listRowBackground(Theme.surface)
    }
}
