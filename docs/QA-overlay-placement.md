# Overlay placement QA

## Visual reference

These neutral diagrams contain no Path of Exile or Grinding Gear Games assets.
The dashed cyan rectangle represents the persistent area-name region used by
OCR; it remains unobstructed.

| Before — top-left | After — top-right below the OCR region |
| --- | --- |
| ![Previous top-left placement](screenshots/overlay-placement-before.svg) | ![New top-right placement](screenshots/overlay-placement-after.svg) |

## Automated validation

- [x] Default placement uses a 24-point trailing inset.
- [x] The overlay starts 12 points below the configured OCR area-title region.
- [x] Negative display coordinates are supported for monitors left of the main display.
- [x] Compact/expanded resizing preserves the top-right anchor.
- [x] Placement is constrained to the visible display.
- [x] Saved pre-migration geometry is ignored once, cleared, and replaced atomically.

## GeForce NOW validation

- [ ] The overlay appears at the top-right on the first launch after updating.
- [ ] The persistent area label remains visible.
- [ ] Compact checklist growth keeps the same top-right anchor.
- [ ] Interaction-mode movement is saved and restored on the same display.
