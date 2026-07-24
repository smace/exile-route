#!/bin/sh
set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf 'Usage: %s stable|beta RELEASE_TAG ARCHIVE [RELEASE_NOTES]\n' "$0" >&2
    exit 64
fi

channel="$1"
release_tag="$2"
archive_path="$3"
release_notes_path="${4:-}"
repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
key_account="${EXILE_ROUTE_UPDATE_KEY_ACCOUNT:-com.swannmace.ExileRoute}"
sparkle_bin="${SPARKLE_BIN_DIR:-$repository_root/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
appcast_path="${EXILE_ROUTE_APPCAST_PATH:-$repository_root/updates/appcast.xml}"

case "$channel" in
    stable|beta) ;;
    *)
        printf 'Unknown channel: %s\n' "$channel" >&2
        exit 64
        ;;
esac
case "$release_tag" in
    v*) ;;
    *)
        printf 'Release tag must start with v: %s\n' "$release_tag" >&2
        exit 64
        ;;
esac
if [ ! -f "$archive_path" ]; then
    printf 'Archive not found: %s\n' "$archive_path" >&2
    exit 1
fi
if [ -n "$release_notes_path" ] && [ ! -f "$release_notes_path" ]; then
    printf 'Release notes not found: %s\n' "$release_notes_path" >&2
    exit 1
fi
if [ ! -x "$sparkle_bin/generate_appcast" ]; then
    printf 'Sparkle publishing tools not found in: %s\n' "$sparkle_bin" >&2
    printf 'Resolve the Xcode package or set SPARKLE_BIN_DIR.\n' >&2
    exit 1
fi

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/exile-route-appcast.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT HUP INT TERM
archive_name="$(basename "$archive_path")"
archive_stem="${archive_name%.*}"

cp "$appcast_path" "$staging_directory/appcast.xml"
cp "$archive_path" "$staging_directory/$archive_name"
if [ -n "$release_notes_path" ]; then
    cp "$release_notes_path" "$staging_directory/$archive_stem.md"
fi

set -- \
    --account "$key_account" \
    --download-url-prefix "https://github.com/smace/exile-route/releases/download/$release_tag/" \
    --link "https://github.com/smace/exile-route/releases/tag/$release_tag" \
    --embed-release-notes \
    --maximum-versions 0
if [ "$channel" = beta ]; then
    set -- "$@" --channel beta
fi

"$sparkle_bin/generate_appcast" "$@" "$staging_directory"
xmllint --noout "$staging_directory/appcast.xml"

temporary_output="$appcast_path.new"
cp "$staging_directory/appcast.xml" "$temporary_output"
mv "$temporary_output" "$appcast_path"

printf 'Prepared signed %s appcast entry for %s.\n' "$channel" "$release_tag"
printf 'The private EdDSA key remained in the login Keychain account %s.\n' "$key_account"
