#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p build
export IMMO_REPOSITORY="$ROOT"
swift test --package-path ios/ImmoCore
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/ImmoFlux.xcodeproj -scheme ImmoFlux \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/build/ImmoFlux.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  archive
APP="$ROOT/build/ImmoFlux.xcarchive/Products/Applications/ImmoFlux.app"
test -f "$APP/ImmoFlux"
/usr/bin/lipo -info "$APP/ImmoFlux"
mkdir -p "$ROOT/build/package/Payload"
ditto "$APP" "$ROOT/build/package/Payload/ImmoFlux.app"
cd "$ROOT/build/package"
ditto -c -k --keepParent Payload "$ROOT/build/ImmoFlux-unsigned.ipa"
unzip -t "$ROOT/build/ImmoFlux-unsigned.ipa"
cd "$ROOT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '## Compilation iOS\n\nIPA arm64 non signée générée. Signature et provisioning nécessaires avant installation.\n' >> "$GITHUB_STEP_SUMMARY"
fi
