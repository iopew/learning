#!/bin/bash
# Builds ActivityTracker.app into .build/ActivityTracker.app.
#
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications and (re)start the app
#
# Environment:
#   BUILD_NUMBER=N   CFBundleVersion (CI passes the run number; local builds default to 0, so the app updates itself
#                    to the next published release)
#   SIGN=local       sign with this Mac's stable identity (default; keeps permissions across rebuilds)
#   SIGN=adhoc       ad-hoc signature (CI release builds: they get re-signed on the user's Mac)
#   UNIVERSAL=1      Apple Silicon + Intel (needs full Xcode)
#
# Needs the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

BUILD_NUMBER="${BUILD_NUMBER:-0}"
SIGN="${SIGN:-local}"
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
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/local-sign.sh "$APP/Contents/Resources/local-sign.sh"
chmod +x "$APP/Contents/Resources/local-sign.sh"

# App icon: Resources/AppIcon.png (1024 px) → AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

case "$SIGN" in
    local) bash Resources/local-sign.sh "$APP" ;;
    adhoc) codesign --force --sign - "$APP" ;;
    *) echo "unknown SIGN=$SIGN" >&2; exit 1 ;;
esac
echo "Built $(pwd)/$APP (build $BUILD_NUMBER, signature: $SIGN)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ActivityTracker 2>/dev/null && sleep 1 || true
    rm -rf /Applications/ActivityTracker.app
    ditto "$APP" /Applications/ActivityTracker.app
    open /Applications/ActivityTracker.app
    echo "Installed to /Applications/ActivityTracker.app and started."
fi
