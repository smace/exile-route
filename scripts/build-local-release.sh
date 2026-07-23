#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
identity_name="${EXILE_ROUTE_SIGNING_IDENTITY:-Exile Route Local Signing}"
keychain_path="${EXILE_ROUTE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
derived_data="${EXILE_ROUTE_DERIVED_DATA:-$repository_root/DerivedData/LocalSigned}"

cd "$repository_root"

identity_hash="$(
    security find-identity -v -p codesigning "$keychain_path" 2>/dev/null |
        awk -v label="\"$identity_name\"" 'index($0, label) { print $2; exit }'
)"
if [ -z "$identity_hash" ]; then
    printf 'Missing signing identity: %s\n' "$identity_name" >&2
    printf 'Create it with: ./scripts/create-local-signing-identity.sh\n' >&2
    exit 1
fi

xcodegen generate
xcodebuild \
    -project ExileRoute.xcodeproj \
    -scheme ExileRoute \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY="$identity_hash" \
    DEVELOPMENT_TEAM= \
    OTHER_CODE_SIGN_FLAGS=--timestamp=none \
    build

application_path="$derived_data/Build/Products/Release/ExileRoute.app"
codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --sign "$identity_hash" \
    "$application_path"
codesign --verify --deep --strict --verbose=2 "$application_path"

designated_requirement="$(codesign -d -r- "$application_path" 2>&1)"
case "$designated_requirement" in
    *"cdhash"*)
        printf 'The Release still has an ad hoc designated requirement:\n%s\n' "$designated_requirement" >&2
        exit 1
        ;;
    *'identifier "com.swannmace.ExileRoute"'*'certificate root = H"'*)
        ;;
    *)
        printf 'The Release does not have the expected certificate-backed requirement:\n%s\n' "$designated_requirement" >&2
        exit 1
        ;;
esac

printf 'Built durable local Release:\n%s\n' "$application_path"
printf '%s\n' "$designated_requirement"
