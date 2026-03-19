#!/usr/bin/env bash
set -euo pipefail

# Build, sign, and optionally notarize the Swift migration app binary.
# Usage:
#   scripts/release_macos.sh
# Optional env:
#   CODESIGN_IDENTITY="Developer ID Application: ..."
#   NOTARY_PROFILE="notarytool-profile"
#   TEAM_ID="ABCDE12345"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/.build/release"
ARTIFACT_DIR="$ROOT_DIR/artifacts"
mkdir -p "$ARTIFACT_DIR"

echo "[1/4] Building release binary"
swift build -c release

BIN_PATH="$BUILD_DIR/AIMenu"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Release binary not found: $BIN_PATH" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
PKG_DIR="$ARTIFACT_DIR/AIMenu-$STAMP"
mkdir -p "$PKG_DIR"
cp "$BIN_PATH" "$PKG_DIR/"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "[2/4] Codesigning binary"
  codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$PKG_DIR/AIMenu"
else
  echo "[2/4] Skip codesign (CODESIGN_IDENTITY not set)"
fi

ZIP_PATH="$ARTIFACT_DIR/AIMenu-$STAMP.zip"
echo "[3/4] Packaging zip: $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PKG_DIR" "$ZIP_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "[4/4] Submitting for notarization"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG_DIR/AIMenu" || true
else
  echo "[4/4] Skip notarization (NOTARY_PROFILE not set)"
fi

echo "Done: $ZIP_PATH"
