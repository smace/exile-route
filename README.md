# Exile Route

Exile Route is a native macOS campaign overlay for Path of Exile played through GeForce NOW. It keeps the current campaign instruction visible, advances from locally detected area names, and remains fully usable with manual hotkeys.

The visual design is an original dark occult interface. This project is not affiliated with or endorsed by Grinding Gear Games. Path of Exile is a trademark of Grinding Gear Games.

Route content and route-language concepts are derived from [HeartofPhos/exile-leveling](https://github.com/HeartofPhos/exile-leveling), used under its MIT license.

## Requirements

- Apple Silicon Mac
- macOS 15 or newer
- Xcode 16 or newer
- XcodeGen
- GeForce NOW with Path of Exile in English for OCR auto-progress

## Build

```sh
brew install xcodegen
./scripts/generate-project.sh
xcodebuild test -project ExileRoute.xcodeproj -scheme ExileRoute -destination 'platform=macOS,arch=arm64'
./scripts/build-release.sh
```

The first OCR launch asks for macOS Screen Recording permission. Frames are processed locally, never stored, and never uploaded.

## License

MIT. See [LICENSE](LICENSE) and bundled upstream attribution.
