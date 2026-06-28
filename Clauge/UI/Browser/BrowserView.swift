import SwiftUI

struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = BrowserViewModel()
    @StateObject private var webController = WebController()

    @State private var editing = false
    @State private var field = ""
    @State private var proxyToken: String?
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Divider().background(Theme.outlineVariant)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomChrome
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            proxyToken = await vm.authToken()
            vm.onAppear()
        }
        .onChange(of: currentWebUrl) { _ in
            loading = false
            loadError = nil
        }
    }

    private var currentWebUrl: String {
        if case .web(let u, _) = vm.view { return u }
        return ""
    }

    private var consoleEnabled: Bool {
        if case .web(_, let proxy) = vm.view { return proxy }
        return false
    }

    // MARK: Address bar

    private var addressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundColor(Theme.pink)
                .font(.system(size: 18))
            if editing {
                TextField("URL or port number", text: $field)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceHigh)
                    .clipShape(Capsule())
                    .onSubmit { submitField() }
            } else {
                Button {
                    field = currentWebUrl
                    editing = true
                } label: {
                    Text(vm.title)
                        .lineLimit(1)
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceHigh)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func submitField() {
        let t = field.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        if !t.isEmpty { vm.submit(t) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch vm.view {
        case .home:
            homeContent
        case .ports:
            portsContent
        case .web(let url, let isProxy):
            webContent(url: url, isProxy: isProxy)
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    vm.goPorts()
                } label: {
                    HStack {
                        Image(systemName: "powerplug")
                            .foregroundColor(Theme.pink)
                        Text("Ports")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(16)
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !vm.recents.isEmpty {
                    Text("RECENT")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(vm.recents) { r in
                            Button {
                                vm.submit(r.url)
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(Theme.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title)
                                            .foregroundColor(Theme.textPrimary)
                                            .lineLimit(1)
                                        Text(r.url)
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.vertical, 10)
                            }
                            Divider().background(Theme.outlineVariant)
                        }
                    }
                }

                Text("TIPS")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type a port number (e.g. 3000) to open a local dev server through the desktop proxy.")
                    Text("Type a domain to browse the web.")
                    Text("The console is available on proxied localhost pages.")
                }
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            }
            .padding(16)
        }
    }

    private var portsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open ports")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    vm.refreshPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            TextField("port, process…", text: $vm.portQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .foregroundColor(Theme.textPrimary)
                .padding(10)
                .background(Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", selected: vm.processFilter == nil) {
                        vm.processFilter = nil
                    }
                    ForEach(processes, id: \.self) { p in
                        filterChip(label: p, selected: vm.processFilter == p) {
                            vm.processFilter = p
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider().background(Theme.outlineVariant).padding(.top, 4)

            portsList
        }
    }

    @ViewBuilder private var portsList: some View {
        if filteredPorts.isEmpty {
            // #7: portsError takes priority over the empty state.
            VStack(spacing: 12) {
                if let err = vm.portsError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Theme.error)
                    Text(err)
                        .foregroundColor(Theme.error)
                        .multilineTextAlignment(.center)
                } else if vm.portsLoading {
                    ProgressView().tint(Theme.pink)
                } else {
                    Text("No open ports")
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            List {
                ForEach(groupedProcesses, id: \.self) { proc in
                    Section(header: Text(proc).foregroundColor(Theme.textSecondary)) {
                        ForEach(portsByProcess[proc] ?? []) { port in
                            Button {
                                vm.openPort(port.port)
                            } label: {
                                HStack {
                                    Text("\(port.port)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(Theme.pink)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(port.process ?? "unknown")
                                            .foregroundColor(Theme.textPrimary)
                                        Text(port.bindAddr)
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.pinkContainer : Theme.surfaceHigh)
                .foregroundColor(selected ? Theme.onPinkContainer : Theme.textPrimary)
                .clipShape(Capsule())
        }
    }

    private var processes: [String] {
        Array(Set(vm.ports.compactMap { $0.process })).sorted()
    }

    private var filteredPorts: [PortInfoDto] {
        vm.ports.filter { p in
            let matchesProcess = vm.processFilter == nil || p.process == vm.processFilter
            let q = vm.portQuery.trimmingCharacters(in: .whitespaces)
            let matchesQuery = q.isEmpty
                || "\(p.port)".contains(q)
                || (p.process ?? "").localizedCaseInsensitiveContains(q)
            return matchesProcess && matchesQuery
        }
    }

    private var portsByProcess: [String: [PortInfoDto]] {
        Dictionary(grouping: filteredPorts) { $0.process ?? "unknown" }
    }

    private var groupedProcesses: [String] {
        portsByProcess.keys.sorted()
    }

    private func webContent(url: String, isProxy: Bool) -> some View {
        ZStack(alignment: .top) {
            BrowserWebView(
                url: url,
                isProxy: isProxy,
                token: proxyToken,
                consoleOpen: vm.consoleOpen,
                controller: webController,
                onNav: { back, fwd in vm.setNav(back: back, forward: fwd) },
                onTitle: { vm.setPageTitle($0) },
                onLoading: { loading = $0 },
                onError: { loadError = $0 }
            )
            .id(url)

            if loading {
                ProgressView()
                    .tint(Theme.pink)
                    .padding(.top, 8)
            }

            if isProxy && (proxyToken?.isEmpty ?? true) {
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.pink)
                    Text("Connecting…")
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            }

            if let err = loadError {
                VStack(spacing: 12) {
                    Text(err)
                        .foregroundColor(Theme.textPrimary)
                    Text(url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadError = nil
                        webController.reload()
                    }
                    .foregroundColor(Theme.pink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(Theme.background)
            }
        }
    }

    // MARK: Bottom chrome

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.outlineVariant)
            HStack {
                Spacer()
                chromeButton(system: "chevron.backward", enabled: true) { handleBack() }
                Spacer()
                chromeButton(system: "chevron.forward", enabled: vm.canGoForward) {
                    webController.goForward()
                }
                Spacer()
                chromeButton(system: "house", tint: isHome ? Theme.pink : Theme.textPrimary, enabled: true) {
                    vm.goHome()
                }
                Spacer()
                chromeButton(system: "arrow.clockwise", enabled: true) { reload() }
                Spacer()
                chromeButton(
                    system: "terminal",
                    tint: vm.consoleOpen ? Theme.pink : Theme.textPrimary,
                    enabled: consoleEnabled
                ) {
                    vm.toggleConsole()
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var isHome: Bool {
        if case .home = vm.view { return true }
        return false
    }

    private func chromeButton(system: String, tint: Color = Theme.textPrimary, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20))
                .foregroundColor(enabled ? tint : Theme.textSecondary.opacity(0.4))
        }
        .disabled(!enabled)
    }

    private func handleBack() {
        if case .web = vm.view, webController.canGoBack {
            webController.goBack()
            return
        }
        switch vm.view {
        case .home: dismiss()
        default: vm.goHome()
        }
    }

    private func reload() {
        switch vm.view {
        case .web: webController.reload()
        case .ports: vm.refreshPorts()
        case .home: break
        }
    }
}
