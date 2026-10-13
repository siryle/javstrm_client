#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-unsigned}"
case "$mode" in
  unsigned|signed) ;;
  *) printf 'Usage: bash scripts/build_ipa.sh [unsigned|signed]\n' >&2; exit 2 ;;
esac

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  printf 'Full Xcode is required. Install /Applications/Xcode.app and complete its first-launch setup.\n' >&2
  exit 1
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  printf 'The iOS SDK is missing. Add iOS platform support in Xcode Settings > Components.\n' >&2
  exit 1
fi
if [ "$mode" = signed ] && [ -z "${JAVSTRM_DEVELOPMENT_TEAM:-}" ]; then
  printf 'Set JAVSTRM_DEVELOPMENT_TEAM to your Apple Developer Team ID before creating a signed IPA.\n' >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
output_root="$PWD/build/ipa-$stamp"
archive_path="$output_root/JavStrm.xcarchive"
mkdir -p "$output_root"
build_options=(
  -project JavStrm.xcodeproj
  -scheme JavStrm
  -configuration Release
  -destination 'generic/platform=iOS'
  -derivedDataPath "$PWD/DerivedData"
  -archivePath "$archive_path"
)

if [ "$mode" = unsigned ]; then
  xcodebuild "${build_options[@]}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    archive 2>&1 | tee "$output_root/archive.log"
  app_path="$archive_path/Products/Applications/JavStrm.app"
  [ -d "$app_path" ] || { printf 'Archive contains no JavStrm.app.\n' >&2; exit 1; }
  platform="$(plutil -extract DTPlatformName raw -o - "$app_path/Info.plist")"
  [ "$platform" = iphoneos ] || { printf 'Refusing to package a non-device build.\n' >&2; exit 1; }
  xcrun lipo -verify_arch arm64 "$app_path/JavStrm"
  ipa_staging="$(mktemp -d "${TMPDIR:-/tmp}/javstrm-ipa.XXXXXX")"
  trap 'rm -rf "$ipa_staging"' EXIT
  mkdir -p "$ipa_staging/Payload"
  ditto "$app_path" "$ipa_staging/Payload/JavStrm.app"
  ipa_path="$output_root/JavStrm-unsigned.ipa"
  ditto -c -k --keepParent "$ipa_staging/Payload" "$ipa_path"
  python3 scripts/inspect_ipa.py "$ipa_path" --expect-unsigned
  printf '\nUnsigned IPA: %s\nThis package needs iOS signing before installation on a device.\n' "$ipa_path"
else
  team="$JAVSTRM_DEVELOPMENT_TEAM"
  xcodebuild "${build_options[@]}" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
    archive 2>&1 | tee "$output_root/archive.log"
  export_options="$output_root/ExportOptions.plist"
  JAVSTRM_EXPORT_OPTIONS_PATH="$export_options" python3 - <<'PY'
import os
import plistlib
from pathlib import Path
options = {
    "method": os.environ.get("JAVSTRM_EXPORT_METHOD", "debugging"),
    "teamID": os.environ["JAVSTRM_DEVELOPMENT_TEAM"],
    "signingStyle": "automatic",
    "stripSwiftSymbols": True,
}
Path(os.environ["JAVSTRM_EXPORT_OPTIONS_PATH"]).write_bytes(plistlib.dumps(options))
PY
  xcodebuild -exportArchive -archivePath "$archive_path" \
    -exportPath "$output_root/export" -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates 2>&1 | tee "$output_root/export.log"
  ipa_path="$output_root/export/JavStrm.ipa"
  python3 scripts/inspect_ipa.py "$ipa_path" --expect-signed
  printf '\nSigned IPA: %s\n' "$ipa_path"
fi
