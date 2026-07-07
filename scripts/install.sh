#!/usr/bin/env bash
# Build a Release app, install it to /Applications, ad-hoc sign it, and relaunch.
#
# Deliberately does NOT run "killall Dock" -- restarting the Dock un-minimizes
# every minimized window on macOS. The icon is refreshed via LaunchServices +
# the icon-services cache instead. If the Dock still shows a stale icon, run
# "killall Dock" yourself once, when it's convenient to have minimized windows
# pop back (e.g. right after a login).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_SRC="build/Release/ReclaimDesktop.app"
APP_DST="/Applications/ReclaimDesktop.app"
ENT="ReclaimDesktop/ReclaimDesktop.entitlements"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "[1/5] Building Release..."
xcodebuild -project ReclaimDesktop.xcodeproj -target ReclaimDesktop \
  -configuration Release build CODE_SIGNING_ALLOWED=NO >/dev/null

echo "[2/5] Installing to ${APP_DST}..."
pkill -x ReclaimDesktop 2>/dev/null || true
sleep 1
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"

echo "[3/5] Signing..."
# App Intents / Siri distrust ad-hoc signatures ("couldn't communicate with the
# app"), so prefer a real Apple Development identity if one is available. Pick the
# first codesigning identity's SHA-1 (names can be ambiguous across duplicates).
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/{print $2; exit}')"
if [ -n "${SIGN_ID}" ]; then
  echo "      using development identity ${SIGN_ID}"
  codesign --force --deep --sign "${SIGN_ID}" --entitlements "${ENT}" --options runtime "${APP_DST}"
else
  echo "      no Development identity found -- ad-hoc signing (Siri/Shortcuts may not work)"
  codesign --force --deep --sign - --entitlements "${ENT}" "${APP_DST}"
fi

echo "[4/5] Refreshing icon (no Dock restart)..."
CACHE="$(getconf DARWIN_USER_CACHE_DIR)"
rm -rf "${CACHE}com.apple.iconservices" 2>/dev/null || true
"${LSREGISTER}" -f "${APP_DST}"
killall -HUP iconservicesagent 2>/dev/null || true

# xcodebuild registers the build products with LaunchServices; once we delete
# build/, those become stale registrations that can shadow /Applications and make
# App Intents fail with "couldn't communicate with the app". Unregister them.
"${LSREGISTER}" -u "${PWD}/build/Release/ReclaimDesktop.app" 2>/dev/null || true
"${LSREGISTER}" -u "${PWD}/build/Debug/ReclaimDesktop.app" 2>/dev/null || true
rm -rf build
"${LSREGISTER}" -f "${APP_DST}"   # ensure /Applications is the canonical copy

echo "[5/5] Launching..."
open "${APP_DST}"
echo "Done. If the Dock icon looks stale, run 'killall Dock' once"
echo "(note: that un-minimizes minimized windows)."
