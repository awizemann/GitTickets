#!/usr/bin/env bash
#
# Builds and runs the iOS refresh-affordance harness on a booted simulator.
#
# This one cannot be a SwiftPM target: SwiftPM does not build iOS simulator app
# bundles, so the app is compiled with swiftc and installed with simctl.
#
# Usage:  ./run-ios-harness.sh [device-udid]
#         (defaults to the currently booted device)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/.build-ios"
APP="$BUILD/RefreshHarness.app"
BUNDLE_ID="com.wizemann.RefreshHarness"
DEVICE="${1:-booted}"

if [ "$DEVICE" = "booted" ] && ! xcrun simctl list devices booted | grep -q Booted; then
  echo "No booted simulator. Boot one first, e.g.:" >&2
  echo "  xcrun simctl boot 'iPhone 17 Pro'" >&2
  exit 1
fi

echo "==> Compiling"
rm -rf "$APP"
mkdir -p "$APP"
xcrun -sdk iphonesimulator swiftc \
  -target arm64-apple-ios18.0-simulator \
  -parse-as-library \
  -o "$APP/RefreshHarness" \
  "$HERE/main.swift"

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RefreshHarness</string>
    <key>CFBundleIdentifier</key><string>com.wizemann.RefreshHarness</string>
    <key>CFBundleName</key><string>RefreshHarness</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>MinimumOSVersion</key><string>18.0</string>
    <key>UIDeviceFamily</key><array><integer>1</integer></array>
    <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST

echo "==> Installing"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

echo "==> Running (scan prints below, and is also drawn on screen)"
xcrun simctl launch --console-pty "$DEVICE" "$BUNDLE_ID" 2>&1 | grep -E '^SCAN' &
LAUNCH_PID=$!
sleep 8
kill "$LAUNCH_PID" 2>/dev/null || true

SHOT="$BUILD/scan.png"
xcrun simctl io "$DEVICE" screenshot --type=png "$SHOT" >/dev/null 2>&1
echo "==> Screenshot: $SHOT"
echo
echo "Expected: YES for BOTH the ScrollView and the List — on iOS, .refreshable"
echo "installs a UIRefreshControl on a plain ScrollView. That is the opposite of"
echo "macOS; see ../../README.md."
