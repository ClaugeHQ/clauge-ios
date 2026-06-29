import SwiftUI

/// The active device's cockpit: a header showing the device + live status, a
/// five-item bottom bar, and the selected tab's content. Agent and SSH reuse the
/// shared `HomeContent`; Files renders inline. Terminal and Browser are launched
/// screens (pushed routes), so tapping them leaves the selected content tab as-is
/// — back returns to whatever tab you were on.
struct CockpitView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var router: Router
    @StateObject private var home = HomeViewModel()

    @State private var tab: CockpitTab = .agent

    private var deviceName: String { store.activeDevice?.name ?? "Clauge desktop" }

    /// Red when unreachable, green once a fetch succeeds, grey while first loading.
    private var dotColor: Color {
        if home.offline { return Theme.statusExited }
        if home.loaded { return Theme.statusRunning }
        return Theme.statusIdle
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CockpitBottomBar(selected: tab, onSelect: select)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(deviceName).font(.headline).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .onAppear { home.start() }
        .onDisappear { home.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .agent: HomeContent(vm: home, section: .agent)
        case .ssh: HomeContent(vm: home, section: .ssh)
        case .files: FilesView()
        case .terminal, .browser: Color.clear // launched as full screens, not content tabs
        }
    }

    private func select(_ t: CockpitTab) {
        switch t {
        case .terminal: openTerminal()
        case .browser: router.push(.browser)
        default: tab = t
        }
    }

    private func openTerminal() {
        Task {
            if let id = await TerminalsViewModel.shared.openCurrentOrSpawn() {
                router.push(.terminal(id))
            }
        }
    }
}

enum CockpitTab: CaseIterable {
    case agent, ssh, files, terminal, browser

    var label: String {
        switch self {
        case .agent: return "Agent"
        case .ssh: return "SSH"
        case .files: return "Files"
        case .terminal: return "Terminal"
        case .browser: return "Browser"
        }
    }

    var icon: String {
        switch self {
        case .agent: return "sparkles"
        case .ssh: return "server.rack"
        case .files: return "folder"
        case .terminal: return "terminal"
        case .browser: return "globe"
        }
    }
}

/// Each item is an equal-width slot with the selected pill centered inside it,
/// so the indicator never clips at the screen edges.
private struct CockpitBottomBar: View {
    let selected: CockpitTab
    let onSelect: (CockpitTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.outlineVariant)
                .frame(height: 1)
            HStack(spacing: 2) {
                ForEach(CockpitTab.allCases, id: \.self) { t in
                    item(t)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
    }

    private func item(_ t: CockpitTab) -> some View {
        let sel = t == selected
        return VStack(spacing: 4) {
            Image(systemName: t.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(sel ? Theme.background : Theme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
                .background(sel ? Theme.pink : Color.clear, in: Capsule())
            Text(t.label)
                .font(.caption2)
                .foregroundStyle(sel ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(t) }
    }
}
