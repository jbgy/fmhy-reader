#!/usr/bin/env bash
#
# build-ipa.sh — build FMHY for iPhone and package an .ipa for sideloading
#
# The default build is UNSIGNED, which is what AltStore, SideStore, Sideloadly,
# TrollStore and LiveContainer expect: they re-sign the app with your own
# certificate on install.
#
# Usage:
#   ./scripts/build-ipa.sh                     # unsigned .ipa in build/
#   ./scripts/build-ipa.sh --signed TEAMID     # signed with your Apple team
#
# Environment overrides (used by the release workflow):
#   VERSION_OVERRIDE=1.2          # sets CFBundleShortVersionString
#   BUILD_NUMBER_OVERRIDE=42      # sets CFBundleVersion
#
# Requirements: Xcode 27+ with an iOS SDK. No developer account needed for the
# unsigned build.

set -euo pipefail

PROJECT="fmhy.xcodeproj"
SCHEME="fmhy"
CONFIGURATION="Release"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/FMHY.xcarchive"
STAGE_DIR="$BUILD_DIR/ipa-stage"

cd "$(dirname "$0")/.."

MODE="unsigned"
TEAM_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --signed)
      MODE="signed"
      TEAM_ID="${2:?--signed needs a DEVELOPMENT_TEAM id, e.g. ABCDE12345}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode and run 'xcode-select -s /Applications/Xcode.app'." >&2
  exit 1
fi

echo "==> Cleaning previous artefacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

VERSION_ARGS=()
if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  VERSION_ARGS+=("MARKETING_VERSION=${VERSION_OVERRIDE#v}")
fi
if [[ -n "${BUILD_NUMBER_OVERRIDE:-}" ]]; then
  VERSION_ARGS+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER_OVERRIDE}")
fi

SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
if [[ "$MODE" == "signed" ]]; then
  echo "==> Archiving with automatic signing for team $TEAM_ID"
  SIGN_ARGS=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
else
  echo "==> Archiving unsigned (sideloading tools will re-sign on install)"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  "${SIGN_ARGS[@]}" \
  "${VERSION_ARGS[@]}" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  # Fall back to any app inside the archive's Applications folder.
  APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "error: no .app found in the archive at $ARCHIVE_PATH/Products/Applications" >&2
  exit 1
fi

echo "==> Packaging $(basename "$APP_PATH")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist" 2>/dev/null || echo "1.0")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist" 2>/dev/null || echo "1")"

mkdir -p "$STAGE_DIR/Payload"
cp -R "$APP_PATH" "$STAGE_DIR/Payload/"

# Strip extended attributes that confuse some sideloading tools.
xattr -cr "$STAGE_DIR/Payload" 2>/dev/null || true

IPA_PATH="$BUILD_DIR/FMHY-${VERSION}-${BUILD_NUMBER}-${MODE}.ipa"
(
  cd "$STAGE_DIR"
  /usr/bin/zip -qry "$OLDPWD/$IPA_PATH" Payload
)

rm -rf "$STAGE_DIR"

SIZE="$(du -h "$IPA_PATH" | cut -f1 | tr -d ' ')"
echo
echo "✅ Built $IPA_PATH ($SIZE)"
echo
echo "Install it with:"
echo "  • AltStore / SideStore: open the .ipa from Files or the app's + button"
echo "  • Sideloadly: drag the .ipa in, sign in with your Apple ID"
echo "  • TrollStore: open the .ipa with TrollStore installed"
echo
echo "Note: unsigned .ipa files must be re-signed by the tool you use."
