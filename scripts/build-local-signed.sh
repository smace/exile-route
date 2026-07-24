#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    printf 'Usage: %s CONFIGURATION EXPECTED_BUNDLE_ID EXPECTED_FLAVOR\n' "$0" >&2
    exit 64
fi

configuration="$1"
expected_bundle_id="$2"
expected_flavor="$3"
repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
identity_name="${EXILE_ROUTE_SIGNING_IDENTITY:-Exile Route Local Signing}"
keychain_path="${EXILE_ROUTE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
derived_data="${EXILE_ROUTE_DERIVED_DATA:-$repository_root/DerivedData/LocalSigned-$configuration}"

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
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY="$identity_hash" \
    DEVELOPMENT_TEAM= \
    OTHER_CODE_SIGN_FLAGS=--timestamp=none \
    build

application_path="$derived_data/Build/Products/$configuration/ExileRoute.app"
"$repository_root/scripts/sign-app-bundle.sh" "$application_path" "$identity_hash"

bundle_id="$(plutil -extract CFBundleIdentifier raw "$application_path/Contents/Info.plist")"
flavor="$(plutil -extract ExileRouteDistributionFlavor raw "$application_path/Contents/Info.plist")"
if [ "$bundle_id" != "$expected_bundle_id" ] || [ "$flavor" != "$expected_flavor" ]; then
    printf 'Unexpected build identity: bundle=%s flavor=%s\n' "$bundle_id" "$flavor" >&2
    exit 1
fi

designated_requirement="$(codesign -d -r- "$application_path" 2>&1)"
case "$designated_requirement" in
    *"cdhash"*)
        printf 'The build still has an ad hoc designated requirement:\n%s\n' "$designated_requirement" >&2
        exit 1
        ;;
    *"identifier \"$expected_bundle_id\""*'certificate root = H"'*)
        ;;
    *)
        printf 'The build does not have the expected certificate-backed requirement:\n%s\n' "$designated_requirement" >&2
        exit 1
        ;;
esac

printf 'Built durable local %s:\n%s\n' "$configuration" "$application_path"
printf '%s\n' "$designated_requirement"
