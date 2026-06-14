import Foundation

// Wire models shared with the Clauge desktop companion server. Field names
// match the desktop JSON exactly. The server omits null/default fields
// (explicitNulls=false), so optional fields tolerate absence.

// MARK: - Pairing

struct PairRequest: Codable {
    let code: String
    let deviceName: String
    let platform: String // "ios"
}

struct PairResponse: Codable {
    let deviceToken: String
    let deviceId: String
    let serverName: String
}

/// Payload encoded in the desktop's pairing QR code.
struct QrPayload: Codable {
    let v: Int
    let hosts: [String]
    let port: Int
    let code: String
}

// MARK: - Sessions

struct AgentSessionDto: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let provider: String
    let status: String
    let projectPath: String
    let lastUsedAt: String?
    let purpose: String?
    let liveTerminalId: String?
    let awaitingInput: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, provider, status, projectPath, lastUsedAt, purpose, liveTerminalId, awaitingInput
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Terminal"
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "claude"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        liveTerminalId = try c.decodeIfPresent(String.self, forKey: .liveTerminalId)
        awaitingInput = try c.decodeIfPresent(Bool.self, forKey: .awaitingInput)
    }
}

struct LiveSshTerminalDto: Codable, Equatable {
    let terminalId: String
    let label: String?
}

struct SshProfileDto: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let username: String
    let accentColor: String?
    let lastUsedAt: String?
    let connected: Bool
    let live: Bool
    let liveTerminals: [LiveSshTerminalDto]

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, accentColor, lastUsedAt, connected, live, liveTerminals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? false
        liveTerminals = try c.decodeIfPresent([LiveSshTerminalDto].self, forKey: .liveTerminals) ?? []
    }
}

// MARK: - Spawn

struct NewSessionSpec: Codable {
    let projectPath: String
    let provider: String
    let title: String?
}

struct SpawnAgentRequest: Codable {
    let sessionId: String?
    let newSession: NewSessionSpec?
}

struct SpawnSshRequest: Codable {
    let profileId: String
}

struct SpawnResponse: Codable {
    let terminalId: String
}

// MARK: - Misc

struct ServerInfoDto: Codable {
    let serverName: String
    let version: String?
}

struct FcmTokenRequest: Codable {
    let token: String
}

struct ApiErrorBody: Codable {
    let error: String?
}

// MARK: - Local persistence models

struct Device: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var hosts: [String]
    var port: Int
    var addedAt: Double
}

/// A pending navigation target produced by tapping a push notification.
struct DeepLink: Equatable {
    let terminalId: String
    let serverName: String?
}
