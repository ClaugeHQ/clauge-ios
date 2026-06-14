import Foundation

/// Errors surfaced by the companion networking layer. Messages mirror the
/// Android client so the UI copy stays identical across platforms.
enum NetError: LocalizedError {
    case notPaired
    case deviceOffline
    case unauthorized
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return "No paired server"
        case .deviceOffline:
            return "Device offline — make sure Clauge desktop is running and reachable"
        case .unauthorized:
            return "Unauthorized"
        case .server(let msg):
            return msg
        case .badResponse:
            return "Unexpected response from the desktop"
        }
    }
}
