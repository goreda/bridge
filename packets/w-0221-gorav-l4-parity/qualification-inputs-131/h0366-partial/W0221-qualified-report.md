# W-0221 gorav L4 parity: solver report (in2tinct)

State: partial coverage, same ID W-0221, needs review. Not a closed packet, not product acceptance.

## Result

The pinned production file `PlaybackCore.swift` (57,752 bytes) compiled whole and unmodified with a small test shim. The real `FramePump` pacing loop (with `AVSyncDecider`, `MediaWallAnchor`, `CancelCommit`) ran against 17 fixed scenarios, each in plain mode and in `CancelCommit` ticket mode, plus 3 code-driven runs (cancel in wait, seek landing during a pacing wait in both modes). 37 runs, 0 fail. The existing 24 decision + 5 anchor vectors stay green (0 fail).

Six one-line mutants of the loop (made in temp copies only) all fail the new suite. The old 24+5 suite passes every one of them (exit 0), which shows the original gap directly.

| mutant | new suite failing checks | old 24+5 suite |
|---|---|---|
| drift sign flip (`paceAnchorPts! - (decisionNow - paceAnchorWall)`) | 84 | pass |
| deadline plus one frame duration | 91 | pass |
| seek anchor wall set to 0 | 26 | pass |
| retry limit 100 to 1000 | 2 | pass |
| drop stale-wait fence (`if false`) | 2 | pass |
| drop lastPts reset on seek | 4 | pass |

The last three are each caught by one targeted vector, so they are narrow detectors.

## Environment and source

- Packet: repo goreda/bridge, commit e763c45fd11c4a246e00160cad91804d418868af, path packets/w-0221-gorav-l4-parity/ (raw files fetched at that commit).
- Linux x86_64 (Ubuntu 22.04), Swift 6.1.2 (swift-6.1.2-RELEASE), Python 3, compiled with `-swift-version 5`.
- All six packet source pins matched the manifest. Pins before and after all runs: PlaybackCore d51e131e..., Package.swift c8024acb... (unchanged).

Full sha256:

```
d51e131eb6240279bbb207c7d1b323d947d6d3fb41fb0d4fdcf709a1419f2260  Sources/GorAVPlaybackCore/PlaybackCore.swift
c8024acbc50dbc977a59f72665c17c74ed4395a3c2159e54a757a8d6e46e2274  Package.swift
9b2c293f362da7ab875084b3d3e026965e07f2ccdc040dfb52ef39c57068b981  Tests/parity/ClockParity.swift
c4b7438957f1c20711b187cf4360965f1659d627a2013423c6f3bcc259d3b5a5  Tests/parity/run-clock-parity.py
c1adbda4c43279c5ce29704a27e8754eb8eb5ccd967c17aba27d7a14192ad5a1  Tests/parity/README.md
48150fefcb3998df79aea52d42598ac051423e37375004f1e61bcfc5176f48f6  fixtures/corpus/clock-parity.json
c7aa5f0c4cf84198388e5a38bcb8ecd658a643b468322c08854b3c50b07a97c4  Tests/parity/LoopShim.swift
cc5222002e5607a060e26e01023b895e13b119ab5d02eb380c0e84b61d6f7997  Tests/parity/LoopParity.swift
68262ba09c942b110d6a324bd93b7fdd3adbe620737714cbfe6605cf13ae7976  Tests/parity/run-loop-parity.py
a8ae2ec7f5e3102533c80f25a3d59073e3e45aabcae089140fa8db02e82036da  fixtures/corpus/loop-parity.json
```

Peer freeze G0436: failure-cases JSON 10,107 B sha256 bc571cf4872ecfa02b6396392c4eb4ae3c73936be156bfc2975c193566e5c935; selftest 382 B 5b057b2a3d58e45cc5e04464a1dfa505137c5c33d5a12437fe6ca246ab09e2df (matched; the selftest checks JSON shape only, not loop behavior).

## Reproduce

Layout: the packet's repo layout, with the new files added. Production files and Package.swift are not touched.

```
python3 Tests/parity/run-clock-parity.py --source Sources/GorAVPlaybackCore/PlaybackCore.swift
python3 Tests/parity/run-loop-parity.py --source Sources/GorAVPlaybackCore/PlaybackCore.swift --negative-controls
```

Expected: `CLOCK_PARITY decisions=24 anchors=5 failures=0`; `loop parity: 17 corpus scenarios x {plain,commit} + 3 code-driven = 37 runs, 0 fail`; then 6 negative controls each exit 1, ending `all 6 negative controls fail as required`.

New files: `Tests/parity/LoopShim.swift`, `Tests/parity/LoopParity.swift`, `Tests/parity/run-loop-parity.py`, `fixtures/corpus/loop-parity.json`. Harness: virtual monotonic clock, scripted source, recording sink; the wait callback advances the clock; each shown frame records (pts, wall). Values are binary-exact; comparison tolerance 1e-9.

Scenarios: steady arrival anchor; seek anchor honors landing gap; forward gap over maxWait (3 waits); backward seek with reset; forward seek mid-play; backward pts without reset; late burst then recovery; early gap capped waits; retry limit; non-finite pts and duration; negative stream origin; identical pts; +3600 s clock advance; 1000 frames no drift; sink refusal; 30 s pause without reset; 30 s pause with arrival reset.

## Test stand-ins and differences

The pinned file does not compile alone. It needs two types defined in package files that are not in the packet: `AtomicU64` (GorAVCAtomics) and `TimingLedger` with its segment, subsystem and kind enums. The shim supplies stand-ins:

- `AtomicU64`: lock-guarded UInt64 with load, compareExchange, fetchAdd. The real one is a C atomic. Memory ordering, lock-free behavior and failed-creation behavior are not exercised; `CancelCommit.available` is always true. This is not a real-atomics race proof.
- `TimingLedger`: records event kinds only. The real ledger's ordering and overflow behavior is untested. The enums are minimal re-declarations of the names the file uses.
- The sink uses `CancelCommit._testMayFinishConsume`, a test-only API in the pinned file, not the real display commit path.

FramePump and CancelCommit logic run from the pinned bytes. This is a qualified partial integration, not whole-production integration. Whether it meets the packet acceptance gates is for the packet gates and the owner to judge.

## Behavior of the current source (characterization, pinned as vectors, not fixes)

1. Pause: with no `resetPresentation`, a 30 s wall gap makes later frames late and they are typed drops. With `resetPresentation` (arrival anchor) the first frame after the gap shows at once. This is FramePump behavior only; how the shell handles resume is not tested here.
2. A +3600 s forward advance of the injected clock stays monotonic (a suspend-like gap). The pump never re-anchors: every later frame is dropped until pts catches up or a reset. No hang, no unbounded catch-up. No wall-clock or NTP step was tested; the loop reads only the injected clock.
3. One frame with pts 1e9: 100 waits, then one typed drop at the retry limit. Because `lastPts` then holds 1e9, later normal frames are out-of-order drops until a reset.
4. Backward pts without a reset: typed out-of-order drops. Identical pts: both shown. Negative origin: shown and paced from the first frame.
5. A seek landing during a pacing wait is fenced typed (`seekStalePulls` = 1); the next frame paces from the new seek anchor, in both modes.

## Peer case mapping (G0436)

Run: pts 0, negative origin, NaN, +inf, duration 0 and -1, 1e9, identical pts, backward pts without reset (generic), seek during wait (single seek), cancel in wait, drop burst with recovery, 1000-frame drift, six mutants (NC-01 and NC-02 map to these).

Not run: pts 1e-9, 30 days, Double.greatestFiniteMagnitude, -inf, a separate 1e6 s backward jump, FC-02 (two seeks 5 ms apart), FC-05 (100 pause/resume at 1 ms), FC-09b (wall-clock step), FC-10 and FC-11 (audio master; `SyncMaster.audioNotImplemented` is not selectable), FC-01 and FC-03 behavior with a queued-source seek barrier. The peer's proposed tolerances (1 ms, 12 frames in 0.5 s) were not used; walls are exact.

## Not covered (suggested scope line)

"Executes the unmodified production FramePump pacing loop (with AVSyncDecider, MediaWallAnchor, CancelCommit) on a virtual monotonic clock with scripted frames and a recording sink; AtomicU64 and TimingLedger are test stand-ins. Not covered: queued-source seek barrier (QueuedFrameSource), audio master, real decoder, native display and HDR, real atomics races, wall-clock jumps, full-package parity."

Not run on macOS.

## Ask (same ID W-0221)

Please supply the GorAVCAtomics source and the TimingLedger source file(s) from the pinned commit, so the shim can be replaced by the real files and the loop re-run. This would remove the stand-in caveat. Optional for this partial result.
