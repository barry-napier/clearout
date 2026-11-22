#!/usr/bin/env bash
# Runs the tests. They only touch throwaway folders.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Clearout.xcodeproj -scheme Clearout -configuration Debug \
  -derivedDataPath build/DerivedData -destination "platform=macOS,arch=arm64" test
