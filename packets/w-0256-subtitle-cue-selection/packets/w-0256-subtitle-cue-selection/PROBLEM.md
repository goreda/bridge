# W-0256 - gorav subtitle cue overlap selection (Q4) adversarial venue

state: candidate (awaiting solver acceptance + reviewer blind failure-cases)
solver lab: in2tinct
reviewer lab: 1nstinct
source grant: owner 2026-10-27 (block 123a) - real product source excerpts may be posted when a W- needs them.
secret scan: clean (grepped for key-like strings and known key variable names; no credentials, no user data, no fonts, no licensed bytes).

## problem (what fails, for the user)
When two or more subtitle cues are active at the same time t, the presenter must not silently stack or line-merge them, and must not drop one without a trace. The decided M2 rule (block 168, Q4): half-open intervals [start,end); one active cue renders; on overlap the LATEST-STARTING cue wins; every suppressed cue is REPORTED with its producer index. This unit is the pure-Swift selector plus its Linux venue. It needs adversarial edge-check and, if a defect is found, a fix inside this unit - before host integration wires it into the presenter.

## reproducer (real source at named pins)
- SubtitleCueSelection.swift  sha256 6756c76bb35d215ce28454a11fcf48ee24b5e69fd676ba8b94f2eef246b80b86  (the unit under review)
- main.swift                  sha256 0a6c8f618f4bd43b5a590f62c72e4de579af959481630245501336214f11a3fe  (venue; rename from q4-main)
Both attached to this packet. M2 candidate source state 4bb068cc; interface decision ref M2-INTERFACE-DECISION-2026-11-01 (coordinator, via Ops).
Run (Linux, Swift 5.10.1):  swiftc SubtitleCueSelection.swift main.swift -o q4tests && ./q4tests

## expected behaviour
9 lines "PASS <name>" then "ALL PASS 9/9", exit 0. Covered cases: no-active / single / 2-overlap / 3-overlap / equal-start tie / half-open end / half-open start / input-order independence / empty.

## exact call site and interface
Presenter-side cue selection. SubtitleCueSelectionRule.select(at:cues:) -> SubtitleSelection(activeIndex, suppressedIndices). The host's SubtitleCueProvider shim maps plan cues into CueInterval. Additive prep: NOT yet in the GorAVMetalPresenter sources pin; host wiring is routed separately and is out of scope here.

## behaviour that must not change
- goreda-owned plan/cue TYPES are not touched.
- Half-open [start,end) semantics; latest-starting wins; suppressed cues always reported with indices, ascending; nil when none active.
- Pure Swift, no Metal/AppKit/GorAVSubtitles imports; Sendable value types only.
- Any semantic change forced by an adversarial finding returns to Ops with evidence first; no silent rule edit.

## known edges to attack (from independent review)
- Equal-start tie is resolved by producer INDEX (cue.index < best.index), not by raw input order: the documented "earliest file order" holds only if the provider assigns indices monotonically in plan/file order. Confirm the shim contract or show a counterexample.
- NaN / infinite start/end seconds: contains() is false for NaN; degenerate start>end never activates. Confirm this is the intended typed behaviour.
- suppressed list ordering and duplicates under pathological overlaps.

## acceptance test
The venue above must pass unmodified, PLUS the reviewer lab's blind failure cases (written before reading any fix): e.g. tie under adversarial index assignment, 4+ way overlap, cues ending exactly when another starts, very large cue counts (performance sanity). Neither lab approval is product acceptance; Ops lands after readback.
