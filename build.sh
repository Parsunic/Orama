#!/usr/bin/env bash
# Builds Glance.app from source and opens it.
#
#   ./build.sh            build into ./build/Glance.app and open it
#   ./build.sh --install  also copy it to /Applications (needed for "Open at login")
#
# Needs Xcode or the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

echo "Building…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Glance.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Glance" "$APP/Contents/MacOS/Glance"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign it. macOS remembers the Screen Recording permission (and Keychain
# access) by signature. With an "Apple Development" certificate the signature
# stays the same between builds, so you grant permission once. Without one we
# sign "ad hoc", which works, but macOS treats every rebuild as a new app and
# asks again.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
# A self-signed certificate named "Glance Signing" (made once in Keychain
# Access, see README) works just as well for keeping permissions between builds.
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Glance Signing"'; then
  IDENTITY="Glance Signing"
fi
if [ -n "$IDENTITY" ]; then
  echo "Signing with: $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  echo "No developer certificate found; signing ad hoc."
  echo "(You'll need to re-allow Screen Recording after each rebuild.)"
  codesign --force --sign - "$APP"
fi

echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Glance 2>/dev/null || true
  rm -rf /Applications/Glance.app
  cp -R "$APP" /Applications/
  open /Applications/Glance.app
  echo "Installed to /Applications/Glance.app"
else
  pkill -x Glance 2>/dev/null || true
  open "$APP"
fi
