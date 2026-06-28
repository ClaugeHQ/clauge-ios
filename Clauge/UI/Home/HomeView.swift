import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ServerStore
    @StateObject private var vm = HomeViewModel()

    private var serverName: String { store.activeDevice?.name ?? "Clauge desktop" }

    /// Red when the desktop is unreachable, green once a fetch succeeds, grey while first loading.
    private var onlineColor: Color {
        if vm.offline { return Theme.statusExited }
        if vm.loaded { return Theme.statusRunning }
        return Theme.statusIdle
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("", selection: $vm.tab) {
                    Text("Agent").tag(HomeViewModel.Tab.agent)
                    Text("SSH").tag(HomeViewModel.Tab.ssh)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                HomeContent(vm: vm, section: vm.tab)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle().fill(onlineColor).frame(width: 8, height: 8)
                    Text(serverName).font(.headline).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

/// The Agent or SSH session list for the active device, without app chrome —
/// the host (Home screen or Cockpit) owns the header and navigation. A pure
/// body so it can be dropped into any cockpit tab.
struct HomeContent: View {
    @ObservedObject var vm: HomeViewModel
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var router: Router
    let section: HomeViewModel.Tab

    private var serverName: String { store.activeDevice?.name ?? "Clauge desktop" }

    var body: some View {
        ZStack {
            content
            if let title = vm.spawningTitle { spawnOverlay(title) }
            if let toast = vm.toast { toastView(toast) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.offline {
            emptyState(
                title: "Can't reach \(serverName)",
                detail: "Make sure Clauge desktop is running on the same network."
            )
        } else if section == .agent {
            agentList
        } else {
            sshList
        }
    }

    // MARK: Agent

    @ViewBuilder
    private var agentList: some View {
        if vm.loaded && vm.agents.isEmpty {
            emptyState(title: "No active sessions on this device",
                       detail: "Start one on your desktop — it'll show up here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.agentGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.label)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 4)
                            VStack(spacing: 10) {
                                ForEach(group.sessions) { session in
                                    AgentRow(session: session)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                                        .contentShape(Rectangle())
                                        .onTapGesture { openAgent(session) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable { await vm.refresh() }
        }
    }

    // MARK: SSH

    @ViewBuilder
    private var sshList: some View {
        if vm.loaded && vm.ssh.isEmpty {
            emptyState(title: "No SSH profiles on this device",
                       detail: "Add one on your desktop to connect from here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.ssh) { profile in
                        SshRow(profile: profile)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { openSsh(profile) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable { await vm.refresh() }
        }
    }

    // MARK: Actions

    private func openAgent(_ session: AgentSessionDto) {
        vm.openAgent(session) { id in router.push(.terminal(id)) }
    }

    private func openSsh(_ profile: SshProfileDto) {
        vm.openSsh(profile) { id in router.push(.terminal(id)) }
    }

    // MARK: Pieces

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spawnOverlay(_ title: String) -> some View {
        ZStack {
            Color(hex: "#060414").opacity(0.85).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Theme.pink)
                Text("Starting \(title)…").foregroundStyle(Theme.textPrimary)
                Text("Make sure the desktop app is open")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Cancel") { vm.cancelSpawn() }
                    .foregroundStyle(Theme.pink)
                    .padding(.top, 6)
            }
        }
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.onErrorContainer)
                .padding(12)
                .background(Theme.errorContainer, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            vm.toast = nil
        }
    }
}

// MARK: - Rows

private struct AgentRow: View {
    let session: AgentSessionDto

    private var awaiting: Bool { session.awaitingInput == true }

    var body: some View {
        HStack(spacing: 12) {
            ProviderBadge(provider: session.provider)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.headline).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    if let purpose = session.purpose, !purpose.isEmpty {
                        PurposePill(purpose: purpose)
                    }
                    if let rel = RelativeTime.format(session.lastUsedAt) {
                        Text(rel).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            StatusDot(color: awaiting ? Theme.statusAwaiting : Theme.statusColor(session.status),
                      pulsing: awaiting)
        }
        .padding(.vertical, 6)
    }
}

private struct SshRow: View {
    let profile: SshProfileDto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text("\(profile.username)@\(profile.host)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if profile.live {
                Text("live")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.statusRunning)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.statusRunning.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 6)
    }

    private var accent: Color {
        if let hex = profile.accentColor, !hex.isEmpty { return Color(hex: hex) }
        return Theme.violet
    }
}

private struct ProviderBadge: View {
    let provider: String

    private var letter: String {
        String((provider.first ?? "C")).uppercased()
    }

    var body: some View {
        Text(letter)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onPinkContainer)
            .frame(width: 28, height: 28)
            .background(Theme.pinkContainer, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PurposePill: View {
    let purpose: String
    var body: some View {
        let c = Theme.purposeColor(purpose)
        Text(purpose)
            .font(.caption2)
            .foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(c.opacity(0.13), in: Capsule())
    }
}
