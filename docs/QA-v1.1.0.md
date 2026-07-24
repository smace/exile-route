# Exile Route v1.1.0 validation

Validated on 2026-07-24 with:

- Apple Silicon (`arm64`);
- macOS 26.5.2, while the deployment target remains macOS 15;
- Xcode 26.6 and the GitHub-hosted `macos-15` runner.

No account-specific screenshot or OCR frame is retained by this report.

## Automated validation

- [x] The bundled ten-act route snapshot validates.
- [x] Current-zone visits preserve repeated areas, transitions, portals, waypoints, hints, and route conditions.
- [x] Manual objective navigation, skipped-objective recovery, duplicate OCR zones, distant jumps, and no regression are covered.
- [x] Saved v1 progress decodes without `skippedStepIDs`.
- [x] Compact and expanded checklist states are covered by versioned visual references.
- [x] Top-right placement derives from the configured OCR crop and preserves its anchor while the checklist resizes.
- [x] Saved overlay geometry migrates to placement version 3.
- [x] GitHub Actions CI succeeds for the functional and release pull requests.
- [x] The Release build embeds version `1.1.0`, build `2`, and its Git revision.

## Local installation validation

- [ ] The durable certificate-backed build is installed in `/Applications/ExileRoute.app`.
- [ ] The signing requirement matches the previous local build.
- [ ] Only one installed Exile Route application remains.
- [ ] Existing route progress and settings are preserved after launch.
- [ ] The overlay appears at the top-right, 12 pt below the configured OCR region.

## GeForce NOW validation

- [ ] The overlay remains visible above the streamed game without taking keyboard or mouse focus.
- [ ] The active zone checklist displays every objective and its exit.
- [ ] The overlay does not cover the captured area-name text.
- [ ] OCR progresses after two coherent nearby-zone detections.
- [ ] No new Screen Recording permission dialog appears.

## Release decision

Automated validation must be green and the local installation checks must pass before publishing. The GeForce NOW checks remain the final real-game acceptance pass after installation.
