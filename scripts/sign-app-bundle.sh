#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf 'Usage: %s APP_PATH SIGNING_IDENTITY\n' "$0" >&2
    exit 64
fi

application_path="$1"
signing_identity="$2"
sparkle_framework="$application_path/Contents/Frameworks/Sparkle.framework"
sparkle_version="$sparkle_framework/Versions/B"

if [ ! -d "$application_path" ]; then
    printf 'Application not found: %s\n' "$application_path" >&2
    exit 1
fi
if [ ! -d "$sparkle_framework" ]; then
    printf 'Sparkle framework not found: %s\n' "$sparkle_framework" >&2
    exit 1
fi

sign() {
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --preserve-metadata=identifier,entitlements \
        --sign "$signing_identity" \
        "$1"
}

# Sparkle contains nested executable bundles. Sign from the inside out so the
# enclosing framework and application seal the final helper signatures.
sign "$sparkle_version/XPCServices/Downloader.xpc"
sign "$sparkle_version/XPCServices/Installer.xpc"
sign "$sparkle_version/Autoupdate"
sign "$sparkle_version/Updater.app"
sign "$sparkle_framework"
sign "$application_path"

codesign --verify --deep --strict --verbose=2 "$application_path"
