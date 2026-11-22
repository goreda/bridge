# PiP subtitle typography

Run `SWIFTC=/path/to/swiftc python3 Tests/PiPSubtitleTypography/run.py`.

The production global variation listener derives normal subtitle point size from the mouse's distance to the main display center on every tick. It does not check application activation, so the same behavior continued while PiP was inactive. This was not caused by hover controls changing the PiP canvas.

PiP now has a distinct typography policy: a 25-point minimum and a stable user-scaled point size, independent of pointer distance and window dimensions. The pointer-driven SIZE axis is also neutral in PiP. The final font write enforces the policy for listener, fade, initialization and zoom paths. Mode changes apply immediately even while paused, reflow outgoing ink at the new size, and restore the saved normal typography when leaving PiP. New controllers inherit the current PiP mode. Normal and stereo typography formulas are unchanged; no canvas or glyph transforms were added.

The Linux test compiles production policy, mode setter, final font writer and fade method with font/layer boundary spies. It covers 3005 pointer/scale cases, the floor, SIZE-axis neutrality, immediate paused entry, idempotence, outgoing reflow and normal-mode restoration. Source routing checks cover enter/exit and controller replacement. Native AppKit/CoreText bitmap and the installed PiP window appearance remain unverified.
