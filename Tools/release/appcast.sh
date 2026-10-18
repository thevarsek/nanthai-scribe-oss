#!/bin/bash
# Only creates local release metadata. The owner publishes the DMG and XML separately.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
: "${SPARKLE_BIN:?Set SPARKLE_BIN to the Sparkle distribution bin directory}"
dmg=${1:?Usage: appcast.sh path/to/notarized.dmg}
base=${2:-https://scribe.nanthai.tech/downloads/}
work="$root/build/appcast"
mkdir -p "$work" "$root/website/public"
if [[ -f "$root/website/public/appcast.xml" ]]; then
    cp "$root/website/public/appcast.xml" "$work/appcast.xml"
fi
cp "$dmg" "$work/"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$base" "$work"
cp "$work/appcast.xml" "$root/website/public/appcast.xml"
echo "Wrote website/public/appcast.xml. Review it before publishing."
