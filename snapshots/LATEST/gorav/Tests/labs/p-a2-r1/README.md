# P-A2: deterministic audio-master scheduler

Clean-room Swift package implementing the packet's public protocol. No third-party
source or dependencies, licensed assets, user data, devices, wall-clock reads or
sleeps are used by the scheduler or simulation. Python 3 is used only to regenerate
compact JSON fixture definitions. Swift/XCTest runs the simulation.

## Reproduce

Requires Swift 5.9 or newer; tested with Swift 6.0.3, Linux x86_64.

```sh
export LC_ALL=C
python3 tools/generate.py
mkdir -p Evidence
EVIDENCE_DIR="$PWD/Evidence" swift test -j 1
python3 tools/verify_evidence.py
sha256sum -c SHA256SUMS
```

Do not overwrite the saved run log if you want its manifest hash to remain valid.
The package has no network dependency. The Swift toolchain is not bundled.

## Clock and decisions

All time values are seconds. The host clock is supplied by the caller. After each
valid audio sample, `mediaTime(at: h) = mediaAnchor + h - hostAnchor`, rate 1.0.
Audio media-time samples have jitter [-2, 0, 2, 0] milliseconds in repeating
10 ms updates, including at tick zero. Jitter perturbs measured audio position,
not host delivery time. At a seek tick, seek takes priority over that audio update.

A frame ahead of the audio master waits. A frame late by more than 40 ms plus
1e-9 seconds drops. Other frames present. The 1e-9 tolerance is explicit numeric
boundary slack, not another scheduling window. Invalid decisions drop; invalid
anchors are ignored. Finite times and serialized calls are the supported domain.
Backward host queries extrapolate backward, which is useful for reproducible
inspection; out-of-order audio updates are not reordered or smoothed.

## Seek identity limitation: acceptance remains conditional

The packet's PTS-only `decide(videoPTS:hostTime:)` cannot distinguish two frames
with the same timestamp but different seek generations. This is an information
limit, not a timing algorithm failure. In particular, an unseen pre-seek frame at
PTS 10 and a fresh post-seek frame at PTS 10 supply identical arguments. They
cannot be required to return different decisions with this protocol alone.

The exact protocol is preserved. This implementation invalidates PTS values known
to be waiting when seek occurs. That protects known pending frames, but can also
drop a legitimate new frame with the same PTS. Its invalidated-PTS storage grows
until reset; it is deliberately conservative. `reset` starts a fresh timeline and
clears these PTS sets. The caller must flush queues at reset.

An additive concrete overload accepts a generation captured at enqueue time:

```swift
let frameGeneration = clock.generation
// Store frameGeneration alongside the frame, before any later seek.
let decision = clock.decide(videoPTS: pts, hostTime: host,
                            generation: frameGeneration)
```

Seek and reset advance generation. An old-generation frame always drops, even if
never evaluated before seek. New-generation frames with identical PTS work. The
overload bypasses conservative PTS invalidation. Do not relabel queued frames
with the current generation after a seek. A UInt64 generation must not be reused
across 2^64 resets/seeks while an old frame survives.

Missing acceptance input: approval to require epoch-tagged frames, or a caller
queue-flush contract that guarantees no pre-seek frame reaches the PTS-only API.
The tests demonstrate the PTS-only ambiguity rather than hide it. No universal
pre-seek-frame guarantee is claimed for the untagged protocol.

## Fixtures and evidence

The three named JSON fixtures are compact input definitions, expanded by tests:
0 through 600000 inclusive in 1 ms ticks; audio every 10 ms; sequential video PTS
at 40 ms spacing. Five seeks occur at host 60, 150, 240, 360, 480 seconds to media
10, 300, 20, 500, 100 seconds. Video cadence restarts at the seek target. Distinct
pending probe PTS values use leads 123 through 127 ms. Tests drain due frames in
order and retain early frames for another tick. Boundary JSON covers early,
on-time, exact 40 ms, just-inside, and just-outside decisions.

Every presented frame is recorded in `Evidence/*.evidence.json`, including PTS,
master time, offset, host tick and segment. Seek evidence records tick-1,
seek-immediate, and tick+1 media samples, target, pending PTS and generations.
Segment drift is abs(last presented offset - first presented offset), not a
hardcoded bound. An independent formula from the input tick/audio events checks
the clock on each presentation. `summary.json` contains measured aggregates.

Eight deterministic XCTest cases passed with zero failures. Each of four full
simulations traversed 600001 virtual ticks. The untagged five-seek run has five
conservative PTS drops; the tagged run has none. Measured maximum absolute offset
is about 1 ms; maximum segment drift is about 1 ms. Exact values and counts are in
the evidence, run log and summary. These are scheduler measurements only, not
physical audio/video-device validation, rendering, or real playback acceptance.

## Integrity and scan

`SHA256SUMS` covers every payload file except itself, because a file cannot
contain its own ordinary SHA-256 digest. The accompanying archive digest covers
the entire package including this manifest. The manifest is sorted by path.
No toolchain, build cache or downloaded material is in the archive.

secret scan: clean

The included pattern scan checked every payload text/JSON file for private-key
headers, common access-token formats and credential assignments. No matches were
found. This is a bounded pattern check plus inspection, not a guarantee against
all possible secret encodings. All fixtures are synthetic public-contract data.
