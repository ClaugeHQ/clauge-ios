import SwiftUI

struct TerminalView: View {
    let terminalId: String
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TerminalViewModel

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
                Button {
                    Task {
                        await vm.end()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onDisappear { vm.detach() }
    }
}
