import Foundation
import SwiftUI

/// Manages persistence of saved SSH connections
@MainActor
class ConnectionStore: ObservableObject {
    @Published var connections: [SavedConnection] = []

    private let storageKey = "savedConnections"

    init() {
        load()
    }

    // MARK: - CRUD Operations

    func add(_ connection: SavedConnection) {
        connections.append(connection)
        save()
    }

    func update(_ connection: SavedConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            save()
        }
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        // Also remove credentials from Keychain
        try? KeychainHelper.deleteCredentials(for: connection.id)
        save()
    }

    func delete(at offsets: IndexSet) {
        let connectionsToDelete = offsets.map { connections[$0] }
        for connection in connectionsToDelete {
            try? KeychainHelper.deleteCredentials(for: connection.id)
        }
        connections.remove(atOffsets: offsets)
        save()
    }

    func updateLastConnected(_ connection: SavedConnection) {
        var updated = connection
        updated.lastConnected = Date()
        update(updated)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(connections)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        do {
            connections = try JSONDecoder().decode([SavedConnection].self, from: data)
        } catch {
            print("Failed to load connections: \(error)")
        }
    }
}
