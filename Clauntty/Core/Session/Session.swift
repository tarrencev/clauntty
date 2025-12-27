import Foundation
import NIOCore
import NIOSSH
import os.log
import RtachClient

/// Represents a single terminal session (one tab)
/// Each session has its own SSH channel and terminal surface
@MainActor
class Session: ObservableObject, Identifiable {
    // MARK: - Identity

    let id: UUID
    let connectionConfig: SavedConnection
    let createdAt: Date

    // MARK: - State

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: State = .disconnected

    /// Dynamic title set by terminal escape sequences (OSC 0/1/2)
    @Published var dynamicTitle: String? {
        didSet {
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): dynamicTitle set to '\(self.dynamicTitle ?? "nil")'")

            // Persist the title for session restoration
            if let title = dynamicTitle, let sessionId = rtachSessionId {
                let key = Self.titleStorageKey(connectionId: connectionConfig.id, rtachSessionId: sessionId)
                UserDefaults.standard.set(title, forKey: key)

                // If this is a Claude session (has ✳️), remember that permanently
                if title.contains("\u{2733}") {
                    markAsClaudeSession()
                }
            }

            // Check for pending notification when title is set
            checkPendingNotification()
        }
    }

    /// Whether this session has ever been identified as Claude (persisted)
    private var _isClaudeSession: Bool = false

    /// Display title for tab - prefer dynamic title if set
    var title: String {
        if let dynamic = dynamicTitle, !dynamic.isEmpty {
            return dynamic
        }
        if !connectionConfig.name.isEmpty {
            return connectionConfig.name
        }
        return "\(connectionConfig.username)@\(connectionConfig.host)"
    }

    /// Whether this appears to be a Claude Code session (detected by ✳️ in title)
    var isClaudeSession: Bool {
        // If we have a title, always check it directly (handles user exiting Claude)
        if let title = dynamicTitle {
            return title.contains("\u{2733}")  // ✳️ eight-spoked asterisk
        }
        // No title yet - use persisted flag (bridges gap during session restore)
        return _isClaudeSession
    }

    /// Whether we have a pending notification waiting for title to be set
    private var pendingNotificationCheck: Bool = false

    /// Mark this session as a Claude session (persisted)
    private func markAsClaudeSession() {
        guard !_isClaudeSession else { return }
        _isClaudeSession = true
        if let sessionId = rtachSessionId {
            let key = Self.claudeSessionKey(connectionId: connectionConfig.id, rtachSessionId: sessionId)
            UserDefaults.standard.set(true, forKey: key)
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): marked as Claude session")
        }
    }

    /// Restore Claude session flag from UserDefaults
    private func restoreClaudeSessionFlag(rtachSessionId: String) {
        let key = Self.claudeSessionKey(connectionId: connectionConfig.id, rtachSessionId: rtachSessionId)
        _isClaudeSession = UserDefaults.standard.bool(forKey: key)
        if _isClaudeSession {
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): restored Claude session flag")
        }
    }

    /// Storage key for Claude session flag
    private static func claudeSessionKey(connectionId: UUID, rtachSessionId: String) -> String {
        return "session_claude_\(connectionId.uuidString)_\(rtachSessionId)"
    }

    /// Check if we should send a notification (called when title is set)
    /// Note: We don't check isWaitingForInput here because more data may have arrived
    /// after the inactivity timeout. The pending flag itself means we were waiting.
    private func checkPendingNotification() {
        guard pendingNotificationCheck else { return }

        pendingNotificationCheck = false
        Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): checking pending notification, isClaudeSession=\(self.isClaudeSession)")

        if NotificationManager.shared.shouldNotify(for: self) {
            Task {
                await NotificationManager.shared.scheduleInputReady(session: self)
            }
        }
    }

    // MARK: - Input Detection (Inactivity-based)

    /// Whether the terminal is waiting for user input (detected via inactivity timeout)
    @Published private(set) var isWaitingForInput: Bool = false

    /// Timer for detecting inactivity after output stops
    private var inactivityTimer: Timer?

    /// How long to wait after output stops before considering terminal idle (seconds)
    private let inactivityThreshold: TimeInterval = 1.5

    // MARK: - SSH Channel

    /// The SSH child channel for this session
    private(set) var sshChannel: Channel?

    /// Channel handler for data flow
    private(set) var channelHandler: SSHChannelHandler?

    /// Reference to parent connection (for sending data)
    weak var parentConnection: SSHConnection?

    /// Strong reference to SSH connection - each session owns its connection
    /// This keeps the connection alive for the lifetime of the session
    var sshConnection: SSHConnection?

    // MARK: - Terminal Size

    /// Initial terminal size to use when connecting (rows, columns)
    /// Set this before connecting for correct initial PTY size
    var initialTerminalSize: (rows: Int, columns: Int) = (30, 60)

    // MARK: - rtach Session

    /// The rtach session ID to use when connecting (nil = create new session)
    var rtachSessionId: String? {
        didSet {
            // Restore the saved title when resuming a session
            if let sessionId = rtachSessionId {
                restoreSavedTitle(rtachSessionId: sessionId)
            }
        }
    }

    /// Storage key for persisting dynamic title
    private static func titleStorageKey(connectionId: UUID, rtachSessionId: String) -> String {
        return "session_title_\(connectionId.uuidString)_\(rtachSessionId)"
    }

    /// Restore saved title for a resumed session
    private func restoreSavedTitle(rtachSessionId: String) {
        // Restore Claude session flag first
        restoreClaudeSessionFlag(rtachSessionId: rtachSessionId)

        // Restore title
        let key = Self.titleStorageKey(connectionId: connectionConfig.id, rtachSessionId: rtachSessionId)
        if let savedTitle = UserDefaults.standard.string(forKey: key) {
            // Only restore if we don't already have a dynamic title
            if dynamicTitle == nil {
                dynamicTitle = savedTitle
                Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): restored title '\(savedTitle.prefix(30))'")
            }
        }
    }

    // MARK: - Scrollback Buffer

    /// Buffer of all received data (for persistence)
    private(set) var scrollbackBuffer = Data()

    /// Maximum scrollback buffer size (50KB)
    private let maxScrollbackSize = 50 * 1024

    // MARK: - Callbacks

    /// Called when data is received from SSH (to display in terminal)
    var onDataReceived: ((Data) -> Void)?

    /// Called when session state changes
    var onStateChanged: ((State) -> Void)?

    /// Called when old scrollback is received (to prepend to terminal)
    var onScrollbackReceived: ((Data) -> Void)?

    /// Called when a port forward is requested via OSC 777
    var onPortForwardRequested: ((Int) -> Void)?

    /// Called when a web tab should be opened via OSC 777
    var onOpenTabRequested: ((Int) -> Void)?

    // MARK: - rtach Protocol Session

    /// State machine for rtach protocol (raw/framed mode handling)
    private let rtachProtocol = RtachClient.RtachSession()

    /// Debug counters for tracking data flow
    private var totalBytesReceived = 0
    private var totalBytesToTerminal = 0

    // MARK: - Paginated Scrollback State

    /// Page size for scrollback requests (16KB)
    private let scrollbackPageSize = 16 * 1024

    /// Current offset into scrollback (0 = oldest data)
    private var scrollbackLoadedOffset: Int = 0

    /// Total scrollback size (set when first page received)
    private var scrollbackTotalSize: Int?

    /// Whether we've finished loading all scrollback
    private var scrollbackFullyLoaded: Bool = false

    /// Whether a scrollback page request is currently in flight
    private var scrollbackPageRequestPending: Bool = false

    // MARK: - Initialization

    init(connectionConfig: SavedConnection) {
        self.id = UUID()
        self.connectionConfig = connectionConfig
        self.createdAt = Date()
    }

    // MARK: - Channel Management

    /// Attach an SSH channel to this session
    /// - Parameters:
    ///   - channel: The SSH channel
    ///   - handler: The channel handler
    ///   - connection: The parent SSH connection
    ///   - expectsRtach: Whether to expect rtach protocol (session management enabled)
    func attach(channel: Channel, handler: SSHChannelHandler, connection: SSHConnection, expectsRtach: Bool = true) {
        self.sshChannel = channel
        self.channelHandler = handler
        self.parentConnection = connection
        self.state = .connected
        onStateChanged?(.connected)

        // Set up rtach protocol delegate and mark as connected
        rtachProtocol.expectsRtach = expectsRtach
        rtachProtocol.delegate = self
        rtachProtocol.connect()

        Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): channel attached, channelHandler is set")
    }

    /// Detach the channel (on disconnect)
    func detach() {
        // Clean up inactivity timer
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        // Disconnect our SSH connection
        sshConnection?.disconnect()
        sshConnection = nil
        sshChannel = nil
        channelHandler = nil
        parentConnection = nil
        state = .disconnected
        onStateChanged?(.disconnected)

        // Reset rtach protocol state for reconnection
        rtachProtocol.reset()

        Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): channel detached")
    }

    // MARK: - Data Flow

    /// Handle data received from SSH
    /// Delegates to RtachSession for protocol handling (raw vs framed mode)
    func handleDataReceived(_ data: Data) {
        self.totalBytesReceived += data.count
        // Debug: log first 32 bytes as hex
        let preview = data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        Logger.clauntty.info("[FRAME] received \(data.count) bytes (total=\(self.totalBytesReceived)), state=\(String(describing: self.rtachProtocol.state)), first32=\(preview)")

        // Delegate to RtachSession for protocol handling
        rtachProtocol.processIncomingData(data)
    }

    // MARK: - Loading Indicator

    /// Whether we're currently loading a large amount of data (show loading indicator)
    @Published private(set) var isLoadingContent: Bool = false

    /// Bytes received in the current sliding window
    private var recentBytes: [(Date, Int)] = []

    /// Timer to check if loading is complete
    private var loadingCheckTimer: Timer?

    /// Threshold: show loading if we receive this many bytes in the window
    private let loadingShowThreshold = 10 * 1024  // 10KB (show quickly)

    /// Window size for tracking recent bytes
    private let loadingWindowSize: TimeInterval = 0.1  // 100ms

    /// How long of low activity before hiding loading indicator
    private let loadingHideDelay: TimeInterval = 0.3  // 300ms

    /// Update loading state based on incoming data rate
    private func updateLoadingState(bytesReceived: Int) {
        let now = Date()

        // Add this chunk to recent bytes
        recentBytes.append((now, bytesReceived))

        // Remove old entries outside the window
        let windowStart = now.addingTimeInterval(-loadingWindowSize)
        recentBytes.removeAll { $0.0 < windowStart }

        // Calculate bytes in window
        let bytesInWindow = recentBytes.reduce(0) { $0 + $1.1 }

        // If receiving lots of data, show loading indicator
        if bytesInWindow >= loadingShowThreshold {
            if !isLoadingContent {
                isLoadingContent = true
                Logger.clauntty.info("[LOAD] Showing loading indicator (bytes in window: \(bytesInWindow))")
            }

            // Reset/restart the hide timer
            loadingCheckTimer?.invalidate()
            loadingCheckTimer = Timer.scheduledTimer(withTimeInterval: loadingHideDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.checkLoadingComplete()
                }
            }
        }
    }

    /// Check if loading is complete (called after delay)
    private func checkLoadingComplete() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-loadingWindowSize)
        recentBytes.removeAll { $0.0 < windowStart }

        let bytesInWindow = recentBytes.reduce(0) { $0 + $1.1 }

        // If data rate is low, hide loading indicator
        if bytesInWindow < 1024 {  // Less than 1KB in window
            if isLoadingContent {
                isLoadingContent = false
                Logger.clauntty.info("[LOAD] Hiding loading indicator (bytes in window: \(bytesInWindow))")
            }
        } else {
            // Still receiving data, check again later
            loadingCheckTimer = Timer.scheduledTimer(withTimeInterval: loadingHideDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.checkLoadingComplete()
                }
            }
        }
    }

    /// Process terminal data (forward to terminal and track scrollback)
    private func processTerminalData(_ data: Data) {
        totalBytesToTerminal += data.count

        // Log if this data contains alternate screen switch escape sequence
        // ESC[?1049h = switch to alternate screen (bytes: 1b 5b 3f 31 30 34 39 68)
        // ESC[?1049l = switch to normal screen (bytes: 1b 5b 3f 31 30 34 39 6c)
        // Search for byte pattern directly (more reliable than UTF-8 string conversion)
        let altScreenEnter = Data([0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]) // ESC[?1049h
        let altScreenExit = Data([0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c])  // ESC[?1049l

        if data.range(of: altScreenEnter) != nil {
            Logger.clauntty.info("[ALTSCREEN] Received ESC[?1049h (switch to alternate screen) in \(data.count) bytes")
        }
        if data.range(of: altScreenExit) != nil {
            Logger.clauntty.info("[ALTSCREEN] Received ESC[?1049l (switch to normal screen) in \(data.count) bytes")
        }

        // Track loading state for showing loading indicator
        updateLoadingState(bytesReceived: data.count)

        // Reset inactivity timer - we received output
        resetInactivityTimer()

        // Append to scrollback buffer
        scrollbackBuffer.append(data)

        // Trim if too large (keep most recent data)
        if scrollbackBuffer.count > maxScrollbackSize {
            let excess = scrollbackBuffer.count - maxScrollbackSize
            scrollbackBuffer.removeFirst(excess)
        }

        // Forward to terminal
        onDataReceived?(data)
    }

    /// Handle a command received from rtach via command pipe
    /// Format: "command;arg1;arg2..."
    private func handleRtachCommand(_ command: String) {
        let parts = command.split(separator: ";", maxSplits: 1)
        guard let cmd = parts.first else { return }

        switch cmd {
        case "open":
            if parts.count > 1, let port = Int(parts[1]) {
                Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): rtach command open port \(port)")
                onOpenTabRequested?(port)
            }
        case "forward":
            if parts.count > 1, let port = Int(parts[1]) {
                Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): rtach command forward port \(port)")
                onPortForwardRequested?(port)
            }
        default:
            Logger.clauntty.debug("Session \(self.id.uuidString.prefix(8)): unknown rtach command: \(cmd)")
        }
    }

    // MARK: - Inactivity Detection

    /// Reset the inactivity timer when output is received
    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()

        // If we were waiting for input, we're not anymore (got output)
        if isWaitingForInput {
            isWaitingForInput = false
        }

        // Schedule timer to check for idle state
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfWaitingForInput()
            }
        }
    }

    /// Check if terminal is waiting for input after inactivity period
    private func checkIfWaitingForInput() {
        // Inactivity-based detection: no output for 1.5s means likely waiting for input
        if !isWaitingForInput {
            isWaitingForInput = true
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): waiting for input")
            checkNotificationForWaitingInput()
        }
    }

    /// Check if we should send a notification when waiting for input
    private func checkNotificationForWaitingInput() {
        // If we have title info, check notification immediately
        if dynamicTitle != nil || _isClaudeSession {
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): checking notification, isClaudeSession=\(self.isClaudeSession)")
            if NotificationManager.shared.shouldNotify(for: self) {
                Task {
                    await NotificationManager.shared.scheduleInputReady(session: self)
                }
            }
        } else {
            // No title yet - wait for title to be set
            pendingNotificationCheck = true
            Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): pending notification check (waiting for title)")
        }
    }

    /// Send data to remote (keyboard input)
    /// Uses rtach protocol to automatically frame when in framed mode
    func sendData(_ data: Data) {
        let hasHandler = self.channelHandler != nil
        Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): sendData called with \(data.count) bytes, channelHandler=\(hasHandler ? "set" : "nil")")
        if channelHandler == nil {
            Logger.clauntty.error("Session \(self.id.uuidString.prefix(8)): sendData called but channelHandler is nil!")
        }
        // Route through rtach protocol - handles raw vs framed mode
        rtachProtocol.sendKeyboardInput(data)
    }

    /// Send window size change
    func sendWindowChange(rows: UInt16, columns: UInt16) {
        guard let channel = sshChannel else {
            Logger.clauntty.warning("Session \(self.id.uuidString.prefix(8)): cannot send window change, no channel")
            return
        }

        // Send SSH window change request
        let windowChange = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: Int(columns),
            terminalRowHeight: Int(rows),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )

        channel.eventLoop.execute {
            channel.triggerUserOutboundEvent(windowChange, promise: nil)
        }

        // Also send via rtach protocol (WINCH packet) if in framed mode
        let size = RtachClient.WindowSize(rows: rows, cols: columns)
        rtachProtocol.sendWindowSize(size)

        Logger.clauntty.debug("Session \(self.id.uuidString.prefix(8)): window change \(columns)x\(rows)")
    }

    // MARK: - Scrollback Request

    /// Request a page of old scrollback from rtach (paginated)
    /// This uses the new request_scrollback_page message type (6) which returns
    /// scrollback in chunks to prevent iOS watchdog kills.
    func requestScrollbackPage() {
        // Only request scrollback after we've confirmed rtach is running (received handshake)
        // Before handshake or in raw mode, these packets would be sent to the shell as garbage input
        guard rtachProtocol.isRtachRunning else {
            Logger.clauntty.debug("Session \(self.id.uuidString.prefix(8)): skipping scrollback request (no rtach handshake received)")
            return
        }

        guard !scrollbackFullyLoaded else {
            Logger.clauntty.debug("Session \(self.id.uuidString.prefix(8)): scrollback already fully loaded")
            return
        }

        guard !scrollbackPageRequestPending else {
            Logger.clauntty.debug("Session \(self.id.uuidString.prefix(8)): scrollback page request already pending")
            return
        }

        guard channelHandler != nil else {
            Logger.clauntty.warning("Session \(self.id.uuidString.prefix(8)): cannot request scrollback, no channel")
            return
        }

        scrollbackPageRequestPending = true

        // Send via rtach protocol
        rtachProtocol.requestScrollbackPage(offset: UInt32(scrollbackLoadedOffset), limit: UInt32(scrollbackPageSize))

        Logger.clauntty.info("Session \(self.id.uuidString.prefix(8)): requesting scrollback page offset=\(self.scrollbackLoadedOffset) limit=\(self.scrollbackPageSize)")
    }

    /// Load more scrollback if user is scrolling near the top and more is available
    /// Call this from TerminalView when user scrolls near the top of scrollback
    func loadMoreScrollbackIfNeeded() {
        Logger.clauntty.debug("[SCROLL] loadMoreScrollbackIfNeeded called, pending=\(self.scrollbackPageRequestPending), fullyLoaded=\(self.scrollbackFullyLoaded)")
        requestScrollbackPage()
    }

    // MARK: - Scrollback Persistence

    /// Get scrollback data for restoration
    func getScrollbackData() -> Data {
        return scrollbackBuffer
    }

    /// Restore scrollback from saved data
    func restoreScrollback(_ data: Data) {
        scrollbackBuffer = data
        // Note: Terminal surface will need to replay this data
    }

    /// Clear scrollback buffer
    func clearScrollback() {
        scrollbackBuffer.removeAll()
    }
}

// MARK: - Hashable

extension Session: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - RtachSessionDelegate

extension Session: RtachClient.RtachSessionDelegate {
    nonisolated func rtachSession(_ session: RtachClient.RtachSession, didReceiveTerminalData data: Data) {
        Task { @MainActor in
            self.processTerminalData(data)
        }
    }

    nonisolated func rtachSession(_ session: RtachClient.RtachSession, didReceiveScrollback data: Data) {
        Task { @MainActor in
            Logger.clauntty.info("Scrollback response complete: \(data.count) bytes")
            self.scrollbackPageRequestPending = false
            self.onScrollbackReceived?(data)
        }
    }

    nonisolated func rtachSession(_ session: RtachClient.RtachSession, didReceiveScrollbackPage meta: RtachClient.ScrollbackPageMeta, data: Data) {
        Task { @MainActor in
            Logger.clauntty.info("Scrollback page complete: \(data.count) bytes, total=\(meta.totalLength), offset=\(meta.offset)")

            self.scrollbackTotalSize = Int(meta.totalLength)
            self.scrollbackPageRequestPending = false
            self.scrollbackLoadedOffset += data.count

            // Check if fully loaded
            if self.scrollbackLoadedOffset >= Int(meta.totalLength) {
                self.scrollbackFullyLoaded = true
                Logger.clauntty.info("Scrollback fully loaded: \(meta.totalLength) bytes total")
            }

            self.onScrollbackReceived?(data)
        }
    }

    nonisolated func rtachSession(_ session: RtachClient.RtachSession, didReceiveCommand data: Data) {
        Task { @MainActor in
            if let commandString = String(data: data, encoding: .utf8) {
                Logger.clauntty.info("Received command from rtach: \(commandString)")
                self.handleRtachCommand(commandString)
            }
        }
    }

    nonisolated func rtachSession(_ session: RtachClient.RtachSession, sendData data: Data) {
        // Must run synchronously to maintain packet order
        // The upgrade packet must be sent BEFORE we start framing keyboard input
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.channelHandler?.sendToRemote(data)
            }
        } else {
            Task { @MainActor in
                self.channelHandler?.sendToRemote(data)
            }
        }
    }
}
