import SwiftUI
import AVFoundation
import VisionKit

struct ScanView: View {
    @StateObject private var vm = PairViewModel()
    @State private var camStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var didScan = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch camStatus {
            case .authorized:
                scanner
            case .notDetermined:
                Color.clear.onAppear {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            camStatus = granted ? .authorized : .denied
                        }
                    }
                }
            default:
                permissionDenied
            }

            if vm.isBusy { approvalOverlay }
        }
        .navigationTitle("Scan QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .alert("Pairing failed", isPresented: errorBinding) {
            Button("OK") { vm.phase = .idle; didScan = false }
        } message: {
            if case let .error(msg) = vm.phase { Text(msg) }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack {
                QRScannerRepresentable { code in onScan(code) }
                    .ignoresSafeArea(edges: .bottom)
                VStack {
                    Spacer()
                    Text("Point your camera at the QR code in Clauge desktop → Settings → Mobile.")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
        } else {
            VStack(spacing: 8) {
                Text("Scanning isn't available on this device.")
                    .foregroundStyle(Theme.textPrimary)
                Text("Enter the host, port, and code manually instead.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding()
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(Theme.textSecondary)
            Text("Clauge needs camera access to scan a pairing QR code.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 32)
            Button("Allow camera") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.headline)
            .foregroundStyle(Theme.pink)
        }
    }

    private var approvalOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(Theme.pink)
                Text("Approve on your desktop…").foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = vm.phase { return true } else { return false } },
                set: { if !$0 { vm.phase = .idle } })
    }

    private func onScan(_ code: String) {
        guard !didScan, !vm.isBusy else { return }
        switch vm.decodeQR(code) {
        case .success(let payload):
            didScan = true
            Task { await vm.pair(hosts: payload.hosts, port: payload.port, code: payload.code) }
        case .failure(let message):
            vm.phase = .error(message)
        }
    }
}

/// Wraps VisionKit's barcode scanner, reporting the first QR payload string.
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var fired = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let value = barcode.payloadStringValue {
                    fired = true
                    onFound(value)
                    return
                }
            }
        }
    }
}
