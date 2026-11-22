# W-gdb-019 seek-vector replay (integration notes)

Added files (this patch):

- `SeekVectorPack.swift` - pack model (Codable), loader, pinned-vocabulary
  validation.
- `SeekVectorReplay.swift` - replay harness, `SeekVectorPlanner` protocol,
  `PinnedSeekCompositionModel` reference planner, negative control.

## Wiring (one line)

In the existing `seek-composition-tests` executable main, after the existing
composition checks (which must stay green incl. the (c4) parked case), add:

```swift
let seekVectorStatus = SeekVectorReplay.run(arguments: CommandLine.arguments)
if seekVectorStatus != 0 { exit(seekVectorStatus) }
```

With no `--seek-vectors` flag this prints a skip notice and returns 0, so the
existing suite is unchanged when the pack is not passed.

## Commands the integrator must run (NOT RUN here: no Swift toolchain)

```
swift run seek-composition-tests
swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json
swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json --negative-control
```

Expected: exit 0 on all three; the negative control must print
`FAIL SV-001: ...` and `negative-control: flipped SV-001 -> correctly FAILED
with vector id`.

To score the real orchestration instead of the reference model, implement
`SeekVectorPlanner` over `SeekOrchestration.coordinateSeekAudio(...)` and pass
it to `SeekVectorReplay.replay(pack:planner:)`.

## Pack schema conventions

acceptedTargetTicks = clamp(request.targetTicks, 0, stream.durationTicks)
+ stream.editListOffsetTicks is a PACK SCHEMA CONVENTION, not derived
from the pinned excerpt; it exists so checkers and planners score one
unambiguous number. Also recorded in the pack's top-level `conventions`.

`--negative-control` flips `pack.vectors[0]` (SV-001 in the generated
pack), not a hardcoded id.

## Known assumption

SV-011 (parked + ring reset refused -> ringResetRefusedResumed) is an
ASSUMPTION: the pinned excerpt is truncated before that branch. Confirm
against the full pinned source before treating the row as authoritative.
