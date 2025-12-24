import SwiftUI

/// Tab bar showing all active terminal sessions
/// Uses macOS-style layout where tabs stretch to fill available space
struct SessionTabBar: View {
    @EnvironmentObject var sessionManager: SessionManager

    /// Callback when user wants to open a new tab
    var onNewTab: () -> Void

    /// Minimum tab width before switching to scroll mode
    private let minTabWidth: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 44 - 4  // minus + button and padding
            let tabCount = max(1, sessionManager.sessions.count)
            let tabWidth = availableWidth / CGFloat(tabCount)
            let useScrollMode = tabWidth < minTabWidth

            HStack(spacing: 0) {
                if useScrollMode {
                    // Scroll mode for many tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(sessionManager.sessions) { session in
                                SessionTab(
                                    session: session,
                                    isActive: session.id == sessionManager.activeSessionId,
                                    onSelect: { sessionManager.switchTo(session) },
                                    onClose: { sessionManager.closeSession(session) }
                                )
                                .frame(width: minTabWidth)
                            }
                        }
                    }
                } else {
                    // Stretch mode - tabs fill available space
                    HStack(spacing: 2) {
                        ForEach(sessionManager.sessions) { session in
                            SessionTab(
                                session: session,
                                isActive: session.id == sessionManager.activeSessionId,
                                onSelect: { sessionManager.switchTo(session) },
                                onClose: { sessionManager.closeSession(session) }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // Fixed + button on right
                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 32)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
        }
        .frame(height: 44)
        .background(Color(.systemGray6))
    }
}

/// Individual session tab
struct SessionTab: View {
    @ObservedObject var session: Session
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    /// Animation state for pulsing "waiting for input" indicator
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 0) {
            // Connection status indicator with waiting overlay
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Pulsing ring when waiting for input
                if session.isWaitingForInput && !isActive {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .opacity(isPulsing ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                }
            }
            .frame(width: 20)

            Spacer(minLength: 4)

            // Tab title - centered, truncates as needed
            Text(session.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isActive ? .primary : .secondary)

            Spacer(minLength: 4)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isActive ? Color(.systemBackground) : Color(.systemGray5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear {
            isPulsing = true
        }
        .onChange(of: session.isWaitingForInput) { _, isWaiting in
            if isWaiting && !isActive {
                // Trigger haptic feedback when non-active tab needs input
                triggerInputNeededFeedback()
            }
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    /// Trigger haptic and optional sound when input is needed
    private func triggerInputNeededFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject var sessionManager = SessionManager()

        var body: some View {
            VStack {
                SessionTabBar(onNewTab: { print("New tab") })
                    .environmentObject(sessionManager)

                Spacer()
            }
            .onAppear {
                // Add some test sessions
                let config1 = SavedConnection(
                    name: "Production",
                    host: "prod.example.com",
                    port: 22,
                    username: "admin",
                    authMethod: .password
                )
                let config2 = SavedConnection(
                    name: "",
                    host: "dev.example.com",
                    port: 22,
                    username: "developer",
                    authMethod: .password
                )

                _ = sessionManager.createSession(for: config1)
                let session2 = sessionManager.createSession(for: config2)
                session2.state = .connecting
            }
        }
    }

    return PreviewWrapper()
}
