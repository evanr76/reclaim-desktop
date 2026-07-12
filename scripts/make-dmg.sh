#!/usr/bin/env bash
# Build a Release app and package it into a distributable .dmg with a drag-to-
# Applications layout. Output: dist/ReclaimDesktop-<version>.dmg
#
# Two modes:
#   ./scripts/make-dmg.sh              Local build. Signs with an available
#                                      identity; runs on THIS Mac, but other
#                                      Macs will see Gatekeeper warnings.
#
#   NOTARIZE=1 ./scripts/make-dmg.sh   Distributable build. Signs with a
#                                      "Developer ID Application" cert, submits
#                                      to Apple's notary service, and staples
#                                      the ticket -> runs cleanly on any Mac.
#
# NOTARIZE=1 prerequisites (one-time, see README "Building a release"):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. A stored notary credential profile. Its name defaults to "reclaim-notary";
#      override with NOTARY_PROFILE=<name>.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="Release"
APP_NAME="ReclaimDesktop"
VOL_NAME="Reclaim Desktop"
BUILD_APP="build/${CONFIG}/${APP_NAME}.app"
ENT="ReclaimDesktop/ReclaimDesktop.entitlements"
DIST="dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-reclaim-notary}"

devid_identity() { security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}'; }
devel_identity() { security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}'; }

echo "[1/5] Building ${CONFIG}..."
xcodebuild -project ReclaimDesktop.xcodeproj -target "${APP_NAME}" \
  -configuration "${CONFIG}" build CODE_SIGNING_ALLOWED=NO >/dev/null

echo "[2/5] Signing app..."
if [ "${NOTARIZE}" = "1" ]; then
  DEVID="$(devid_identity)"
  [ -n "${DEVID}" ] || { echo "ERROR: NOTARIZE=1 needs a 'Developer ID Application' certificate (none found). See README."; exit 1; }
  echo "      Developer ID: ${DEVID} (hardened runtime + timestamp)"
  # Sign nested code first, then the app bundle (avoid --deep for notarization).
  if [ -d "${BUILD_APP}/Contents/Frameworks" ]; then
    find "${BUILD_APP}/Contents/Frameworks" -type f -print0 | while IFS= read -r -d '' f; do
      codesign --force --options runtime --timestamp --sign "${DEVID}" "${f}"
    done
  fi
  codesign --force --options runtime --timestamp --sign "${DEVID}" --entitlements "${ENT}" "${BUILD_APP}"
else
  ID="$(devid_identity)"; [ -n "${ID}" ] || ID="$(devel_identity)"
  if [ -n "${ID}" ]; then
    echo "      local identity ${ID}"
    codesign --force --deep --options runtime --sign "${ID}" --entitlements "${ENT}" "${BUILD_APP}"
  else
    echo "      ad-hoc (recipients will hit Gatekeeper)"
    codesign --force --deep --sign - --entitlements "${ENT}" "${BUILD_APP}"
  fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${BUILD_APP}/Contents/Info.plist" 2>/dev/null || echo "0.0")"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"

echo "[3/5] Staging (app + /Applications symlink)..."
cp -R "${BUILD_APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

echo "[4/5] Creating ${DMG}..."
mkdir -p "${DIST}"
rm -f "${DMG}"
hdiutil create -volname "${VOL_NAME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null

if [ "${NOTARIZE}" = "1" ]; then
  echo "[5/5] Signing + notarizing DMG (profile: ${NOTARY_PROFILE})..."
  codesign --force --timestamp --sign "$(devid_identity)" "${DMG}"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}" && echo "Stapled + validated."
  spctl -a -vvv --type install "${DMG}" 2>&1 | sed 's/^/      /' || true
else
  echo "[5/5] Skipping notarization (local build)."
fi

rm -rf build
echo "Done -> ${DMG}"
du -h "${DMG}" | awk '{print "Size: " $1}'
