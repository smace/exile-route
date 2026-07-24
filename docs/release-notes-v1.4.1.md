# Exile Route 1.4.1

Exile Route 1.4.1 hardens the automatic update path introduced in v1.4.0.

- The complete update feed is now Ed25519-signed and rejected if modified.
- Every update archive is authenticated before Sparkle extracts it.
- Stable and Beta builds can no longer redirect their update feed through an environment variable.
- Distributed Beta and Release builds no longer include the debugging entitlement.
- CI verifies the feed, every published archive, release ordering, and the final application entitlements.

No Apple Team ID or signing-certificate rotation is included in this patch. Screen Recording permission continuity remains subject to the existing local/ad hoc signing limitation.

The application targets Apple Silicon and requires macOS 15 or newer. Public archives remain ad hoc signed and are not notarized.
