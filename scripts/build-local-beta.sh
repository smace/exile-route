#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export EXILE_ROUTE_DERIVED_DATA="${EXILE_ROUTE_DERIVED_DATA:-$repository_root/DerivedData/LocalBeta}"
exec "$repository_root/scripts/build-local-signed.sh" \
    Beta \
    com.swannmace.ExileRoute \
    beta
