#!/bin/bash
# Publishes a notarized, stapled DMG as a GitHub Release on the public repo and points
# scribe.nanthai.tech at it. The DMG itself never goes into git or onto Netlify: GitHub
# serves the bytes, and website/public/_redirects keeps every URL on our own domain, so the
# appcast's /downloads/ prefix (Tools/release/appcast.sh) stays valid for every version.
# Run only with the owner's go-ahead; it publishes. Commit and push website/public/ after.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
dmg=${1:?Usage: publish.sh path/to/notarized.dmg}
repo=${PUBLIC_REPO:-thevarsek/nanthai-scribe-oss}
name=$(basename "$dmg")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Resources/Info.plist")
tag="v$version"
[[ "$name" == "NanthAi-Scribe-$version.dmg" ]] || { echo "Expected NanthAi-Scribe-$version.dmg, got $name." >&2; exit 1; }
xcrun stapler validate "$dmg" >/dev/null || { echo "$name is not stapled; run make dmg with NOTARY_PROFILE." >&2; exit 1; }
grep -q "$name" "$root/website/public/appcast.xml" || { echo "Run Tools/release/appcast.sh on $name first." >&2; exit 1; }

gh release create "$tag" "$dmg" --repo "$repo" --title "NanthAi Scribe $version for Mac" \
    --notes "Download: https://scribe.nanthai.tech/download/NanthAi-Scribe.dmg (macOS 26, Apple silicon)."

url="https://github.com/$repo/releases/download/$tag/$name"
redirects="$root/website/public/_redirects"
touch "$redirects"
# Versioned file for Sparkle; the unversioned name always means the latest release.
grep -v '^/download/NanthAi-Scribe.dmg ' "$redirects" > "$redirects.tmp" || true
mv "$redirects.tmp" "$redirects"
echo "/downloads/$name  $url  302" >> "$redirects"
echo "/download/NanthAi-Scribe.dmg  $url  302" >> "$redirects"
echo "Published $tag. Commit and push website/public/_redirects and appcast.xml to go live."
