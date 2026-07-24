# Exile Route v1.2.0 validation

Validated on 2026-07-24 with:

- Apple Silicon (`arm64`);
- macOS 26.5.2, while the deployment target remains macOS 15;
- Xcode 26.6 and the GitHub-hosted `macos-15` runner.

No account-specific screenshot or OCR frame is retained by this report.

## Automated validation

- [x] The bundled ten-act route snapshot validates.
- [x] A window drag begins only for a left click while interaction mode is active.
- [x] Normal overlay mode remains click-through.
- [x] The overlay frame and display identifier survive persistence round trips.
- [x] Legacy settings without a display identifier remain decodable.
- [x] Existing progress migration keeps overlay placement data compatible.
- [x] The interaction visual reference displays the drag and lock instructions.
- [x] GitHub Actions CI succeeds for the feature pull request.

## Local release validation

- [ ] The Release build embeds version `1.2.0`, build `3`, and its exact Git revision.
- [ ] The durable certificate-backed build is installed in `/Applications/ExileRoute.app`.
- [ ] The signing requirement matches the previous local build.
- [ ] Only one installed Exile Route application remains.
- [ ] Existing route progress and settings are preserved after launch.
- [ ] Moving the overlay changes its persisted frame and last display.

## GeForce NOW validation

- [ ] `Control-Option-I` enables interaction and changes the footer instructions.
- [ ] A left-button drag from any point moves the overlay freely.
- [ ] A second `Control-Option-I` locks the position and restores click-through.
- [ ] The overlay remains visible above the streamed game without stealing focus outside interaction mode.
- [ ] OCR continues to progress after two coherent nearby-zone detections.
- [ ] No new Screen Recording permission dialog appears.

## Release decision

Automated validation and local release checks must pass before publishing. The GeForce NOW checks remain the final real-game acceptance pass after installation.
