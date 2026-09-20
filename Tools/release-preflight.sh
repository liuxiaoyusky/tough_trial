#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
cd "$ROOT_DIR"

echo "[1/8] Checking repository for sensitive information"
node Tools/check-sensitive-info.mjs

echo "[2/8] Validating App Store metadata"
node Tools/validate-app-store-metadata.mjs

echo "[3/8] Validating privacy manifest"
plutil -lint Sources/ToughTrialV2App/PrivacyInfo.xcprivacy

echo "[4/8] Running core checks"
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks

echo "[5/8] Building Swift package"
swift build

echo "[6/8] Regenerating Xcode project"
XCODEGEN_BIN=${XCODEGEN_BIN:-$(command -v xcodegen)}
"$XCODEGEN_BIN" generate

echo "[7/8] Building unsigned iPhoneOS Release"
DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/tough-trial-release.XXXXXX")
xcodebuild \
  -quiet \
  -project ToughTrial.xcodeproj \
  -scheme ToughTrial \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[8/8] Inspecting release product"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/ToughTrial.app"
test -f "$APP_PATH/PrivacyInfo.xcprivacy"
test -d "$APP_PATH/PlugIns/ToughTrialLiveActivity.appex"

if rg -a -l \
  "https?://[^[:space:]\"']+\\.feishu\\.cn/base/|/Users/[^/[:space:]]+/Library/Mobile Documents/" \
  "$APP_PATH"
then
  echo "Release product contains a private source marker." >&2
  exit 1
fi

echo "Release preflight passed."
echo "Unsigned product: $APP_PATH"
