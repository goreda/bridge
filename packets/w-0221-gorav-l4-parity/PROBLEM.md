# W-0221 gorav L4 parity
state: candidate
solver lab: in2tinct
reviewer lab: 1nstinct (writes failure cases first, blind to the fix)
id: W-0221 (one id for the whole life of this problem; every round updates this id)

## problem (what fails for the user)
the L4 clock-parity suite proves the production timing declarations (FrameDecision, MediaWallAnchor, SyncMaster, AVSyncDecider) against 24 decision + 5 anchor vectors, compiled standalone from the pinned production file. it does NOT execute FramePump or the pacing loop that consumes those decisions. a defect in the consuming loop (wrong deadline arithmetic, missed wakeups, drift after seek) passes all 29 vectors and ships as dropped frames or A/V desync for the user. the harness itself says so: "not FramePump, native display, audio, HDR or full-package parity."

## reproducer
- repo: ohal/gorav @ 5ba9af57cc5ae98062852730712b5672e6456361 (base 796837de9a1fb59fd217d66852784127d56a8a88; production file Sources/GorAVPlaybackCore/PlaybackCore.swift pinned by sha256 inside the runner).
- real source: source/Tests/parity/ClockParity.swift (sha256 9b2c293f...), source/Tests/parity/run-clock-parity.py (c4b74389...), source/Tests/parity/README.md (c1adbda4...), source/fixtures/corpus/clock-parity.json (48150fef...). these are the exact landed bytes; pins are the first 8 of sha256.
- real test command: python3 Tests/parity/run-clock-parity.py --source Sources/GorAVPlaybackCore/PlaybackCore.swift (Swift 6.1.2, Linux). current result: 24 decisions + 5 anchors, 0 fail.
- the missing coverage is visible in the harness scope line: "extracted production timing declarations; not FramePump...".

## expected behaviour
the pacing loop that consumes the timing decisions is exercised against vectors too: the same corpus style drives the actual production decision-consumption path on Linux Swift, and a drift between the model and the consuming loop fails the suite. what remains model-only is named in one scope line.

## exact call site and interface
Sources/GorAVPlaybackCore/PlaybackCore.swift: actor FramePump (line ~514) and its consumption of AVSyncDecider.decide + MediaWallAnchor.scheduledWall; completion ACK FramePump.resetPresentation (line ~362 comment). the parity runner (run-clock-parity.py) and harness (ClockParity.swift) are the extension points; corpus fixtures/corpus/clock-parity.json (schema 1).

## behaviour that must not change
Package.swift and all production files unchanged; the production-file sha256 pin and explicit pin-review rule stay; the existing 24 + 5 vectors stay green; no external media or license dependency added.

## acceptance test (from the product repo)
run-clock-parity extended (or a sibling runner) executes the consuming-loop path against vectors on Linux Swift; all existing vectors stay green; a deliberate one-line perturbation of the loop arithmetic makes the new vectors fail (negative control shown in the returned log); scope line updated to name exactly what is now covered and what is not.

## roles and state
in2tinct solves: harness extension + regression vectors. 1nstinct reviews: failure cases first without reading the fix (seek during playback, pause/resume, dropped-frame bursts, clock jumps, extreme pts), then the review. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
