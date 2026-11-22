#!/usr/bin/env bash
# Builds a release of Clearout: tested, signed with Developer ID, checked by
# Apple (notarized) and packed in a DMG. Nothing is published unless you pass
# --publish.
#
#   ./scripts/release.sh 0.1.0                   build everything on this Mac
#   ./scripts/release.sh 0.1.0 --skip-notarize   practice, no upload to Apple
#   ./scripts/release.sh 0.1.0 --publish         also create the GitHub release
#
# One-time setup (saves your Apple login in the keychain):
#   xcrun notarytool store-credentials clearout-notary \
#     --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
#
# The login can come from the environment instead:
#   TEAM_ID, NOTARY_APPLE_ID, NOTARY_PASSWORD
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh VERSION [--skip-notarize] [--publish]}"
shift
VERSION="${VERSION#v}"
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done
fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the version must look like 1.2.3."
[[ $PUBLISH == 1 && $NOTARIZE == 0 ]] && fail "never publish a build that Apple has not checked."

REPO="barry-napier/clearout"
NOTARY_PROFILE="clearout-notary"
IDENTITY="Developer ID Application"
OUT="build/release/$VERSION"
APP="$OUT/export/Clearout.app"
DMG="$OUT/Clearout-$VERSION.dmg"

# 1. Everything that can stop a release, before the slow work starts.
[[ -z "$(git status --porcelain)" ]] || fail "commit your changes first, so the release matches a commit."
if [[ $PUBLISH == 1 ]]; then
  git fetch -q origin --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "push this commit to main first."
  if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    fail "v$VERSION is already out. Pick a higher version."
  fi
  if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    [[ "$(git rev-list -n1 "v$VERSION")" == "$(git rev-parse HEAD)" ]] || fail "v$VERSION points at another commit."
  fi
fi
if [[ -z "${TEAM_ID:-}" ]]; then
  TEAM_ID=$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1) || true
fi
[[ -n "${TEAM_ID:-}" ]] || fail "no $IDENTITY certificate found in your keychain."
if [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
  NOTARY_AUTH=(--apple-id "$NOTARY_APPLE_ID" --password "${NOTARY_PASSWORD:?NOTARY_PASSWORD is not set}" --team-id "$TEAM_ID")
else
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi
if [[ $NOTARIZE == 1 ]] && ! xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1; then
  echo "error: Apple did not accept the login. To save one on this Mac:" >&2
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id YOUR_APPLE_ID --team-id $TEAM_ID" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
BUILD_NUMBER=$(git rev-list --count HEAD)

step "Running the tests"
./scripts/test.sh > "$OUT/test.log" 2>&1 || { tail -30 "$OUT/test.log" >&2; fail "the tests failed."; }
[[ -z "$(git status --porcelain)" ]] || fail "XcodeGen changed the project. Commit that, then run this again."

# The signing settings live here, so build.sh keeps working without a Developer ID.
step "Archiving Clearout $VERSION (build $BUILD_NUMBER)"
xcodebuild -project Clearout.xcodeproj -scheme Clearout -configuration Release \
  -derivedDataPath build/ReleaseData -archivePath "$OUT/Clearout.xcarchive" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet archive

step "Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingCertificate</key><string>$IDENTITY</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Clearout.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" -quiet

step "Checking the app"
BINARY="$APP/Contents/MacOS/Clearout"
codesign --verify --deep --strict "$APP"
SIGN_INFO=$(codesign -dvv "$APP" 2>&1)
grep -q "Authority=$IDENTITY" <<<"$SIGN_INFO" || fail "not signed with Developer ID."
grep -qE "flags=.*runtime" <<<"$SIGN_INFO" || fail "the hardened runtime is off."
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null || true)
[[ "$ENTITLEMENTS" != *get-task-allow* ]] || fail "the app still allows debugging."
for arch in arm64 x86_64; do
  lipo "$BINARY" -verify_arch "$arch" || fail "the app has no $arch part."
  # Apple's AI does not exist on macOS 15. A hard link to it would crash there.
  LINKS=$(otool -arch "$arch" -L "$BINARY")
  if grep "FoundationModels" <<<"$LINKS" | grep -qv "weak"; then
    fail "FoundationModels must be weak linked, or macOS 15 cannot open the app."
  fi
done
SYMBOLS=$(strings - "$BINARY")
[[ "$SYMBOLS" != *--selftest* ]] || fail "the self test is in the release build."

if [[ $NOTARIZE == 1 ]]; then
  step "Apple checks the app (this can take a few minutes)"
  ditto -c -k --keepParent "$APP" "$OUT/Clearout.zip"
  xcrun notarytool submit "$OUT/Clearout.zip" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$APP"
fi

step "Making the DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Clearout.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Clearout" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"
hdiutil verify "$DMG" -quiet
rm -rf "$STAGE"

if [[ $NOTARIZE == 1 ]]; then
  step "Apple checks the DMG"
  xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$DMG"
  step "Checking that a Mac will open it"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  spctl --assess --type execute --verbose "$APP"
fi

echo
echo "Done: $DMG"

if [[ $PUBLISH == 1 ]]; then
  step "Publishing v$VERSION on GitHub"
  git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || git tag -a "v$VERSION" -m "Clearout $VERSION"
  git push origin "v$VERSION"
  # The same file under a name that never changes, for the website's Download
  # button: releases/latest/download/Clearout.dmg always serves the newest one.
  STABLE_DMG="$OUT/Clearout.dmg"
  cp "$DMG" "$STABLE_DMG"
  gh release create "v$VERSION" "$DMG" "$STABLE_DMG" --repo "$REPO" \
    --title "Clearout $VERSION" --verify-tag --generate-notes \
    --notes "Download **Clearout.dmg**, open it, and drag Clearout to Applications. It needs macOS 15 or newer."
else
  echo
  echo "Not published. To publish: ./scripts/release.sh $VERSION --publish"
fi
