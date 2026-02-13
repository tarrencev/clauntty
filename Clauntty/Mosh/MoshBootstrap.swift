import Foundation

struct MoshBootstrapResult: Sendable, Equatable {
    let udpPort: Int
    let key: String
}

enum MoshBootstrapError: Error, LocalizedError, Equatable {
    case moshServerNotInstalled(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .moshServerNotInstalled(let details):
            if details.isEmpty {
                return "`mosh-server` not found on the remote host."
            }
            return "`mosh-server` not found on the remote host. Details: \(details)"
        case .invalidOutput(let output):
            return "Failed to parse mosh-server output: \(output)"
        }
    }
}

/// Runs `mosh-server new` over SSH and parses the `MOSH CONNECT ...` line.
enum MoshBootstrap {
    static func startNewSession(connection: SSHConnection) async throws -> MoshBootstrapResult {
        let output = try await connection.executeCommand("mosh-server new")
        return try parseMoshServerOutput(output)
    }

    static func parseMoshServerOutput(_ output: String) throws -> MoshBootstrapResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw MoshBootstrapError.invalidOutput(output)
        }

        let lower = trimmed.lowercased()
        if lower.contains("command not found") || (lower.contains("not found") && lower.contains("mosh-server")) {
            throw MoshBootstrapError.moshServerNotInstalled(trimmed)
        }

        // Expected line:
        // MOSH CONNECT <port> <key>
        for lineSub in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("MOSH CONNECT ") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            guard let port = Int(parts[2]), port > 0, port <= 65535 else { continue }
            let key = parts[3...].joined(separator: " ")
            if key.isEmpty { continue }
            return MoshBootstrapResult(udpPort: port, key: key)
        }

        throw MoshBootstrapError.invalidOutput(trimmed)
    }
}

