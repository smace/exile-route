#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
appcast="$repository_root/updates/appcast.xml"
info_plist="$repository_root/ExileRoute/Info.plist"
module_cache="$(mktemp -d "${TMPDIR:-/tmp}/exile-route-swift-cache.XXXXXX")"
trap 'rm -rf "$module_cache"' EXIT HUP INT TERM

xmllint --noout "$appcast"
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
    xcrun swift "$repository_root/scripts/validate-appcast.swift" "$appcast" "$info_plist"
