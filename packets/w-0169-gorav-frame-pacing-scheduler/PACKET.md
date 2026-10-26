generic ohal writer packet (block 89/91).

id: W-0169 | date: 2026-10-26 | to: any lab | subject: gorav line GP8: frame-pacing scheduler harness + decision-log oracle (code)

Interface: single-file exe `pacecheck --seed S --frames N --rate R`. Model a presentation scheduler:
frame i has ideal pts = i * (1e9 / rate) ns. A synthetic clock starts at 500000 ns and advances by exactly
one interval per frame (drift-free base); each frame's clock READ carries seeded noise j (documented LCG
x = (x*6364136223846793005 + 1442695040888963407) mod 2^64, draw = x >> 11; j = draw % (2*tol+1) - tol/2,
tol = interval/2, j in [-tol/2, +3tol/2] ns, NON-accumulated). Decision per frame: if now > pts + tol the
frame is LATE -> typed DROP (count it, log `i:DROP;`); otherwise SHOW scheduled at max(now, pts), clamped
to lastShown+1 if needed (never double-schedule, schedule strictly increasing).
Properties asserted every frame: (a) a frame index is shown at most once; (b) SHOW schedule times strictly
increase; (c) DROP happens only when late beyond tolerance (typed, never silent); (d) no reorder (frames
processed in index order).
Output: `final: shown=<n> drops=<n> lastSched=<t> digest=<fnv1a64-hex>` over the concatenated decision log
(`i:DROP;` / `i:SHOW<t>;`), FNV-1a/64 offset 14695981039346656037 prime 1099511628211.
Synthetic expected fixtures (frames=240, rate=25; computed by integrator's reference run):
 seed 5    -> shown=183 drops=57 lastSched=9523067619 digest=bf76da562e2817f3
 seed 99   -> shown=177 drops=63 lastSched=9560000000 digest=2e65afe807415788
 seed 2026 -> shown=174 drops=66 lastSched=9560000000 digest=1ea1c4d784b9b89b
Test: three seeds print exactly these lines, byte-identical across two runs; a mutant that shows a late
frame or double-schedules must trip a named assertion (nonzero exit).
Est: <2h, ~80 lines, Swift preferred (product language), C11/Python acceptable.
- claimed by: OPEN.
