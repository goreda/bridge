# ohal/ca writer packets (credential-free, target branch ohal/ca, base main 5e1a3f9, repo zuellue/ca2, public)
Rules: no hardcoded numbers; English-only code/UI (node devtools/lang-scan.js); JS/wasm parity 1:1; no merge/deploy; do not touch root ca2.js, CNAME, presets. Gap randomness is an intentional stress test: never stabilize geometry.

## CA-1 Rust parity test (writer)
Source: wasm/src/sim.rs (patch ohal-ca-0001 recovers per-cell budget `used[]`, cap = MAXS+1 - used), JS mirror test/ca2.js lines ~455-457 (__ccU/__ccT).
Interface: sim_step exports in wasm/src/lib.rs; harness devtools/harness.js.
Test: node script that runs the same frozen cell state through (a) test/ca2core.wasm and (b) wasm built from ohal/ca (build recipe devtools/WASM-NOTES.md, plain + simd128), for ~220 steps with no births; assert per-cell displacement per step <= MAXS+1 and compare positions/velocities to the JS fallback within tolerance. Report max divergence in px as raw values. Do NOT claim byte-identical wasm: toolchain differs (my build 144859 B vs test/ 151424 B).
Target: devtools/t133-pair-budget-parity.js on ohal/ca.

## CA-2 Rust compaction/index hazard check (writer)
Question: used[] is indexed by cell index per step; check whether sim.rs swaps/removes cells mid-step (kill/fuse/birth compaction) so used[] could attach to the wrong cell. Source: wasm/src/sim.rs step(). Deliver: a failing or passing test plus a minimal fix (e.g. carry used[] with swaps) in the same patch series.

## CA-3 Harness recovery (writer)
Source lead: origin/organic-walls devtools/t130*/t132* (older). Lost local: axis extents (`ax`) in the pos dump and T130_NODRAW flag (e059ac6). Rewrite as a new commit on ohal/ca, credential-free, no owner data; measure maxStep, collision writer max, snap total on the 0.4 inject fixture with raw per-run numbers (metrics, not acceptance).

## CA-4 Velocity channel (writer, needs architect scope ruling first)
Observed |v| up to ~99 untouched by f9. Source: sim.rs velocity update after pair resolve. Not started; owner has not ruled on /test f9. Do not start without ruling.
