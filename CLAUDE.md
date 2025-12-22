# Clauntty - iOS SSH Terminal with Ghostty

iOS SSH terminal using **libghostty** for GPU-accelerated rendering + **SwiftNIO SSH** for connections.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Views          GhosttyBridge         SwiftNIO SSH  │
│  ┌──────────────┐      ┌─────────────┐      ┌────────────┐  │
│  │ Terminal UI  │◄────►│ Local PTY   │◄────►│ SSH Channel│  │
│  │ + Keyboard   │      │ (bridge)    │      │ (remote)   │  │
│  └──────────────┘      └─────────────┘      └────────────┘  │
│         │                     │                    │        │
│         ▼                     ▼                    ▼        │
│  GhosttyKit.xcframework      PTY master     Remote Server   │
│  (Metal rendering)           ◄─────►                        │
└─────────────────────────────────────────────────────────────┘
```

**PTY Bridge**: iOS can't fork shells (sandbox), but CAN create PTYs. Bridge redirects SSH ↔ PTY.

## Repository Layout

```
~/Projects/clauntty/
├── clauntty/          # iOS app (this repo)
├── ghostty/           # Forked ghostty (git@github.com:eriklangille/ghostty.git)
└── libxev/            # Local libxev fork (iOS fixes)
```

## Key Files

| Location | Purpose |
|----------|---------|
| `../ghostty/include/ghostty.h` | C API header |
| `../ghostty/src/termio/Exec.zig` | iOS process/PTY handling |
| `../ghostty/src/renderer/Metal.zig` | Metal renderer |
| `../libxev/src/backend/kqueue.zig` | Event loop (iOS fixes) |
| `Clauntty/Core/Terminal/` | GhosttyApp, TerminalSurface, GhosttyBridge |
| `Clauntty/Core/SSH/` | SSHConnection, SSHAuthenticator |

## Build Commands

```bash
# Build GhosttyKit (after ghostty changes)
cd ../ghostty && zig build -Demit-xcframework

# Build Clauntty
xcodebuild -project Clauntty.xcodeproj -scheme Clauntty \
  -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build

# Run in simulator
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Clauntty-*/Build/Products/Debug-iphonesimulator/Clauntty.app
xcrun simctl launch booted com.clauntty.app

# Run tests
xcodebuild test -project Clauntty.xcodeproj -scheme ClaunttyTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Logging & Debugging

```bash
# Stream app logs
xcrun simctl spawn booted log stream --level=info \
  --predicate 'subsystem == "com.clauntty" OR subsystem == "com.mitchellh.ghostty"'

# View recent logs
xcrun simctl spawn booted log show --predicate 'subsystem == "com.clauntty"' --last 5m

# Screenshot
xcrun simctl io booted screenshot /tmp/clauntty.png

# Parse crash reports
uv run scripts/parse_crash.py --latest        # Formatted view
uv run scripts/parse_crash.py --raw --latest  # Raw stack trace
```

## GhosttyKit API

```c
// Init (MUST call ghostty_init() first!)
ghostty_app_t ghostty_app_new(ghostty_runtime_config_s*, ghostty_config_t);
ghostty_surface_t ghostty_surface_new(ghostty_app_t, ghostty_surface_config_s*);

// Lifecycle
void ghostty_app_tick(ghostty_app_t);
void ghostty_surface_set_size(ghostty_surface_t, uint32_t w, uint32_t h);
void ghostty_surface_set_focus(ghostty_surface_t, bool);

// Input
void ghostty_surface_key(ghostty_surface_t, ghostty_input_key_s);
void ghostty_surface_text(ghostty_surface_t, const char*, size_t);
```

## Current Status

**Working:**
- Terminal surface rendering (Metal) ✓
- PTY creation on iOS ✓
- GhosttyKit initialization ✓
- Connection list UI ✓

**TODO:**
- [ ] Wire keyboard input to surface
- [ ] Wire SSH connection
- [ ] Connect SSH ↔ Terminal data flow

## iOS Fixes Applied

### libxev mach_port Fix
**File**: `../libxev/src/backend/kqueue.zig`

Changed `.macos` checks to `.isDarwin()` to include iOS:
```zig
// Line 957 & 1073: .macos → .isDarwin()
```

ghostty's `build.zig.zon` uses local libxev: `.path = "../libxev"`

### Ghostty Exec.zig
**File**: `../ghostty/src/termio/Exec.zig`

- Skip process spawn on iOS (sandbox restriction)
- PTY created for external data source (SSH bridge)

### Metal.zig
**File**: `../ghostty/src/renderer/Metal.zig` line 127

- Fixed selector: `addSublayer` → `addSublayer:` (needs colon for ObjC parameter)

## Key Info

- **Bundle ID**: `com.clauntty.app`
- **iOS target**: 17.0+
- **Zig version**: 0.15.2+
- **Dependencies**: swift-nio-ssh 0.12.0, swift-nio 2.92.0
- Metal tests require simulator (headless XCTest won't work)

## Visual Testing

Golden screenshot comparison for rendering validation:

```bash
# Capture screenshot
xcrun simctl io booted screenshot /tmp/clauntty_actual.png

# Compare with golden (ImageMagick)
compare -metric AE /tmp/clauntty_actual.png Tests/Golden/terminal_empty.png null: 2>&1

# Generate diff image if pixels differ
compare /tmp/clauntty_actual.png Tests/Golden/terminal_empty.png /tmp/diff.png

# Update golden after intentional changes
xcrun simctl io booted screenshot Tests/Golden/terminal_empty.png
```

Store goldens in `Tests/Golden/` (e.g., `terminal_empty.png`, `terminal_colors.png`).

**Note**: Metal rendering only works in simulator, not headless XCTest.

## SSH Testing

Enable on Mac: System Settings > General > Sharing > Remote Login

In simulator, connect to `localhost:22` with your Mac username.
