import SwiftUI

struct ManualPairView: View {
    @StateObject private var vm = PairViewModel()
    @State private var name = ""
    @State private var host = ""
    @State private var portText = "\(ServerStore.defaultPort)"
    @State private var code = ""

    private var port: Int? { Int(portText).flatMap { (1...65535).contains($0) ? $0 : nil } }
    private var isDemoCode: Bool {
        code.trimmingCharacters(in: .whitespaces).uppercased() == "DEMO"
    }
    private var canSubmit: Bool {
        if vm.isBusy { return false }
        if isDemoCode { return true }
        return !host.trimmingCharacters(in: .whitespaces).isEmpty && port != nil
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    field("NAME", text: $name, placeholder: "Optional", keyboard: .default)
                    field("HOST", text: $host, placeholder: "192.168.1.10", keyboard: .URL)
                    field("PORT", text: $portText, placeholder: "7431", keyboard: .numberPad)
                    field("CODE", text: $code, placeholder: "6-digit code", keyboard: .asciiCapable)

                    Button(action: submit) {
                        Text("Pair")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(canSubmit ? Theme.pink : Theme.surfaceHigh,
                               in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(canSubmit ? Theme.background : Theme.textSecondary)
                    .disabled(!canSubmit)
                    .padding(.top, 16)
                }
                .padding(20)
            }

            if vm.isBusy {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().tint(Theme.pink)
                        Text("Approve on your desktop…").foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        .navigationTitle("Enter manually")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .alert("Pairing failed", isPresented: errorBinding) {
            Button("OK") { vm.phase = .idle }
        } message: {
            if case let .error(msg) = vm.phase { Text(msg) }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.outlineVariant, lineWidth: 1))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = vm.phase { return true } else { return false } },
                set: { if !$0 { vm.phase = .idle } })
    }

    private func submit() {
        let c = code.trimmingCharacters(in: .whitespaces)
        let n = name.trimmingCharacters(in: .whitespaces)
        if isDemoCode {
            Task { await vm.pair(hosts: [], port: ServerStore.defaultPort, code: c,
                                 nameOverride: n.isEmpty ? nil : n) }
            return
        }
        guard let port else { return }
        let h = host.trimmingCharacters(in: .whitespaces)
        Task { await vm.pair(hosts: [h], port: port, code: c, nameOverride: n.isEmpty ? nil : n) }
    }
}
