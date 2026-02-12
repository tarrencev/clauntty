import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ghosttyApp: GhosttyApp
    @EnvironmentObject var appState: AppState
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var notificationManager = NotificationManager.shared
    @ObservedObject var powerManager = PowerManager.shared
    @ObservedObject var speechManager = SpeechManager.shared
    @State private var showingDownloadConfirmation = false
    @AppStorage("sessionManagementEnabled") private var sessionManagementEnabled = true
    @AppStorage(CursorTapPreference.userDefaultsKey) private var tapToMoveCursorEnabled = true
    @State private var fontSize: Float = FontSizePreference.current
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        HStack {
                            Text("Theme")
                            Spacer()
                            Text(ghosttyApp.currentTheme?.name ?? "Default")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Stepper("", value: $fontSize, in: 6...36, step: 1)
                            .labelsHidden()
                            .onChange(of: fontSize) { _, newValue in
                                FontSizePreference.save(newValue)
                            }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Session Management", isOn: $sessionManagementEnabled)
                } header: {
                    Text("Sessions")
                } footer: {
                    Text("When enabled, terminal sessions persist on the server using rtach. Reconnecting restores your session with scrollback history.")
                }

                Section {
                    Toggle("Tap to move cursor", isOn: $tapToMoveCursorEnabled)

                    NavigationLink("Keyboard Bar") {
                        KeyboardBarSettingsView()
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("When enabled, tapping on the active cursor line repositions the cursor horizontally.")
                }

                Section {
                    voiceInputContent
                } header: {
                    Text("Voice Input")
                } footer: {
                    Text("Speak commands instead of typing. Uses on-device speech recognition for privacy.")
                }

                Section {
                    Toggle("Battery Saver", isOn: $powerManager.batterySaverEnabled)
                } header: {
                    Text("Performance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reduces rendering frequency to extend battery life.")
                        if powerManager.currentMode == .lowPower && !powerManager.batterySaverEnabled {
                            Text("Currently active due to low battery, thermal throttling, or iOS Low Power Mode.")
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section {
                    Picker("Input notifications", selection: $notificationManager.notificationMode) {
                        ForEach(NotificationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    // Show system settings link if permission denied
                    if !notificationManager.isAuthorized && notificationManager.hasPromptedForPermission {
                        Button("Enable in Settings") {
                            openNotificationSettings()
                        }
                        .foregroundColor(.blue)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when a terminal is waiting for your input while the app is in the background.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            appState.beginInputSuppression()
            dismissTerminalInput()
        }
        .onDisappear {
            appState.endInputSuppression()
        }
    }

    @ViewBuilder
    private var voiceInputContent: some View {
        switch speechManager.modelState {
        case .notDownloaded:
            Button {
                showingDownloadConfirmation = true
            } label: {
                HStack {
                    Label("Enable Voice Input", systemImage: "mic.fill")
                    Spacer()
                    Text("~800 MB")
                        .foregroundColor(.secondary)
                }
            }
            .alert("Download Speech Model?", isPresented: $showingDownloadConfirmation) {
                Button("Download") {
                    Task {
                        await speechManager.downloadModel()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will download approximately 800 MB of data for on-device speech recognition. The model runs entirely on your device for privacy.")
            }

        case .downloading(let progress):
            HStack {
                Label("Downloading...", systemImage: "arrow.down.circle")
                Spacer()
                if progress > 0 {
                    ProgressView(value: Double(progress))
                        .frame(width: 100)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

        case .ready:
            HStack {
                Label("Voice input enabled", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Spacer()
            }
            Button("Delete Speech Model", role: .destructive) {
                speechManager.deleteModel()
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Retry") {
                    Task {
                        await speechManager.downloadModel()
                    }
                }
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func dismissTerminalInput() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.endEditing(true) }
        NotificationCenter.default.post(name: .hideAllAccessoryBars, object: nil)
    }
}

#Preview {
    SettingsView()
        .environmentObject(GhosttyApp())
        .environmentObject(AppState())
}

struct KeyboardBarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout = KeyboardBarLayoutStore.load()
    @State private var showingResetAlert = false

    var body: some View {
        Form {
            Section("Left Slots") {
                ForEach(0..<KeyboardBarLayout.leftSlotCount, id: \.self) { index in
                    slotEditor(title: "L\(index + 1)", side: .left, index: index)
                }
            }

            Section("Right Slots") {
                ForEach(0..<KeyboardBarLayout.rightSlotCount, id: \.self) { index in
                    slotEditor(title: "R\(index + 1)", side: .right, index: index)
                }
            }

            Section {
                Button("Reset to Default", role: .destructive) {
                    showingResetAlert = true
                }
            } footer: {
                Text("Center joystick is fixed. Duplicates and empty slots are allowed.")
            }
        }
        .navigationTitle("Keyboard Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Reset Keyboard Bar?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                layout = KeyboardBarLayout.default.normalized()
                persistLayout()
            }
        } message: {
            Text("This restores the default keyboard bar slots.")
        }
    }

    @ViewBuilder
    private func slotEditor(title: String, side: Side, index: Int) -> some View {
        let actionBinding = actionBinding(side: side, index: index)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.medium))

            actionEditorRow(label: "Tap", actionBinding: actionBinding, hold: false)
            actionEditorRow(label: "Hold", actionBinding: actionBinding, hold: true)
        }
    }

    @ViewBuilder
    private func actionEditorRow(label: String, actionBinding: Binding<KeyboardBarAction>, hold: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)

            if hold {
                Picker(label, selection: Binding<KeyboardBarActionKind?>(
                    get: { actionBinding.wrappedValue.holdKind },
                    set: { newKind in
                        var action = actionBinding.wrappedValue
                        if let newKind {
                            action.holdKind = newKind
                            if newKind != .snippet {
                                action.holdSnippetText = nil
                                action.holdSnippetLabel = nil
                                action.holdSnippetRunOnTap = nil
                            } else if action.holdSnippetText == nil {
                                action.holdSnippetText = ""
                                action.holdSnippetLabel = "Hold"
                                action.holdSnippetRunOnTap = false
                            }
                            if newKind != .customKey {
                                action.holdCustomText = nil
                                action.holdCustomLabel = nil
                            } else if action.holdCustomText == nil {
                                action.holdCustomText = ""
                                action.holdCustomLabel = "Key"
                            }
                        } else {
                            action.setHoldAction(nil)
                        }
                        actionBinding.wrappedValue = action
                        persistLayout()
                    }
                )) {
                    Text("None").tag(nil as KeyboardBarActionKind?)
                    ForEach(KeyboardBarActionKind.pickerOrder.filter { $0 != .empty }) { kind in
                        Text(kind.title).tag(kind as KeyboardBarActionKind?)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker(label, selection: Binding(
                    get: { actionBinding.wrappedValue.kind },
                    set: { newKind in
                        var action = actionBinding.wrappedValue
                        action.kind = newKind
                        if newKind != .snippet {
                            action.snippetText = nil
                            action.snippetLabel = nil
                            action.snippetRunOnTap = nil
                        } else if action.snippetText == nil {
                            action.snippetText = ""
                            action.snippetLabel = "Snippet"
                            action.snippetRunOnTap = false
                        }
                        if newKind != .customKey {
                            action.customText = nil
                            action.customLabel = nil
                        } else if action.customText == nil {
                            action.customText = ""
                            action.customLabel = "Key"
                        }
                        actionBinding.wrappedValue = action
                        persistLayout()
                    }
                )) {
                    ForEach(KeyboardBarActionKind.pickerOrder) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }
        }

        if (hold ? actionBinding.wrappedValue.holdKind : actionBinding.wrappedValue.kind) == .snippet {
            TextField("Label", text: Binding(
                get: { hold ? (actionBinding.wrappedValue.holdSnippetLabel ?? "Hold") : (actionBinding.wrappedValue.snippetLabel ?? "Snippet") },
                set: { newValue in
                    var action = actionBinding.wrappedValue
                    if hold {
                        action.holdSnippetLabel = newValue
                    } else {
                        action.snippetLabel = newValue
                    }
                    actionBinding.wrappedValue = action
                    persistLayout()
                }
            ))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()

            TextField("Text", text: Binding(
                get: { hold ? (actionBinding.wrappedValue.holdSnippetText ?? "") : (actionBinding.wrappedValue.snippetText ?? "") },
                set: { newValue in
                    var action = actionBinding.wrappedValue
                    if hold {
                        action.holdSnippetText = newValue
                    } else {
                        action.snippetText = newValue
                    }
                    actionBinding.wrappedValue = action
                    persistLayout()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))

            Toggle("Run on tap", isOn: Binding(
                get: { hold ? (actionBinding.wrappedValue.holdSnippetRunOnTap ?? false) : (actionBinding.wrappedValue.snippetRunOnTap ?? false) },
                set: { newValue in
                    var action = actionBinding.wrappedValue
                    if hold {
                        action.holdSnippetRunOnTap = newValue
                    } else {
                        action.snippetRunOnTap = newValue
                    }
                    actionBinding.wrappedValue = action
                    persistLayout()
                }
            ))
        }

        if (hold ? actionBinding.wrappedValue.holdKind : actionBinding.wrappedValue.kind) == .customKey {
            TextField("Label", text: Binding(
                get: { hold ? (actionBinding.wrappedValue.holdCustomLabel ?? "Key") : (actionBinding.wrappedValue.customLabel ?? "Key") },
                set: { newValue in
                    var action = actionBinding.wrappedValue
                    if hold {
                        action.holdCustomLabel = newValue
                    } else {
                        action.customLabel = newValue
                    }
                    actionBinding.wrappedValue = action
                    persistLayout()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField("Key text", text: Binding(
                get: { hold ? (actionBinding.wrappedValue.holdCustomText ?? "") : (actionBinding.wrappedValue.customText ?? "") },
                set: { newValue in
                    var action = actionBinding.wrappedValue
                    if hold {
                        action.holdCustomText = newValue
                    } else {
                        action.customText = newValue
                    }
                    actionBinding.wrappedValue = action
                    persistLayout()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))
        }
    }

    private func actionBinding(side: Side, index: Int) -> Binding<KeyboardBarAction> {
        Binding(
            get: {
                switch side {
                case .left:
                    return layout.leftSlots[index]
                case .right:
                    return layout.rightSlots[index]
                }
            },
            set: { newValue in
                switch side {
                case .left:
                    layout.leftSlots[index] = newValue
                case .right:
                    layout.rightSlots[index] = newValue
                }
            }
        )
    }

    private func persistLayout() {
        let normalized = layout.normalized()
        layout = normalized
        KeyboardBarLayoutStore.save(normalized)
        NotificationCenter.default.post(name: .keyboardBarLayoutChanged, object: nil)
    }

    private enum Side {
        case left
        case right
    }
}
