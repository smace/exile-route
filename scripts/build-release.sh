#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

version="$(awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
if [ -z "$version" ]; then
    printf 'Unable to read MARKETING_VERSION from project.yml\n' >&2
    exit 1
fi

archive_name="ExileRoute-$version.zip"

xcodegen generate
xcodebuild -project ExileRoute.xcodeproj -scheme ExileRoute -configuration Release -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
cp -R DerivedData/Build/Products/Release/ExileRoute.app ./ExileRoute.app
ditto -c -k --sequesterRsrc --keepParent ExileRoute.app "$archive_name"
shasum -a 256 "$archive_name" > "$archive_name.sha256"
