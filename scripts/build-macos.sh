#!/usr/bin/env bash
#
# build-macos.sh — build FMHY for macOS and package it for a GitHub release
#
# The result is an unsigned (ad-hoc signed) FMHY.app inside build/FMHY-macOS.zip.
# macOS will still warn on first launch because the download is quarantined;
# `xattr -dr com.apple.quarantine FMHY.app` clears that.
#
# Environment overrides (used by the release workflow):
#   VERSION_OVERRIDE=1.2          # sets CFBundleShortVersionString
#   BUILD_NUMBER_OVERRIDE=42      # sets CFBundleVersion
#
# Requirements: Xcode 27+ and macOS 14+.

set -euo pipefail

PROJECT="fmhy.xcodeproj"
SCHEME="fmhy"
CONFIGURATION="Release"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/macos"

cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode and run 'xcode-select -s /Applications/Xcode.app'." >&2
  exit 1
fi

VERSION_ARGS=()
if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  VERSION_ARGS+=("MARKETING_VERSION=${VERSION_OVERRIDE#v}")
fi
if [[ -n "${BUILD_NUMBER_OVERRIDE:-}" ]]; then
  VERSION_ARGS+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER_OVERRIDE}")
fi

echo "==> Building FMHY for macOS"
rm -rf "$DERIVED"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  "${VERSION_ARGS[@]}" \
  build

APP_SOURCE="$DERIVED/Build/Products/$CONFIGURATION/$SCHEME.app"
if [[ ! -d "$APP_SOURCE" ]]; then
  echo "error: no .app at $APP_SOURCE" >&2
  exit 1
fi

echo "==> Packaging FMHY.app"
APP="$BUILD_DIR/FMHY.app"
rm -rf "$APP"
cp -R "$APP_SOURCE" "$APP"
xattr -cr "$APP" 2>/dev/null || true
# Apple Silicon won't launch completely unsigned code, so sign ad-hoc.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

ZIP="$BUILD_DIR/FMHY-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "✅ Built $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
echo
echo "Open it with: unzip FMHY-macOS.zip && open FMHY.app"
echo "If Gatekeeper objects to the unsigned build: xattr -dr com.apple.quarantine FMHY.app"
