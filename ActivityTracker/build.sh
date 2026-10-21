#!/bin/bash
# Builds ActivityTracker.app into .build/ActivityTracker.app.
#
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications and (re)start the app
#
# Needs the Xcode Command Line Tools (xcode-select --install). UNIVERSAL=1 builds for Apple Silicon + Intel
# (requires full Xcode).
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP=".build/ActivityTracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ActivityTracker" "$APP/Contents/MacOS/ActivityTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: enough to run locally and to hold Accessibility / Automation permissions.
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ActivityTracker 2>/dev/null && sleep 1 || true
    rm -rf /Applications/ActivityTracker.app
    ditto "$APP" /Applications/ActivityTracker.app
    open /Applications/ActivityTracker.app
    echo "Installed to /Applications/ActivityTracker.app and started. Look for the clock in the menu bar."
fi
