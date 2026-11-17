# arch-198w L2 - Fixture-risk report: would existing fixtures have caught a regression here?

Author: in2tinct. Date: 2026-11-17. Companion to `198w-adversarial-review-in2tinct.md` (same scope, hashes and rig cited there; bridge tip `fb828d25d5d1910f08e0c43c0b983d2d28ce1b32`). "Existing fixtures" = the photon-v4 kit/class fixture set both labs have been working against: class001 interior-flat positive-variance kit and v2/2x2 bucket-matched replay, Kits A/B/C JSON equality replays, clean-letterbox bit-identity checks, and the HDR lane integrity harnesses. Conclusion up front: **the existing set covers the two behaviors this commit advertises (interior-flat preservation, clean-letterbox suppression) and none of the regression classes the removal actually introduces.**

## Coverage matrix

| # | Behavior (evidence in companion review) | Would an existing fixture catch a regression? |
|---|------------------------------------------|------------------------------------------------|
| 1 | Interior flat content keeps grain (case A interior) | YES - class001 interior-flat positive-variance kit; this is the class under repair |
| 2 | Clean exact-black letterbox bars stay suppressed (case A top_bar) | YES - clean-letterbox bit-identity fixtures |
| 3 | Stray nonzero pixel splits edge connectivity, partial bar re-grained, boundary flickers per frame (case B, finding F1) | NO - NAMED GAP G1 |
| 4 | Full-black frames / fades fully masked (case D, F2) | NO - NAMED GAP G2 |
| 5 | Very small all-black crops fully masked (case E, F2) | NO - NAMED GAP G3 |
| 6 | Near-black bars (1/255; limited-range 16/255) grained at full amount (case F, F3) | NO - NAMED GAP G4 |
| 7 | Flat clipped-white frames now grained (case H) - silent behavior change | NO - NAMED GAP G5 |
| 8 | Source-noise attenuation "applied once, by Lua" - zero/double application (F4) | NO - NAMED GAP G6 |
| 9 | photon-shader-recovery missing at load kills the whole script (F5) | NO - NAMED GAP G7 |
| 10 | Recovery watched sourceSHA256 pairs with shipped file bytes (F6) | NO - NAMED GAP G8 |
| 11 | HUD "effective amount" matches post-attenuation shader amount (F8) | NO - NAMED GAP G9 |
| 12 | Bucket-edge straddle seam at the mask boundary (vanish list item 3) | NO - NAMED GAP G10 |
| 13 | glsl-shaders double-read window removes concurrent entries (F7) | NO - minor, G11 |

## Named gaps and proposed fixtures

Each fixture is described as input + observable + assertion. No pass targets are manufactured; where the intended policy is unset, the fixture's job is to make the behavior measured and explicit, and the lane owner sets the policy.

- **G1 noisy-bar resilience.** Input: 1080p letterbox (140px bars) with exactly one 1/255 pixel injected at a parameterized bar row, plus a noise-seeded variant (Poisson specks, density 1e-4). Observable: per-row grain gain map over the bar region. Assertion: masked fraction of the bar stays at the stated policy (e.g. >= 99% of bar rows masked) AND the masked-row set is temporally stable across a 60-frame sequence with animated noise (no per-frame flicker of the unmasked segment). Would have caught F1.
- **G2 full-black frame policy.** Input: full-black 1080p frame; 30-frame fade-to-black sequence. Observable: frame-mean grain gain per frame. Assertion: policy-explicit - either grain is intentionally off (assert gain 0 and document) or a nonzero floor applies (assert gain == floor). Would have caught F2/D as an undocumented behavior.
- **G3 small-crop sweep.** Input: all-black surfaces at 1x1, 4x4, 16x16, 64x64, 256x256 and an all-black 16x16 region upscaled to 1080p. Observable: masked fraction per size. Assertion: policy-explicit per size class (e.g. crops below some dimension are never treated as letterbox). Would have caught F2/E.
- **G4 near-black and limited-range bars.** Input: letterbox with bars at 1/255, 4/255, 16/255 (limited-range black) and bars at 0 with 1/255 Gaussian noise (sigma 0.5/255). Observable: bar-region grain gain. Assertion: bars are suppressed at all listed levels, or the gate's amplitude tolerance is documented as exactly-zero-only and the pipeline black-normalization step is cited. Would have caught F3.
- **G5 flat-white policy.** Input: flat clipped-white frame; white sky gradient clip. Observable: grain gain. Assertion: behavior change vs the old gate is measured and the intended policy recorded (the commit message is currently silent). Would have surfaced case H.
- **G6 attenuation parity sweep.** Input: synthetic noise sweep at levels straddling the old smoothstep knees (noise 0.0, 0.05, 0.20, 0.35, 0.50). Observable: effective applied grain amount per level vs the removed formula `1 - smoothstep(0.05,0.35,noise)*0.5`. Assertion: Lua-applied attenuation matches the removed shader formula exactly once (ratio 1.0 at every level, not 0 or squared). Would have caught F4 zero/double application.
- **G7 module-absent load survival.** Input: script load with photon-shader-recovery absent from the module path. Observable: script loads, grain still applies, error surfacing. Assertion: load survives with recovery disabled (soft-fail) or the hard dependency is documented and packaged. Would have caught F5.
- **G8 watched-hash pairing.** Input: the actually shipped shader file bytes. Observable: sha256 vs the recovery module's configured sourceSHA256. Assertion: equality with the shipped generation, or a documented mapping if generations intentionally differ. Would have caught F6.
- **G9 HUD truthfulness.** Input: footage at two noise levels with attenuation active. Observable: HUD effective amount vs shader-applied amount (measured from output statistics). Assertion: agreement within printed precision (4 decimals as formatted). Would have caught F8.
- **G10 bucket-edge straddle.** Input: letterboxed frame, grain phase frozen at a fixed bucket offset. Observable: per-row grain amplitude across the bar/picture boundary within one bucket height. Assertion: transition width and shape documented; no mid-bucket discontinuity beyond one transition row. Addresses vanish-list item 3.
- **G11 change-list concurrency (minor).** Input: gr_add_shader with a second script appending to glsl-shaders between the snapshot and the change-list pass (simulated via ordered calls). Observable: final list contents. Assertion: foreign entries preserved. Addresses F7.

## Bottom line

Existing fixtures (rows 1-2) green-light exactly what the commit advertises and stay silent on every regression class in rows 3-13. The two highest-priority additions are G1 (executed regression, plausible on real encodes) and G6 (unverifiable-by-design claim in the diff). G4 is third: exact-equality black is fragile against limited-range delivery unless black normalization before the hook is guaranteed and cited.
