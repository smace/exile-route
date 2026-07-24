# Changelog

## Unreleased

### Added

- Add a free, Keychain-backed local signing workflow that keeps a stable application identity across development builds.
- Display every objective of the current zone visit as a compact checklist, with completed, active, upcoming, and skipped states.
- Preview the next two zone visits in expanded mode and expose all hints there.
- Warn for four seconds when a zone transition skips unfinished objectives, with one-key recovery through Previous.
- Show the application version, build number, and exact Git revision in the menu bar and About settings.

### Changed

- Place the overlay at the top-left of each display, below Path of Exile's persistent area label, while preserving that anchor as the checklist grows.
- Preserve the saved top-left anchor across launches and stabilize the initial resize before enabling animations.
- Make Previous and Next navigate individual objectives while OCR remains responsible only for confirmed zone changes.
- Treat each repeated passage through an area as a distinct route visit and include its exit as the final objective.

### Fixed

- Size the compact overlay from its measured SwiftUI content so every objective in a zone remains visible.
- Restrict automatic OCR progression to the exit of the current zone visit so a false match cannot skip Rhoa Glyphs and jump from The Coast to The Tidal Island.
- Preserve the source-zone context for transitions and correctly distinguish portal creation from portal use.
- Request Screen Recording permission at most once per application launch while continuing to detect a permission granted from System Settings.
- Accept repeated nearby area identifiers without crashing when OCR starts.

All notable changes to Exile Route are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-22

### Added

- Native non-activating SwiftUI/AppKit overlay for GeForce NOW on macOS 15 and Apple Silicon.
- Original dark occult visual system, procedural ornaments, Cinzel titles, compact and expanded layouts, and application icon.
- Complete offline ten-act route snapshot pinned to HeartofPhos commit `bbcc7163bdc6f03e0d2276f2dd8bf32e68db6b16`.
- Typed route DSL parser with route conditions, sections, fragments, hints, areas, quests, and manual progression.
- Local ScreenCaptureKit and Vision area recognition with coherent-detection gating, nearby-area constraints, and no automatic regression.
- Configurable global shortcuts, menu-bar controls, interaction mode, opacity, text scaling, and OCR calibration.
- Custom route import from text, clipboard, file, HTTPS, and Pastebin, plus file and clipboard export.
- Validated atomic upstream updates with rollback to the last valid cached snapshot.
- Persistent settings, active route, campaign progress, shortcuts, OCR crop, and per-display overlay geometry.
- CI, parser and progression tests, OCR fixtures, updater rollback tests, persistence tests, and visual snapshot tests.

[1.0.0]: https://github.com/smace/exile-route/releases/tag/v1.0.0
