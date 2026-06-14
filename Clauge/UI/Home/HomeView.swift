import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var router: Router
    @StateObject private var vm = HomeViewModel()

    private var serverName: String { store.activeDevice?.name ?? "Clauge desktop" }

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

                content
                VersionFooter()
            }

            if let title = vm.spawningTitle { spawnOverlay(title) }
            if let toast = vm.toast { toastView(toast) }
        }
        .navigationTitle(serverName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.offline {
            emptyState(
                title: "Can't reach \(serverName)",
                detail: "Make sure Clauge desktop is running on the same network."
            )
        } else if vm.tab == .agent {
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
            List {
                ForEach(vm.agentGroups) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            AgentRow(session: session)
                                .listRowBackground(Theme.surface)
                                .contentShape(Rectangle())
                                .onTapGesture { openAgent(session) }
                        }
                    } header: {
                        Text(group.label).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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
            List {
                ForEach(vm.ssh) { profile in
                    SshRow(profile: profile)
                        .listRowBackground(Theme.surface)
                        .contentShape(Rectangle())
                        .onTapGesture { openSsh(profile) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.refresh() }
        }
    }

    // MARK: Actions

    private func openAgent(_ session: AgentSessionDto) {
        Task { if let id = await vm.openAgent(session) { router.push(.terminal(id)) } }
    }

    private func openSsh(_ profile: SshProfileDto) {
        Task { if let id = await vm.openSsh(profile) { router.push(.terminal(id)) } }
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
