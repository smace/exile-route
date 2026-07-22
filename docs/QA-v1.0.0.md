# Exile Route v1.0.0 validation

Validated on 2026-07-22 with:

- Apple Silicon (`arm64`)
- macOS 26.5.2, while the deployment target remains macOS 15
- GeForce NOW 2.0.86.124
- Path of Exile in English
- Xcode 26.6, plus CI on the GitHub-hosted `macos-15` runner

No account-specific screenshots or OCR frames are retained by this report.

## Automated validation

- [x] Ten bundled acts parse successfully.
- [x] League-start, Library, bandit, fragment, hint, and invalid-input parser behavior is covered.
- [x] Duplicate OCR detections, low-confidence matches, distant jumps, manual commands, and no-regression behavior are covered.
- [x] OCR fixtures cover resolution and stream-effect variants, with Vision exercised on a synthetic high-contrast title.
- [x] Network failure, partial commit, invalid schema, atomic installation, and last-valid rollback are covered.
- [x] Persistence migration, route import, HTTPS enforcement, Pastebin resolution, and visual states are covered.
- [x] Local suite: 23 tests, 0 failures.
- [x] Snapshot validation succeeds.
- [x] GitHub Actions CI succeeds on `main`.

## GeForce NOW validation

- [x] Overlay is visible above the real streamed game and remains legible on a dark scene.
- [x] Panel styling matches the versioned compact reference.
- [x] Default mode is click-through and the panel does not become the main window.
- [x] Overlay hides when GeForce NOW loses focus and returns when it becomes frontmost.
- [x] `Lioneye's Watch`, `The Coast`, and `The Submerged Passage` were recognized successively at confidence `1.0`.
- [x] Two coherent detections were observed before progression was accepted.
- [x] Persisted progress reached `The Submerged Passage` at route step 14 without regression.
- [x] Manual previous and next commands remain available.
- [x] Bundled route remains available with network-independent snapshot loading.
- [x] Compact overlay has sufficient contrast over the tested scene.

## Release decision

No blocking defect is known. The v1.0.0 candidate meets the stabilization criteria for an ad hoc signed, non-notarized release.
