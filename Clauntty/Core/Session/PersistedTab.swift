import Foundation

/// Persisted tab state for restoring tabs after app restart
/// Stored in UserDefaults, tabs are restored in disconnected state
struct PersistedTab: Codable, Identifiable {
    /// Unique tab identifier (matches Session.id)
    let id: UUID

    /// Reference to the saved connection (for reconnecting)
    let connectionId: UUID

    /// Transport used for the tab (matches SavedConnection.transport at creation time).
    /// Defaults to SSH for backward compatibility.
    let transport: ConnectionTransport

    /// The rtach session ID on the remote server (SSH transport only)
    let rtachSessionId: String?

    /// When the tab was first created
    let createdAt: Date

    /// When the tab was last active
    var lastActiveAt: Date

    /// Cached session title (shown while disconnected)
    var cachedTitle: String?

    /// Cached dynamic title from terminal escape sequences
    var cachedDynamicTitle: String?

    /// Order index for tab ordering
    var orderIndex: Int

    /// Font size for this tab (nil = use global default)
    var fontSize: Float?

    private enum CodingKeys: String, CodingKey {
        case id
        case connectionId
        case transport
        case rtachSessionId
        case createdAt
        case lastActiveAt
        case cachedTitle
        case cachedDynamicTitle
        case orderIndex
        case fontSize
    }

    init(
        id: UUID,
        connectionId: UUID,
        transport: ConnectionTransport,
        rtachSessionId: String?,
        createdAt: Date,
        lastActiveAt: Date,
        cachedTitle: String?,
        cachedDynamicTitle: String?,
        orderIndex: Int,
        fontSize: Float?
    ) {
        self.id = id
        self.connectionId = connectionId
        self.transport = transport
        self.rtachSessionId = rtachSessionId
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.cachedTitle = cachedTitle
        self.cachedDynamicTitle = cachedDynamicTitle
        self.orderIndex = orderIndex
        self.fontSize = fontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        connectionId = try container.decode(UUID.self, forKey: .connectionId)
        transport = try container.decodeIfPresent(ConnectionTransport.self, forKey: .transport) ?? .ssh
        rtachSessionId = try container.decodeIfPresent(String.self, forKey: .rtachSessionId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastActiveAt = try container.decode(Date.self, forKey: .lastActiveAt)
        cachedTitle = try container.decodeIfPresent(String.self, forKey: .cachedTitle)
        cachedDynamicTitle = try container.decodeIfPresent(String.self, forKey: .cachedDynamicTitle)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        fontSize = try container.decodeIfPresent(Float.self, forKey: .fontSize)
    }
}
