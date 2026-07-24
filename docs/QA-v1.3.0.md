# Exile Route v1.3.0 validation

Validated on 2026-07-24 with:

- Apple Silicon (`arm64`);
- macOS 26.5.2, while the deployment target remains macOS 15;
- Xcode 26.6 and the GitHub-hosted Xcode 16.4 runner.

No account-specific screenshot or OCR frame is retained by this report.

## Automated validation

- [x] The bundled ten-act route snapshot validates.
- [x] The status-menu Settings item invokes an explicit window action.
- [x] The populated Settings window is reusable after close and reopen.
- [x] Keyboard recording accepts supported keys with two to four modifiers.
- [x] Duplicate and unsupported combinations are rejected.
- [x] Default shortcuts can be restored.
- [x] Custom combinations persist across state round trips.
- [x] Legacy state without custom shortcuts remains decodable.
- [x] Duplicate legacy shortcuts are sanitized safely.
- [x] All 53 macOS tests pass locally.
- [x] GitHub Actions passes on Xcode 16.4.
- [x] The Settings rendering is versioned with before/after references.

## Local release validation

- [x] The Release build embeds version `1.3.0`, build `4`, and Git revision `49eda74f`.
- [x] The durable certificate-backed build is installed in `/Applications/ExileRoute.app`.
- [x] The signing requirement matches the previous local build.
- [x] Only one installed Exile Route application remains.
- [x] Existing route progress and settings are preserved after launch.
- [x] Settings opens with all four sections visible and both menu paths reuse the same window.
- [x] A custom `⌃⌥⇧K` shortcut can be recorded and restored to the default `⌃⌥←`.

## GeForce NOW validation

- [ ] The overlay remains visible without stealing focus outside interaction mode.
- [ ] Customized shortcuts trigger while GeForce NOW is focused.
- [ ] OCR continues to progress after two coherent nearby-zone detections.
- [ ] No new Screen Recording permission dialog appears.

## Release decision

Automated validation and local release checks must pass before publishing. GeForce NOW remains the final real-game acceptance pass after installation.
