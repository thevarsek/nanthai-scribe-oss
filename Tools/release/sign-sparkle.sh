#!/bin/bash
# Re-sign from the inside out, preserving framework symlinks and Sparkle's hardened helpers.
set -euo pipefail
framework=$1
identity=$2
timestamp=$3
version="$framework/Versions/B"
for binary in "$version"/XPCServices/*.xpc "$version"/Autoupdate "$version"/Updater.app; do
    codesign --force --options runtime --preserve-metadata=entitlements "$timestamp" --sign "$identity" "$binary"
done
codesign --force --options runtime "$timestamp" --sign "$identity" "$framework"
