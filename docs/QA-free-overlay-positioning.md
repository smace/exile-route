# Free overlay positioning validation

Validated on 2026-07-24 with Apple Silicon, macOS 26.5.2, Xcode 26.6, and deployment target macOS 15.

## Automated validation

- [x] A left mouse-down starts native window dragging only while interaction mode is enabled.
- [x] Right-click and normal click-through mode never begin a window drag.
- [x] Saved state remains backward compatible when no preferred display exists.
- [x] The destination display identifier and final frame persist together.
- [x] A legacy placement migration clears the obsolete display before saving the new one.
- [x] Overlay placement and persistence suites: 12 tests, 0 failures.
- [x] Bundled route snapshot validation succeeds.
- [x] Shell scripts pass syntax validation.

## Manual validation

- [ ] Enable movement with `⌃⌥I` while GeForce NOW is frontmost.
- [ ] Drag from the header, objective checklist, and footer.
- [ ] Move the panel within the current display and onto a second display.
- [ ] Lock with `⌃⌥I` and confirm clicks pass through to GeForce NOW.
- [ ] Relaunch Exile Route and confirm the final display and position are restored.
- [ ] Confirm the overlay still hides when GeForce NOW loses focus.

## Interface references

- Before: interaction mode is visible but does not explain the drag surface.
- After: the footer explicitly says `DRAG ANYWHERE • ⌃⌥I TO LOCK`.

The references are account-neutral and contain no proprietary Path of Exile assets.
