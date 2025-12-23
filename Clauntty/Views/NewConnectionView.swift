import SwiftUI

struct NewConnectionView: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var authType: AuthType = .password
    @State private var password: String = ""
    @State private var savePassword: Bool = true
    @State private var sshKeyId: String = ""
    @State private var sshKeyContent: String = ""
    @State private var showingKeyImporter = false
    @State private var keyImported = false

    // Validation
    @State private var showingValidationError = false
    @State private var validationError = ""

    private let existingConnection: SavedConnection?
    private var isEditing: Bool { existingConnection != nil }

    enum AuthType: String, CaseIterable {
        case password = "Password"
        case sshKey = "SSH Key"
    }

    init(existingConnection: SavedConnection? = nil) {
        self.existingConnection = existingConnection

        if let existing = existingConnection {
            _name = State(initialValue: existing.name)
            _host = State(initialValue: existing.host)
            _port = State(initialValue: String(existing.port))
            _username = State(initialValue: existing.username)
            switch existing.authMethod {
            case .password:
                _authType = State(initialValue: .password)
            case .sshKey(let keyId):
                _authType = State(initialValue: .sshKey)
                _sshKeyId = State(initialValue: keyId)
            }
        } else {
            _name = State(initialValue: "")
            _host = State(initialValue: "")
            _port = State(initialValue: "22")
            _username = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.never)

                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)

                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Authentication") {
                    Picker("Method", selection: $authType) {
                        ForEach(AuthType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    switch authType {
                    case .password:
                        SecureField("Password", text: $password)
                        Toggle("Save password", isOn: $savePassword)
                    case .sshKey:
                        if keyImported {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("SSH Key imported")
                                Spacer()
                                Button("Change") {
                                    keyImported = false
                                    sshKeyContent = ""
                                }
                                .foregroundColor(.blue)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paste your private key (Ed25519):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $sshKeyContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )

                                if !sshKeyContent.isEmpty {
                                    Button("Import Key") {
                                        importSSHKey()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            Button {
                                showingKeyImporter = true
                            } label: {
                                Label("Import from Files", systemImage: "doc")
                            }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showingKeyImporter,
                    allowedContentTypes: [.data, .text],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImport(result)
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "New Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConnection()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationError)
            }
        }
    }

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(port) ?? 0) > 0 && (Int(port) ?? 0) <= 65535
    }

    private func importSSHKey() {
        let trimmedKey = sshKeyContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate key format
        guard trimmedKey.contains("BEGIN OPENSSH PRIVATE KEY") else {
            validationError = "Invalid SSH key format. Only OpenSSH Ed25519 keys are supported."
            showingValidationError = true
            return
        }

        // Generate a key ID if we don't have one
        if sshKeyId.isEmpty {
            sshKeyId = UUID().uuidString
        }

        // Save to Keychain
        guard let keyData = trimmedKey.data(using: .utf8) else {
            validationError = "Failed to encode SSH key"
            showingValidationError = true
            return
        }

        do {
            try KeychainHelper.saveSSHKey(id: sshKeyId, privateKey: keyData)
            keyImported = true
        } catch {
            validationError = "Failed to save SSH key: \(error.localizedDescription)"
            showingValidationError = true
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                validationError = "Cannot access file"
                showingValidationError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let keyContent = try String(contentsOf: url, encoding: .utf8)
                sshKeyContent = keyContent
                importSSHKey()
            } catch {
                validationError = "Failed to read file: \(error.localizedDescription)"
                showingValidationError = true
            }

        case .failure(let error):
            validationError = "Failed to import file: \(error.localizedDescription)"
            showingValidationError = true
        }
    }

    private func saveConnection() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedHost.isEmpty else {
            validationError = "Host is required"
            showingValidationError = true
            return
        }

        guard !trimmedUsername.isEmpty else {
            validationError = "Username is required"
            showingValidationError = true
            return
        }

        guard let portNumber = Int(port), portNumber > 0, portNumber <= 65535 else {
            validationError = "Port must be between 1 and 65535"
            showingValidationError = true
            return
        }

        let authMethod: AuthMethod
        switch authType {
        case .password:
            authMethod = .password
        case .sshKey:
            authMethod = .sshKey(keyId: sshKeyId.isEmpty ? UUID().uuidString : sshKeyId)
        }

        let connection = SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: trimmedName,
            host: trimmedHost,
            port: portNumber,
            username: trimmedUsername,
            authMethod: authMethod,
            lastConnected: existingConnection?.lastConnected
        )

        // Check for duplicate (same host, port, username, and name)
        if let duplicate = connectionStore.findDuplicate(of: connection, excludingId: existingConnection?.id) {
            validationError = "A connection with the same settings already exists: \(duplicate.displayName)"
            showingValidationError = true
            return
        }

        // Save password to Keychain if provided
        if authType == .password && savePassword && !password.isEmpty {
            try? KeychainHelper.savePassword(for: connection.id, password: password)
        }

        if isEditing {
            connectionStore.update(connection)
        } else {
            connectionStore.add(connection)
        }

        dismiss()
    }
}

#Preview {
    NewConnectionView()
        .environmentObject(ConnectionStore())
}
