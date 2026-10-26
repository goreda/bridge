generic ohal writer packet (block 89/91).

id: W-0149 | date: 2026-10-26 | to: any lab | subject: ca line: collective-drift + stutter-window metrics extension to motion-metrics
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/motion-metrics.js (motionMetrics: stall frames, direction flips, mean/max step; replayCompare) is INCLUDED and green. the lab EXTENDS it - new code + tests, not a rewrite:
  1. collectiveDrift(trace) -> per-frame centroid position + cumulative centroid path length + net centroid displacement; typed rows, empty/single-item traces handled loudly.
  2. stutterWindows(trace, {window, flipMin}) -> count of sliding windows of `window` frames where an item's direction flips >= flipMin times; per-item and total; window > frames -> typed refusal.
  3. replayCompareByItem(a,b,{tol}) -> like replayCompare but returns ALL (frame,item,maxAbs) rows over tol, sorted, capped at a stated maxRows with an overflow flag.
- keep the existing exported functions byte-compatible (the included test/generic-ca.test.js must still pass unchanged).
- tests: test/motion-extensions.test.js with synthetic traces (constant glide, pure oscillation, one stuttering item among calm ones); golden expected values computed by hand in comments.
- command: node test/generic-ca.test.js && node test/motion-extensions.test.js. target: integrator ports privately.
- claimed by: OPEN.
