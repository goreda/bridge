# Fullscreen <-> PiP transition-tick overlay sync

Run `SWIFTC=/path/to/swiftc python3 Tests/FullscreenPiPTransitionTick/run.py`.

Owner report (build 3c48acac): leaving fullscreen into PiP with the photon
magnet / "i" stats HUD open, the mpv window returns to the PiP frame at once
but the gor overlay stays fullscreen-sized for seconds, then shrinks. Root
class: lagging state on the mode change. The first receipt of the new mode
was fenced off in syncOverlay (prepareMPVFullscreenTransition advances the
drag generation before the generic follow's fence is evaluated), and
trackMPVFullscreen itself committed nothing before the restore settle gate
(0.35-0.60 s of stable frames after the animation, 5 s timeout).

Fix: trackMPVFullscreen commits the first receipt of every mode change
(entry and exit) to the overlay on the transition tick, through
commitOverlayFrame's atomic no-animation transaction, so the overlay window
and every HUD inside it (photon magnet, "i" stats, spine, subtitles) land on
mpv's frame in the same tick. The settle gate keeps confirming only restore
bookkeeping and the one final PiP/refit intent. Diagnostics log overlay vs
mpv frame at entry, exit and settled restore ("[window-sync] transition
receipt ..." / "[window-sync] restore settled ...").

The test compiles the current production trackMPVFullscreen,
commitOverlayFrame, prepareMPVFullscreenTransition, restore/refit PiP and
refit routing methods with order-recording frame/layout spies: 24 cases
across two screens, four PiP corners and three aspects assert geometry
equality after the transition tick, frame-before-layout ordering inside one
disabled-actions transaction, no fullscreen writes, at most one settled
intent write, and saved PiP target preservation. On the unpatched base the
entry-tick equality precondition fails (SIGILL witness).

Linux evidence only. Native AppKit/AX motion, installed PiP pixels and
absolute timing remain unverified; the Mac self-test capture is the real gate.
