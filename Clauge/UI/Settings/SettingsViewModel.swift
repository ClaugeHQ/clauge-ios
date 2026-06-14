import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    enum Status { case checking, online, offline }

    @Published var status: Status = .checking

    private let client = Services.shared.client

    func check() async {
        status = .checking
        status = await client.healthz() ? .online : .offline
    }
}
