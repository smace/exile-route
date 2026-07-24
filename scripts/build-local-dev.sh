#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export EXILE_ROUTE_DERIVED_DATA="${EXILE_ROUTE_DERIVED_DATA:-$repository_root/DerivedData/LocalDev}"
exec "$repository_root/scripts/build-local-signed.sh" \
    Debug \
    com.swannmace.ExileRoute.Dev \
    dev
