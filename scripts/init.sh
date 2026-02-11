#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
LIBXEV_DIR="$REPO_ROOT/libxev"
LIBXEV_REPO="${LIBXEV_REPO:-https://github.com/mitchellh/libxev.git}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
  echo -e "${BLUE}$1${NC}"
}

ok() {
  echo -e "${GREEN}$1${NC}"
}

fail() {
  echo -e "${RED}$1${NC}"
  exit 1
}

if ! command -v git >/dev/null 2>&1; then
  fail "git is required but not found on PATH."
fi

if ! command -v asdf >/dev/null 2>&1; then
  fail "asdf is required but not found on PATH. Install asdf first: https://asdf-vm.com/"
fi

log "Initializing git submodules (ghostty, rtach)..."
git -C "$REPO_ROOT" submodule update --init --recursive ghostty rtach
ok "Submodules ready"

if [ ! -d "$LIBXEV_DIR" ]; then
  log "libxev not found at $LIBXEV_DIR; cloning from $LIBXEV_REPO..."
  git -C "$REPO_ROOT" clone "$LIBXEV_REPO" "$LIBXEV_DIR"
fi
ok "libxev ready"

log "Ensuring asdf has zig ${ZIG_VERSION}..."
if ! asdf plugin list | grep -qx zig; then
  asdf plugin add zig
fi

if ! asdf where zig "$ZIG_VERSION" >/dev/null 2>&1; then
  asdf install zig "$ZIG_VERSION"
fi
ok "Zig ${ZIG_VERSION} ready"

log "Building GhosttyKit framework..."
(
  cd "$REPO_ROOT/ghostty"
  ASDF_ZIG_VERSION="$ZIG_VERSION" asdf exec zig build -Demit-xcframework -Demit-macos-app=false -Doptimize=ReleaseFast
)
ok "GhosttyKit build complete"

log "Building rtach binaries..."
(
  cd "$REPO_ROOT/rtach"
  ASDF_ZIG_VERSION="$ZIG_VERSION" asdf exec zig build cross
)
ok "rtach build complete"

ok "Init complete"
