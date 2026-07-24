#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    printf 'Usage: %s APP_PATH SIGNING_IDENTITY [ALLOW_GET_TASK_ALLOW]\n' "$0" >&2
    exit 64
fi

application_path="$1"
signing_identity="$2"
allow_get_task_allow="${3:-false}"
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

assert_no_get_task_allow() {
    signed_path="$1"
    entitlement="$(
        codesign -d --entitlements :- "$signed_path" 2>/dev/null |
            plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null ||
            true
    )"
    if [ "$entitlement" = true ]; then
        printf 'Forbidden get-task-allow entitlement in: %s\n' "$signed_path" >&2
        exit 1
    fi
}

if [ "$allow_get_task_allow" != true ]; then
    assert_no_get_task_allow "$sparkle_version/XPCServices/Downloader.xpc"
    assert_no_get_task_allow "$sparkle_version/XPCServices/Installer.xpc"
    assert_no_get_task_allow "$sparkle_version/Autoupdate"
    assert_no_get_task_allow "$sparkle_version/Updater.app"
    assert_no_get_task_allow "$sparkle_framework"
    assert_no_get_task_allow "$application_path"
fi
