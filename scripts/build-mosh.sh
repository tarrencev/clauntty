#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

MOSH_DIR="$REPO_ROOT/ThirdParty/mosh"
PROTOBUF_DIR="$REPO_ROOT/ThirdParty/protobuf"
SUPPORT_DIR="$REPO_ROOT/ThirdParty/mosh-support"

OUT_DIR="$REPO_ROOT/build/mosh"
HEADERS_DIR="$SUPPORT_DIR/public"
XCFRAMEWORK_OUT="$OUT_DIR/MoshClient.xcframework"
XCFRAMEWORK_SYMLINK="$REPO_ROOT/Frameworks/MoshClient.xcframework"

log() { echo "[build-mosh] $*"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required (run this on macOS with Xcode installed)." >&2
  exit 1
fi

if [ ! -d "$MOSH_DIR/src" ]; then
  echo "Missing submodule: ThirdParty/mosh" >&2
  exit 1
fi

if [ ! -d "$PROTOBUF_DIR/src" ]; then
  echo "Missing submodule: ThirdParty/protobuf" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

PROTOBUF_SRCS=()
while IFS= read -r p; do
  PROTOBUF_SRCS+=("$p")
done < <(
  python3 - <<'PY'
import re, pathlib
root = pathlib.Path("ThirdParty/protobuf")
paths=[]
text=(root/"cmake/libprotobuf-lite.cmake").read_text()
for m in re.finditer(r"\$\{protobuf_source_dir\}/src/([^\s\)]+\.cc)", text):
    p = root/"src"/m.group(1)
    # Skip Windows-only sources when building for Apple platforms.
    if p.name == "io_win32.cc":
        continue
    paths.append(str(p))
seen=set(); out=[]
for p in paths:
    if p not in seen:
        seen.add(p)
        out.append(p)
print("\n".join(out))
PY
  )

# Mosh + Clauntty wrapper sources (client-only subset; no ncurses frontend).
MOSH_SRCS=(
  "ThirdParty/mosh/src/util/timestamp.cc"
  "ThirdParty/mosh/src/crypto/base64.cc"
  "ThirdParty/mosh/src/crypto/crypto.cc"
  "ThirdParty/mosh/src/crypto/ocb_internal.cc"
  "ThirdParty/mosh/src/network/compressor.cc"
  "ThirdParty/mosh/src/network/network.cc"
  "ThirdParty/mosh/src/network/transportfragment.cc"
  "ThirdParty/mosh/src/statesync/user.cc"
  "ThirdParty/mosh/src/statesync/completeterminal.cc"
  "ThirdParty/mosh/src/terminal/parser.cc"
  "ThirdParty/mosh/src/terminal/parseraction.cc"
  "ThirdParty/mosh/src/terminal/parserstate.cc"
  "ThirdParty/mosh/src/terminal/terminal.cc"
  "ThirdParty/mosh/src/terminal/terminaldispatcher.cc"
  "ThirdParty/mosh/src/terminal/terminalframebuffer.cc"
  "ThirdParty/mosh/src/terminal/terminalfunctions.cc"
  "ThirdParty/mosh/src/terminal/terminaluserinput.cc"
  "ThirdParty/mosh/src/terminal/terminaldisplay.cc"
  "ThirdParty/mosh-support/src/terminaldisplayinit_no_curses.cc"
  "ThirdParty/mosh-support/src/clauntty_mosh.cc"
  "ThirdParty/mosh-support/generated/src/protobufs/hostinput.pb.cc"
  "ThirdParty/mosh-support/generated/src/protobufs/userinput.pb.cc"
  "ThirdParty/mosh-support/generated/src/protobufs/transportinstruction.pb.cc"
)

INCLUDES=(
  "$REPO_ROOT/ThirdParty/mosh-support/include"
  "$REPO_ROOT/ThirdParty/mosh-support/generated"
  "$REPO_ROOT/ThirdParty/mosh-support/public"
  "$REPO_ROOT/ThirdParty/mosh"
  "$REPO_ROOT/ThirdParty/protobuf/src"
)

compile_one() {
  local sdk="$1"
  local arch="$2"
  local objdir="$3"

  local cxx
  cxx="$(xcrun --sdk "$sdk" --find clang++)"

  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  mkdir -p "$objdir"

  local common_flags=(
    -std=c++17
    -O2
    -DNDEBUG
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -fno-omit-frame-pointer
    -arch "$arch"
    -isysroot "$sysroot"
  )

  for inc in "${INCLUDES[@]}"; do
    common_flags+=("-I$inc")
  done

  # Build protobuf runtime sources
  for src in "${PROTOBUF_SRCS[@]}"; do
    local obj
    obj="$(echo "$src" | sed 's#[/ ]#_#g')"
    "$cxx" "${common_flags[@]}" -c "$REPO_ROOT/$src" -o "$objdir/$obj.o"
  done

  # Build Mosh + wrapper sources
  for src in "${MOSH_SRCS[@]}"; do
    local obj
    obj="$(echo "$src" | sed 's#[/ ]#_#g')"
    "$cxx" "${common_flags[@]}" -c "$REPO_ROOT/$src" -o "$objdir/$obj.o"
  done
}

libtool_static() {
  local out="$1"
  shift
  /usr/bin/libtool -static -o "$out" "$@"
}

log "Building device (iphoneos arm64)..."
OBJ_DEVICE="$OUT_DIR/obj-iphoneos-arm64"
compile_one iphoneos arm64 "$OBJ_DEVICE"
libtool_static "$OUT_DIR/libmoshclient-iphoneos.a" "$OBJ_DEVICE"/*.o

log "Building simulator (iphonesimulator arm64 + x86_64)..."
OBJ_SIM_ARM64="$OUT_DIR/obj-iphonesimulator-arm64"
compile_one iphonesimulator arm64 "$OBJ_SIM_ARM64"
libtool_static "$OUT_DIR/libmoshclient-sim-arm64.a" "$OBJ_SIM_ARM64"/*.o

OBJ_SIM_X86_64="$OUT_DIR/obj-iphonesimulator-x86_64"
compile_one iphonesimulator x86_64 "$OBJ_SIM_X86_64"
libtool_static "$OUT_DIR/libmoshclient-sim-x86_64.a" "$OBJ_SIM_X86_64"/*.o

log "Lipo simulator static libs..."
lipo -create \
  "$OUT_DIR/libmoshclient-sim-arm64.a" \
  "$OUT_DIR/libmoshclient-sim-x86_64.a" \
  -output "$OUT_DIR/libmoshclient-iphonesimulator.a"

log "Creating xcframework..."
rm -rf "$XCFRAMEWORK_OUT"
xcodebuild -create-xcframework \
  -library "$OUT_DIR/libmoshclient-iphoneos.a" -headers "$HEADERS_DIR" \
  -library "$OUT_DIR/libmoshclient-iphonesimulator.a" -headers "$HEADERS_DIR" \
  -output "$XCFRAMEWORK_OUT"

log "Built: $XCFRAMEWORK_OUT"
log "Updating symlink: $XCFRAMEWORK_SYMLINK -> ../build/mosh/MoshClient.xcframework"
rm -rf "$XCFRAMEWORK_SYMLINK"
ln -s "../build/mosh/MoshClient.xcframework" "$XCFRAMEWORK_SYMLINK"
log "Note: the app target must also link system zlib (libz) (Mosh uses zlib for compression)."
