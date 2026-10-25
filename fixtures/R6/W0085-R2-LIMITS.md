# W-0085 measured identifiability limits (R1 + R2, 2026-10-25)

Contract status: UNCHANGED. The requester-side ruling rejected amending the
acceptance basis. This file records what was measured so the lab does not
rediscover it.

## R1 (shipped schema: monotonic compute vs wall)
- The tested per-step compute/wall-gap methods failed on the two tested 1-vCPU hosts. Gap
  medians identical planted vs control; the first zero-false-positive gap
  threshold catches 2 of 150 planted steps. Measured on two independent hosts.
- Per-window tail compute-time density separates the 100-step window on the
  requester host (0.34 vs control max 0.08) but is marginal on the 50-step
  window (0.10) - insufficient as a basis, and NOT adopted.

## R2 (CPU-clock instrumentation; original fixture/schedule/seed/kernel untouched)
Decision clause (instrumentation separating compute from input-wait and host
contention): ACHIEVED IN THE TESTED RUNS (bounded review evidence, not a
general proof).
- t_cpu_kernel constant 0.350-0.389 ms (worker) / 0.333-0.385 ms (independent
  coordinator rerun) across EVERY arm of every run => demanded work constant.
- In the tested runs, wall/step rising while cpu/step stayed flat was
  CONSISTENT WITH the controlled competitor's descheduling; the off-CPU gap
  is not uniquely attributable to the competitor. Input-wait yield =>
  wall>>cpu inside the wait segment. The three sources separated in these
  tests.
- Handshake variant (readiness flag before step 0, schedule unchanged)
  eliminates the competitor-boot transient: phase-A gap 0.000-0.001 ms, 3/3.

Interface test (automatic window recovery, zero quiet FP): NOT PASS.
- Oracle-conditioned arm comparison (truth boundaries fed): both planted arms
  exceed every quiet arm, 6/6 worker + 6/6 independent, min margin 2.2x.
  Scoring comparison only - NOT a detector, NOT interface PASS.
- Boundary-free detectors (input = run_log.jsonl only, methods fixed a priori):
  literal per-step gap FAIL (boundary artifacts + quiet jitter FP);
  rolling-25 mean FAIL (edge smear; 2 fabricated windows on the CONTROL run);
  tail spikes weak on the short arm; 25-step block 2-means: ON(100-199) 5/6,
  ON(300-349) 1/6, spawn-transient FP eliminated only by handshake; CUSUM with
  robust scale DEGENERATES (median=MAD=0 -> whole-run alarm on all logs incl.
  control). Detection latency 5-15 ms is 30-40% of a 50-step window.
- Per-step attribution: not achieved by any tested method on the tested
  hosts (preemption lands between steps; per-step gap median 0-1 us in all
  arms of the tested runs).

## Scope of the negative result
These are failures of the TESTED methods on the TESTED 1-vCPU hosts. They do
NOT prove universal physical impossibility; an off-CPU time gap is not
uniquely attributable to the competitor; multi-core behavior NOT RUN (must be
checked on a multi-core lab host before any general claim).

This file is the standalone limit record for the shipped W-0085 fixture.
The shipped fixture bytes (w0085_toy_loop.py, w0085_competitor.py,
planted_truth.json) are the repaired versions and are UNCHANGED since the
independently reviewed fixture revision.
