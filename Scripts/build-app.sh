#!/bin/bash
# Assembles dist/Quintile.app from the SPM release build.
#
# Why a script and not an Xcode target: a bare `swift build` binary cannot
# carry LSUIElement, hold a TCC Accessibility grant across launches, or
# register via SMAppService — those all key off a bundled, identified app.
# This script produces that bundle without requiring full Xcode (Command
# Line Tools are enough). Contributors with Xcode can generate an app
# target instead; the Info.plist here is the source of truth either way.
#
# Signing: ad-hoc by default (good for local use). For distribution, set
# CODESIGN_IDENTITY to a "Developer ID Application: ..." identity and
# notarize the result — Gatekeeper blocks unsigned downloads, and a stable
# signing identity is what keeps the Accessibility grant valid across
# updates (see README > Releasing).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_DIR="dist/Quintile.app"

echo "▸ swift build -c ${CONFIGURATION}"
swift build -c "${CONFIGURATION}" --product QuintileApp

BIN="$(swift build -c "${CONFIGURATION}" --show-bin-path)/QuintileApp"

echo "▸ assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/Quintile"
cp Scripts/Info.plist "${APP_DIR}/Contents/Info.plist"

echo "▸ codesign (identity: ${CODESIGN_IDENTITY})"
# Hardened runtime is required for notarization but pointless (and stricter than
# needed) for an ad-hoc "-" signature, so only enable it for a real Developer ID.
if [ "${CODESIGN_IDENTITY}" = "-" ]; then
  codesign --force --sign - "${APP_DIR}"
else
  codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
fi

echo "✓ built ${APP_DIR}"
