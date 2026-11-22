#!/usr/bin/env bash
# Build Clearout, sign it with your stable Apple Development certificate,
# install it to /Applications and relaunch it.
#
# Always use this script. The app path and signature then never change,
# so macOS keeps Full Disk Access across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

# Release by default: a Debug scan is much slower.
CONFIG="${CONFIG:-Release}"
APP_NAME="Clearout"
BUNDLE_ID="com.barrynapier.clearout"
INSTALL_PATH="/Applications/${APP_NAME}.app"
DERIVED="build/DerivedData"
LOCAL_XCCONFIG="Config/Local.xcconfig"

# 1. Team ID for signing, taken from your Apple Development certificate.
if [[ ! -f "$LOCAL_XCCONFIG" ]]; then
  team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
  if [[ -z "${team:-}" ]]; then
    echo "error: no Apple Development certificate found in your keychain." >&2
    exit 1
  fi
  printf '// Local signing settings. Not committed.\nDEVELOPMENT_TEAM = %s\n' "$team" > "$LOCAL_XCCONFIG"
  echo "Created $LOCAL_XCCONFIG"
fi

# 2. Regenerate the Xcode project if XcodeGen is installed.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi

# 3. Build.
echo "Building $APP_NAME ($CONFIG)..."
xcodebuild -project Clearout.xcodeproj -scheme Clearout -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination "platform=macOS,arch=arm64" -quiet build
BUILT="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"

# 4. Refuse ad-hoc builds: they make macOS forget permissions.
codesign --verify --strict "$BUILT"
if codesign -dv "$BUILT" 2>&1 | grep -q "Signature=adhoc"; then
  echo "error: the build is ad-hoc signed. Check your signing certificate." >&2
  exit 1
fi

# 5. Only ever replace a copy of Clearout, never some other app with that name.
if [[ -e "$INSTALL_PATH" ]]; then
  installed=$(plutil -extract CFBundleIdentifier raw "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$installed" != "$BUNDLE_ID" && "$installed" != "local.clearout.launcher" ]]; then
    echo "error: a different app is at $INSTALL_PATH. It was not touched." >&2
    exit 1
  fi
fi

# 6. Quit the running copy, install, relaunch.
pkill -f "^$INSTALL_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
for _ in $(seq 1 50); do
  pgrep -f "^$INSTALL_PATH/Contents/MacOS/$APP_NAME" >/dev/null || break
  sleep 0.1
done
rm -rf "$INSTALL_PATH"
ditto "$BUILT" "$INSTALL_PATH"
open "$INSTALL_PATH"
echo "Installed and launched $INSTALL_PATH"
