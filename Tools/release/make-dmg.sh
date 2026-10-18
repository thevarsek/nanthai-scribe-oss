#!/bin/bash
set -euo pipefail
identity=${1:-${SIGN_ID:?Pass a signing identity or set SIGN_ID}}
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
layout_package="$root/Tools/release/dmg-layout"
layout_build="$root/build/dmg-layout"
swift build --package-path "$layout_package" --scratch-path "$layout_build" -c release -j 4
layout_bin=$(swift build --package-path "$layout_package" --scratch-path "$layout_build" -c release -j 4 --show-bin-path)
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "build/NanthAi Scribe.app/Contents/Info.plist")
dmg="$root/build/NanthAi-Scribe-$version.dmg"
rw="$root/build/NanthAi-Scribe-rw.dmg"
stage="$root/build/dmg-stage"
mount=""
mount_info="$root/build/dmg-mount.plist"
mounted=false
cleanup() {
    if $mounted; then hdiutil detach "$mount" >/dev/null; fi
    rm -rf "$stage" "$rw" "$mount_info"
}
trap cleanup EXIT
rm -rf "$stage" "$rw" "$dmg"
mkdir -p "$stage/.background"
ditto "build/NanthAi Scribe.app" "$stage/NanthAi Scribe.app"
ln -s /Applications "$stage/Applications"
cp build/dmg-background/background.tiff "$stage/.background/background.tiff"
hdiutil create -volname 'NanthAi Scribe' -srcfolder "$stage" -format UDRW -fs HFS+ "$rw"
hdiutil attach "$rw" -nobrowse -noautoopen -plist > "$mount_info"
mount=$(python3 - "$mount_info" <<'PYMOUNT'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    entities = plistlib.load(source)['system-entities']
print(next(entity['mount-point'] for entity in entities if 'mount-point' in entity))
PYMOUNT
)
mounted=true
"$layout_bin/dmg-layout" "$mount"
sync
hdiutil detach "$mount"
mounted=false
hdiutil convert "$rw" -format UDZO -o "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
echo "Signed $dmg"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo 'NOTARY_PROFILE is unset: stopped after signing. No notarization submitted.'
    exit 0
fi
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
