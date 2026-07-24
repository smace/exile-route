#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
appcast="$repository_root/updates/appcast.xml"

xmllint --noout "$appcast"

enclosure_count="$(xmllint --xpath 'count(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"])' "$appcast")"
signature_count="$(xmllint --xpath 'count(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$appcast")"
if [ "$enclosure_count" != "$signature_count" ]; then
    printf 'Every appcast enclosure must have an EdDSA signature (%s/%s).\n' "$signature_count" "$enclosure_count" >&2
    exit 1
fi

printf 'Validated appcast: %s signed update enclosure(s)\n' "$signature_count"
