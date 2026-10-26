# G-T7 latency measurement harness (generic, ohal transcribe line)
Pure timestamped-event stats module + tests, <2h. Synthetic logs only.

## Interface
```js
analyze(log) -> { stages, violations }
// log: Array<{ t: number (ms), run: string, stage: string }>
// stages: per stage-name { count, p50, p90, p99, max } of (t - previous stage t) within one run, sorted input or not;
// violations: [{ run, reason }] for non-monotonic timestamps, duplicated stage within a run, run ending mid-sequence;
// percentile rule: nearest-rank on sorted samples; empty stage -> omitted (not zero-filled);
// runs are independent - a stage delta never crosses run boundaries.
```
## Synthetic fixture
fixtures/logs.json: 6 logs (clean 3-run; shuffled input order; clock regression; duplicated stage; truncated run; 20k-event stress) with expected stages/violations.
## Must-pass tests
1-6. Exact expected per fixture. 7. Property over 200 random logs: percentiles within [min,max]; violations flagged iff the structural rule breaks; output independent of input ordering.
Run: `node test/gt7-latency-harness.test.mjs`.
## Bounds
Pure statistics; no timers, no network, no real captures; proves the measurement math only - not any product latency.
## Target
Integrator ports into the transcribe line branch (assigned on return).
