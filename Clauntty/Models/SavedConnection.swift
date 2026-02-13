import Foundation

/// Transport type for a connection (how bytes flow to/from the remote terminal).
enum ConnectionTransport: String, Codable, Hashable, CaseIterable {
    case ssh
    case mosh

    var displayName: String {
        switch self {
        case .ssh: return "SSH"
        case .mosh: return "Mosh"
        }
    }
}

/// Represents a saved SSH connection configuration
struct SavedConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var lastConnected: Date?
    var transport: ConnectionTransport

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod,
        lastConnected: Date? = nil,
        transport: ConnectionTransport = .ssh
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.lastConnected = lastConnected
        self.transport = transport
    }

    /// Display name - uses custom name or falls back to user@host
    var displayName: String {
        name.isEmpty ? "\(username)@\(host)" : name
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case authMethod
        case lastConnected
        case transport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        authMethod = try container.decode(AuthMethod.self, forKey: .authMethod)
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        transport = try container.decodeIfPresent(ConnectionTransport.self, forKey: .transport) ?? .ssh
    }
}

/// Authentication method for SSH connections
enum AuthMethod: Codable, Hashable {
    case password
    case sshKey(keyId: String)

    var displayName: String {
        switch self {
        case .password:
            return "Password"
        case .sshKey:
            return "SSH Key"
        }
    }
}
