# Settings window and shortcut editor validation

Validated on 2026-07-24 for the post-1.2.0 Settings and keyboard-shortcut update.

## Reproduction

The v1.2.0 status menu called the dynamic responder action `showSettingsWindow:`. In the accessory menu-bar application, no guaranteed responder owned that action, so selecting **Settings…** could produce no usable content.

## Automated validation

- [x] The status-menu **Settings…** item invokes the explicit window-opening action.
- [x] The Settings controller creates a populated SwiftUI hosting window.
- [x] Repeated opens reuse the same window instead of creating duplicates.
- [x] Closing the window keeps it reusable.
- [x] A recorded extended shortcut such as `Control-Option-Shift-K` is accepted.
- [x] Unsupported single-modifier input is rejected.
- [x] Duplicate assignments leave the previous shortcut unchanged and show a conflict.
- [x] Restoring defaults resets all five actions.
- [x] A custom shortcut survives persistence round-trip.
- [x] Existing saved shortcut values remain decodable.

## Visual validation

- [x] The window renders the Overlay, Route, Recognition, and About sections.
- [x] The shortcut recorder remains inside the existing dark-occult Settings card.
- [x] All five actions and current combinations are readable.
- [x] The content scrolls without clipping when the window is at its minimum size.
- [x] The generated rendering is versioned as `docs/screenshots/settings-shortcut-editor-after.png`.

## Manual acceptance after installation

- [ ] Open **Settings…** from the menu-bar diamond.
- [ ] Close and reopen Settings; the same populated window returns.
- [ ] Record a new shortcut and verify it triggers the intended overlay action.
- [ ] Attempt to reuse an existing shortcut and verify the conflict warning.
- [ ] Restore defaults and verify all five original shortcuts return.
- [ ] Confirm no Screen Recording permission prompt is introduced.
