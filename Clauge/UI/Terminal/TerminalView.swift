import SwiftUI

struct TerminalView: View {
    let terminalId: String
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TerminalViewModel
    @ObservedObject private var terminals = TerminalsViewModel.shared

    init(terminalId: String) {
        self.terminalId = terminalId
        _vm = StateObject(wrappedValue: TerminalViewModel(terminalId: terminalId))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                TerminalWebView(bridge: vm.bridge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                KeyBar(vm: vm)
            }
            .onChange(of: geo.size.width) { _ in vm.refit() }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    vm.detach()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // The shell switcher (▾ list / New Terminal) belongs only to the
                // generic Terminal tab's shells. Agent/SSH sessions aren't tracked
                // in TerminalsViewModel.tabs, so they get a plain close instead.
                if terminals.tabs.contains(terminalId) {
                    Menu {
                        ForEach(Array(terminals.tabs.enumerated()), id: \.element) { index, id in
                            Button {
                                switchTo(id)
                            } label: {
                                Label(
                                    "Shell \(index + 1)" + (id == terminalId ? "  •" : ""),
                                    systemImage: "terminal"
                                )
                            }
                        }
                        Divider()
                        Button {
                            newTerminal()
                        } label: {
                            Label("New Terminal", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            closeCurrent()
                        } label: {
                            Label("Close this terminal", systemImage: "xmark")
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                } else {
                    Button {
                        Task { await vm.end(); dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .onDisappear { vm.detach() }
    }

    private func replaceTop(with id: String) {
        guard !router.path.isEmpty else { return }
        router.path[router.path.count - 1] = .terminal(id)
    }

    private func switchTo(_ id: String) {
        guard id != terminalId else { return }
        vm.detach()
        terminals.setCurrent(id)
        replaceTop(with: id)
    }

    private func newTerminal() {
        vm.detach()
        Task {
            if let id = await terminals.spawn() {
                replaceTop(with: id)
            }
        }
    }

    private func closeCurrent() {
        Task {
            await vm.end()
            terminals.remove(terminalId)
            if let next = terminals.currentOrLast() {
                terminals.setCurrent(next)
                replaceTop(with: next)
            } else {
                dismiss()
            }
        }
    }
}
