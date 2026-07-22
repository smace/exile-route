#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project ExileRoute.xcodeproj -scheme ExileRoute -configuration Release -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
cp -R DerivedData/Build/Products/Release/ExileRoute.app ./ExileRoute.app
ditto -c -k --sequesterRsrc --keepParent ExileRoute.app ExileRoute-1.0.0.zip
shasum -a 256 ExileRoute-1.0.0.zip > ExileRoute-1.0.0.zip.sha256

