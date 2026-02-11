#!/usr/bin/env bash
# Build, install, and launch Clauntty on a connected iOS device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT="Clauntty.xcodeproj"
SCHEME="Clauntty"
CONFIGURATION="Debug"
BUNDLE_ID="com.octerm.clauntty"
DEVICE_NAME=""
TEAM_ID=""
ALLOW_PROVISIONING_UPDATES=1

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  cat <<USAGE
Usage: $0 --device "<device name>" [options]

Required:
  --device <name>            Device name shown by xcrun devicectl (for example: "tarrence")

Options:
  --project <path>           Xcode project (default: $PROJECT)
  --scheme <name>            Xcode scheme (default: $SCHEME)
  --configuration <name>     Build configuration (default: $CONFIGURATION)
  --bundle-id <id>           App bundle id to launch (default: $BUNDLE_ID)
  --team-id <id>             Apple Developer Team ID for signing (optional)
  --no-provisioning-updates  Disable -allowProvisioningUpdates during build
  -h, --help                 Show this help

Example:
  $0 --device "tarrence"
USAGE
}

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_NAME="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --no-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$DEVICE_NAME" ]]; then
  usage
  fail "Missing required argument: --device"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild not found"
fi

if ! command -v xcrun >/dev/null 2>&1; then
  fail "xcrun not found"
fi

cd "$PROJECT_DIR"

DESTINATION="platform=iOS,name=${DEVICE_NAME}"

log "Building ${SCHEME} for device \"${DEVICE_NAME}\"..."
BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
  -quiet
)
if [[ "$ALLOW_PROVISIONING_UPDATES" -eq 1 ]]; then
  BUILD_ARGS+=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
fi
BUILD_ARGS+=("PRODUCT_BUNDLE_IDENTIFIER=${BUNDLE_ID}" "CODE_SIGN_STYLE=Automatic")
if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=("DEVELOPMENT_TEAM=${TEAM_ID}")
fi
xcodebuild "${BUILD_ARGS[@]}" build
ok "Build complete"

log "Resolving built app path..."
BUILD_SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)"
TARGET_BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $2; exit}')"
FULL_PRODUCT_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')"

if [[ -z "$TARGET_BUILD_DIR" || -z "$FULL_PRODUCT_NAME" ]]; then
  fail "Unable to determine build output path from xcodebuild settings"
fi

APP_PATH="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"

if [[ ! -d "$APP_PATH" ]]; then
  fail "Built app not found at: $APP_PATH"
fi

log "Installing app on \"${DEVICE_NAME}\"..."
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP_PATH" >/dev/null
ok "Install complete"

log "Launching ${BUNDLE_ID} on \"${DEVICE_NAME}\"..."
xcrun devicectl device process launch --device "$DEVICE_NAME" "$BUNDLE_ID" >/dev/null
ok "Launch complete"

ok "Deploy finished"
