import Foundation
import os.log

// Provided by Frameworks/MoshClient.xcframework (built from ThirdParty/mosh + protobuf + wrapper).
import MoshClient

@MainActor
final class MoshClientSession {
    private var client: UnsafeMutablePointer<clauntty_mosh_client_t>?
    private let onOutput: (Data) -> Void
    private let onEvent: (clauntty_mosh_event_t, String?) -> Void

    init(
        ip: String,
        port: String,
        key: String,
        cols: Int,
        rows: Int,
        onOutput: @escaping (Data) -> Void,
        onEvent: @escaping (clauntty_mosh_event_t, String?) -> Void
    ) throws {
        self.onOutput = onOutput
        self.onEvent = onEvent

        var errbuf = [CChar](repeating: 0, count: 512)

        let outputCtx = Unmanaged.passUnretained(self).toOpaque()
        let eventCtx = outputCtx

        // C callbacks. They may be invoked from a background thread.
        let outputCb: clauntty_mosh_output_cb = { bytes, len, ctx in
            guard let bytes, len > 0, let ctx else { return }
            let me = Unmanaged<MoshClientSession>.fromOpaque(ctx).takeUnretainedValue()
            let data = Data(bytes: bytes, count: len)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    me.onOutput(data)
                }
            }
        }

        let eventCb: clauntty_mosh_event_cb = { event, message, ctx in
            guard let ctx else { return }
            let me = Unmanaged<MoshClientSession>.fromOpaque(ctx).takeUnretainedValue()
            let msg = message.map { String(cString: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    me.onEvent(event, msg)
                }
            }
        }

        let created = ip.withCString { ipC in
            port.withCString { portC in
                key.withCString { keyC in
                    clauntty_mosh_client_create(
                        ipC,
                        portC,
                        keyC,
                        Int32(cols),
                        Int32(rows),
                        outputCb,
                        outputCtx,
                        eventCb,
                        eventCtx,
                        &errbuf,
                        errbuf.count
                    )
                }
            }
        }

        guard let created else {
            let msg = String(cString: errbuf)
            throw NSError(domain: "MoshClientSession", code: 1, userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Failed to create Mosh client" : msg])
        }

        self.client = created
    }

    deinit {
        if let client {
            clauntty_mosh_client_destroy(client)
        }
    }

    func start() {
        guard let client else { return }
        clauntty_mosh_client_start(client)
    }

    func stop() {
        guard let client else { return }
        clauntty_mosh_client_stop(client)
    }

    func setOutputEnabled(_ enabled: Bool) {
        guard let client else { return }
        clauntty_mosh_client_set_output_enabled(client, enabled ? 1 : 0)
    }

    func sendInput(_ data: Data) {
        guard let client else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            clauntty_mosh_client_send_input(client, base, ptr.count)
        }
    }

    func sendResize(cols: Int, rows: Int) {
        guard let client else { return }
        clauntty_mosh_client_send_resize(client, Int32(cols), Int32(rows))
    }
}
