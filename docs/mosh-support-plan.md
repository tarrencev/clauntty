# Mosh Support Plan (Official Upstream)

## Goals

- Support Mosh-based terminal connections using the official upstream implementation (`mobile-shell/mosh`).
- Keep sessions usable across network changes (roaming) within a running app session.
- Integrate cleanly with Clauntty's existing session/tab model and GhosttyKit terminal surface.
- Provide GPL-3.0 + third-party notices in-app.

## Non-goals (Current)

- Persisting a Mosh session across app termination (requires securely persisting the session key/port and the server still running).
- Reusing Clauntty's `rtach` session-management features with Mosh (Mosh is already "persistent" over UDP, but it is not `rtach`).
- Port forwarding, image upload, and other SSH-only features for Mosh tabs.

## Architecture

### Connection flow

1. SSH bootstrap (existing SwiftNIO SSH stack):
   - Connect via SSH to the configured host.
   - Determine the *numeric* remote IP from the SSH TCP connection (matches Mosh wrapper behavior).
   - Run `mosh-server new` to obtain:
     - UDP port
     - session key
2. Embedded Mosh client (C++ library):
   - Implement the Mosh UDP protocol using upstream sources.
   - Expose a small C API (`ThirdParty/mosh-support/public/clauntty_mosh.h`).
   - Emit ANSI diffs (ECMA-48 sequences) to the app via callbacks.
3. Swift integration:
   - `MoshClientSession` wraps the C API.
   - Output callback is fed into `Session.handleDirectTerminalOutput(_:)` which updates scrollback + forwards to Ghostty surface.

### Battery / background behavior

- Mosh has no server-side "pause streaming" equivalent of `rtach`.
- Clauntty pauses *rendering* for Mosh sessions (output emission is disabled in the embedded client) while keeping the UDP protocol ticking.
- When output is re-enabled, the embedded client forces a repaint to resynchronize the terminal display.

## Build + Vendoring

- Upstream submodules:
  - `ThirdParty/mosh` (official upstream)
  - `ThirdParty/protobuf` pinned to `v3.20.3` (avoids newer dependency graph)
- Clauntty overlay (not inside the submodule):
  - `ThirdParty/mosh-support/` contains:
    - minimal `config.h` (no autotools)
    - generated protobuf sources for required messages
    - `terminaldisplayinit_no_curses.cc` (no ncurses/terminfo dependency)
    - embedded client wrapper (`clauntty_mosh.cc`)
- Xcode/iOS artifact:
  - `scripts/build-mosh.sh` builds `build/mosh/MoshClient.xcframework`
  - `Frameworks/MoshClient.xcframework` is a symlink to the build artifact
  - App links `libz.tbd` (Mosh uses zlib compression)

## App Integration

- `SavedConnection.transport` selects `SSH` vs `Mosh`.
- UI:
  - Connection creation/editing includes a transport picker.
  - Connection list shows a "Mosh" badge.
- Session plumbing:
  - `SessionManager.connect(...)` bootstraps Mosh via SSH then starts the embedded client.
  - `Session.sendData(...)` and `Session.sendWindowChange(...)` route to Mosh when transport is `.mosh`.
  - Mosh exit/crypto errors transition the session state to `.disconnected`/`.error`.
  - A connect timeout fails fast when UDP is blocked to avoid infinite "Connecting...".

## Legal / Licensing

- Root `LICENSE` is GPL-3.0 (from upstream Mosh).
- `Clauntty/Resources/Licenses/` is bundled and displayed in Settings:
  - `THIRD_PARTY_NOTICES.txt`
  - `LICENSE.txt`

## QA Checklist

1. Basic connect:
   - Connect to a host with `mosh-server` installed.
   - Confirm prompt appears and input works.
2. Roaming:
   - Toggle Wi-Fi off/on, switch Wi-Fi networks, or switch between Wi-Fi and cellular.
   - Session should recover without restarting.
3. Background/foreground:
   - Background the app for 10-30 seconds, then foreground.
   - Output should repaint and remain usable.
4. UDP blocked:
   - Connect to a host where UDP to Mosh ports is blocked.
   - Expect a timeout error with a helpful message (no infinite spinner).
5. Missing `mosh-server`:
   - Connect to a host without `mosh-server`.
   - Expect a clear error.

