# SPEED-2 hot-path harness (new files only; no existing module touched)

Writer brief SPEED-2 (2026-10-18, via parent agent): profile the Rust hot path on a
real run, report per-stage/per-crate wall clock, propose one optimization as a
separate patch. All files here are additive; nothing under this directory is linked
into any shipped artifact.

## Files

- `run_timed.py` — stage wall-clock harness. Runs `kni-pipeline` on a manifest N
  times, timestamps the binary's own `progress stageN ...` stderr markers, and
  writes per-stage wall-clock rows (`stage_times.tsv`). No code change to the
  engine; the markers already exist in `pipeline/src/main.rs`.
- `rip_sampler.rs` — ptrace sampling profiler, std-only, built with plain `rustc`
  (no Cargo, no new dependency in any crate). Attaches to every thread of a running
  pipeline process with `PTRACE_SEIZE`, samples the instruction pointer at a fixed
  rate via `PTRACE_INTERRUPT` + `PTRACE_GETREGS`, and writes raw `(ts, tid, rip_off)`
  rows. Sampling pauses each thread for microseconds per tick; measured overhead is
  reported alongside results.
- `symbolize_merge.py` — resolves raw samples against `nm -C --defined-only` of the
  exact binary that ran (PIE slide taken from `/proc/<pid>/maps` at attach time),
  folds samples into stage windows from `stage_times.tsv`, and emits
  `hotpath_by_stage_crate.tsv` (stage x crate x function).
- `profile_full_run.sh` — orchestrator: timed repeats (unsampled, pristine wall
  clock) plus one sampled run; writes all artifacts under `bench/hotpath/results/`.

## DECLARED_CONVENTION constants (provenance)

- Stage marker strings (`progress stage2 profiles`, `progress stage3 spacing`,
  `progress stage4 residual kern`, `progress stage5 assembly`,
  `progress stage6 export`): emitted by `pipeline/src/main.rs` (`eprintln!` at
  `stage2_and_beyond`); stage 1 is the window from process spawn to the stage-2
  marker (manifest parse + placeholder scan + per-glyph capture/fit). The marker
  set is read from the binary, not invented.
- Sample rate 99 Hz: conventional profiling cadence (not a divisor of any timer
  period in play); any value in 50-200 Hz is equally valid, 99 chosen once and
  pinned here so repeats are comparable.
- Timing repeats: 3 (brief asks for repeatable wall clock; 3 gives mean + spread
  without burning the shared 2-core box for an hour).

## Run

  bash bench/hotpath/profile_full_run.sh

Requires: built `target/release/kni-pipeline` (RUN.sh step 3), a tile dir, python3,
nm (binutils), rustc (for the sampler). Runs on Linux; ptrace of same-user children
must be permitted (it is on the Linux worker).
