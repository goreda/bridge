# PanelFocus key-ownership harness

Run `bash gor/Tests/Harness/PanelFocus/run.sh` (python3 only, no network, no
package installs). Ports `PanelKeyOwnership` from
`gor/Sources/gor/PanelFocusTraversal.swift` and replays the Cmd+M search-panel
focus scenario against a pre-fix model (shipped behavior at 3c48acac) and the
fixed model. Source anchors read the current Swift tree directly, with no
old-source fallback.

Defect modelled: while a GORInputPanel (magnet search bar, URL panel, about
panel) is open, four automatic paths re-keyed the player/overlay window
unconditionally - the o2 activation beat (fires after every NSApp.activate,
including the one in the panel's own open path), the o1 mpv-process activation
recovery, PPController.claimFocusForClick on any overlay click, and
DraggableOverlayWindow.sendEvent. Each one leaves the panel visible but never
key; when the mpv process window holds key, gor's local monitors never run, so
keyboard, esc and the panel's mouse focus are all dead.

PASS means the ownership rule rejects every automatic player re-key while an
input panel is open, allows the intentional key return on panel close, and the
Swift sources carry the five guarded call sites plus the [panel-focus]
diagnostics. It does NOT exercise AppKit, the window server, or a Mac build;
those remain Mac-side via ./build.sh. Source changes to the guarded paths
require semantic port review, not merely token agreement.
