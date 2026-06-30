import Foundation
import SwiftUI

@MainActor
final class PairViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case waitingApproval
        case error(String)
    }

    @Published var phase: Phase = .idle

    private let client = Services.shared.client
    private let store = Services.shared.store

    var isBusy: Bool { phase == .waitingApproval }

    enum QRDecode {
        case ok(QrPayload)
        case invalid(String)
    }

    /// Decode a scanned QR string into a pairing payload, validating version.
    func decodeQR(_ raw: String) -> QRDecode {
        guard let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QrPayload.self, from: data) else {
            return .invalid("Not a Clauge pairing QR code")
        }
        guard payload.v == 1 else { return .invalid("Unsupported QR version \(payload.v)") }
        return .ok(payload)
    }

    func pair(hosts: [String], port: Int, code: String, nameOverride: String? = nil) async {
        // Offline review demo: the `DEMO` code (manual or QR) short-circuits
        // before any network call and lands on the device list with a canned
        // desktop. Any other code pairs for real, unchanged.
        if code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DEMO" {
            store.enterDemoMode()
            return
        }
        phase = .waitingApproval
        do {
            let resp = try await client.pair(
                hosts: hosts, port: port, code: code, deviceName: store.deviceName
            )
            let name = (nameOverride?.isEmpty == false) ? nameOverride! : resp.serverName
            store.addOrMergeDevice(name: name, hosts: hosts, port: port, token: resp.deviceToken)
            PushManager.requestAuthorizationIfEnabled()
            PushManager.syncTokenToDesktop()
            // isPaired flips → RootView swaps to the paired stack.
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .error(msg)
        }
    }
}
