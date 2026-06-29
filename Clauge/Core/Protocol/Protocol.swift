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
    /// Phone-generated id so the open can be cancelled before it resolves.
    var requestId: String? = nil
}

struct SpawnSshRequest: Codable {
    let profileId: String
    var requestId: String? = nil
}

struct CancelOpenRequest: Codable {
    let requestId: String
}

struct SpawnResponse: Codable {
    let terminalId: String
}

// MARK: - System metrics (GET /v1/sys/metrics)

struct SysMetricsDto: Codable {
    let serverName: String
    let platform: String
    let uptimeSecs: Int
    let cpu: CpuDto
    let memory: MemoryDto
    let battery: BatteryDto?
    let volumes: [VolumeDto]

    enum CodingKeys: String, CodingKey {
        case serverName, platform, uptimeSecs, cpu, memory, battery, volumes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverName = try c.decodeIfPresent(String.self, forKey: .serverName) ?? ""
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        uptimeSecs = try c.decodeIfPresent(Int.self, forKey: .uptimeSecs) ?? 0
        cpu = try c.decode(CpuDto.self, forKey: .cpu)
        memory = try c.decode(MemoryDto.self, forKey: .memory)
        battery = try c.decodeIfPresent(BatteryDto.self, forKey: .battery)
        volumes = try c.decodeIfPresent([VolumeDto].self, forKey: .volumes) ?? []
    }
}

struct CpuDto: Codable {
    let usagePct: Double
    let brand: String
    let cores: Int
}

struct MemoryDto: Codable {
    let totalBytes: Int
    let usedBytes: Int
    let availableBytes: Int
}

struct BatteryDto: Codable {
    let percent: Int
    let charging: Bool
}

struct VolumeDto: Codable, Identifiable {
    let name: String
    let mountPoint: String
    let totalBytes: Int
    let usedBytes: Int
    let availableBytes: Int
    var id: String { mountPoint }
}

// MARK: - Files (/v1/fs/*)

struct FsEntryDto: Codable, Identifiable, Equatable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int
    var id: String { path }

    enum CodingKeys: String, CodingKey { case name, path, isDir, size }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try c.decode(String.self, forKey: .path)
        isDir = try c.decodeIfPresent(Bool.self, forKey: .isDir) ?? false
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
    }
}

struct FsListDto: Codable {
    let path: String
    let parent: String?
    let entries: [FsEntryDto]

    enum CodingKeys: String, CodingKey { case path, parent, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        entries = try c.decodeIfPresent([FsEntryDto].self, forKey: .entries) ?? []
    }
}

struct FsReadDto: Codable {
    let path: String
    let binary: Bool
    let tooLarge: Bool
    let content: String?
    let size: Int?

    enum CodingKeys: String, CodingKey { case path, binary, tooLarge, content, size }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        binary = try c.decodeIfPresent(Bool.self, forKey: .binary) ?? false
        tooLarge = try c.decodeIfPresent(Bool.self, forKey: .tooLarge) ?? false
        content = try c.decodeIfPresent(String.self, forKey: .content)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
    }
}

struct FsSearchDto: Codable {
    let entries: [FsEntryDto]

    enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([FsEntryDto].self, forKey: .entries) ?? []
    }
}

struct FsPathBody: Codable { let path: String }
struct FsWriteBody: Codable { let path: String; let content: String }

// MARK: - Ports (/v1/ports)

struct PortInfoDto: Codable, Identifiable, Equatable {
    let port: Int
    let bindAddr: String
    let pid: Int?
    let process: String?
    var id: String { "\(port)-\(bindAddr)" }

    enum CodingKeys: String, CodingKey { case port, bindAddr, pid, process }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.decode(Int.self, forKey: .port)
        bindAddr = try c.decode(String.self, forKey: .bindAddr)
        pid = try c.decodeIfPresent(Int.self, forKey: .pid)
        process = try c.decodeIfPresent(String.self, forKey: .process)
    }
}

struct PortsDto: Codable {
    let ports: [PortInfoDto]

    enum CodingKeys: String, CodingKey { case ports }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ports = try c.decodeIfPresent([PortInfoDto].self, forKey: .ports) ?? []
    }
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
