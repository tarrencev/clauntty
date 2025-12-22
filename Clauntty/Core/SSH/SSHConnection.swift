import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Manages an SSH connection lifecycle
@MainActor
class SSHConnection: ObservableObject {
    // MARK: - State

    enum State {
        case disconnected
        case connecting
        case authenticating
        case connected
        case error(Error)
    }

    @Published var state: State = .disconnected

    // MARK: - Configuration

    private let host: String
    private let port: Int
    private let username: String
    private let authMethod: AuthMethod

    // MARK: - NIO Components

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var sshChildChannel: Channel?

    // MARK: - Bridge

    private nonisolated let bridge: GhosttyBridge

    // Callback when connected
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?

    // MARK: - Initialization

    init(
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod,
        bridge: GhosttyBridge
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.bridge = bridge
    }

    // MARK: - Connection

    func connect() async throws {
        state = .connecting

        do {
            // Create event loop group
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            guard let group = eventLoopGroup else {
                throw SSHError.internalError("Failed to create event loop group")
            }

            // Capture values for closure
            let username = self.username
            let authMethod = self.authMethod

            // Create client bootstrap
            let bootstrap = ClientBootstrap(group: group)
                .channelInitializer { channel in
                    // Add SSH handler
                    channel.pipeline.addHandlers([
                        NIOSSHHandler(
                            role: .client(.init(
                                userAuthDelegate: SSHAuthenticator(
                                    username: username,
                                    authMethod: authMethod
                                ),
                                serverAuthDelegate: AcceptAllHostKeysDelegate()
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                    ])
                }
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .connectTimeout(.seconds(30))

            // Connect
            let channel = try await bootstrap.connect(host: host, port: port).get()
            self.channel = channel

            state = .authenticating

            // Create SSH channel for PTY
            try await createPTYChannel()

            state = .connected
            onConnected?()

        } catch {
            state = .error(error)
            throw error
        }
    }

    private func createPTYChannel() async throws {
        guard let channel = self.channel else {
            throw SSHError.notConnected
        }

        // Capture bridge for closure
        let bridge = self.bridge

        // Create child channel for PTY session
        let childChannel = try await channel.pipeline.handler(type: NIOSSHHandler.self).flatMap { handler -> EventLoopFuture<Channel> in
            let promise = channel.eventLoop.makePromise(of: Channel.self)

            handler.createChannel(promise) { childChannel, channelType in
                guard channelType == .session else {
                    return channel.eventLoop.makeFailedFuture(SSHError.invalidChannelType)
                }
                return childChannel.pipeline.addHandler(
                    SSHChannelHandler(bridge: bridge)
                )
            }

            return promise.futureResult
        }.get()

        self.sshChildChannel = childChannel

        // Request PTY
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:])
        )

        try await childChannel.triggerUserOutboundEvent(ptyRequest).get()

        // Request shell
        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        try await childChannel.triggerUserOutboundEvent(shellRequest).get()
    }

    func disconnect() {
        channel?.close(mode: .all, promise: nil)
        channel = nil
        sshChildChannel = nil

        eventLoopGroup?.shutdownGracefully { _ in }
        eventLoopGroup = nil

        state = .disconnected
        onDisconnected?(nil)
    }
}

// MARK: - SSH Channel Handler

/// Handles SSH channel data
final class SSHChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let bridge: GhosttyBridge

    init(bridge: GhosttyBridge) {
        self.bridge = bridge

        // Set up bridge callback
        bridge.onDataFromTerminal = { [weak self] data in
            self?.sendToRemote(data)
        }
    }

    private var context: ChannelHandlerContext?

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)

        // Only handle standard data (not extended/stderr)
        guard case .byteBuffer(let buffer) = channelData.data,
              channelData.type == .channel else {
            return
        }

        // Get bytes and send to bridge (displays in terminal)
        if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
            let data = Data(bytes)
            DispatchQueue.main.async { [weak self] in
                self?.bridge.writeToTerminal(data)
            }
        }
    }

    func sendToRemote(_ data: Data) {
        guard let context = context else { return }

        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.writeAndFlush(wrapOutboundOut(channelData), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("SSH channel error: \(error)")
        context.close(promise: nil)
    }
}

// MARK: - Host Key Delegate

/// Accepts all host keys (for MVP - should implement known_hosts in production)
final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // WARNING: This accepts all host keys - insecure for production!
        // TODO: Implement proper host key verification
        validationCompletePromise.succeed(())
    }
}

// MARK: - Errors

enum SSHError: Error, LocalizedError {
    case notConnected
    case invalidChannelType
    case authenticationFailed
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to SSH server"
        case .invalidChannelType:
            return "Invalid SSH channel type"
        case .authenticationFailed:
            return "SSH authentication failed"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
