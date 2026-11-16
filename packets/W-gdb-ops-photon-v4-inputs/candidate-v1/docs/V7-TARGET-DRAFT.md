# V7 draft target table

These are engineering calibration targets, not claims of correct taste for every film. Real seven-class clips are not yet pinned. No class gate may be promoted without exact clip sha256, decoded-frame/timebase/crop binding, shader hash, provider/driver identity and measured report. Class names alone are not fixtures.

Luma knots: [0, 0.05, 0.15, 0.35, 0.55, 0.75, 0.90, 1]. Initial normalized sigma_t: [0.0015, 0.003, 0.006, 0.010, 0.010, 0.007, 0.004, 0.002]. Positive endpoints are a product choice to avoid zero-grain flat shadows/whites, differing from codecs that zero endpoints. Tone-domain transform must be fixed before HDR numerical acceptance. These values are provisional DR constants, not literature-prescribed values.

Class | pinned fixture | size mode | expected relation
480p DVD film | PENDING | source-match when confidence valid | max(0.6,est*H/480)
720p film | PENDING | source-match when confidence valid | max(0.6,est*H/720)
Grainy 1080p Blu-ray | PENDING | source-match | target variance floor survives source sigma>=target
Clean 1080p digital | PENDING | look fraction | max(0.6,lookFraction*H)
4K HDR | PENDING | signaled metadata/domain | numeric sigma target UNSET until transfer/domain fixed
Animation | PENDING | look fraction unless measured grain confidence | zero spatial variance must not suppress grain
B&W | PENDING | source or look by confidence | RGB grain equal, luma sigma measured

For each class H in {1080,1440,2160}. Preliminary tolerances for a synthetic stationary field: measured per-bin sigma_add within +/-10% of predicted after subtracting input, autocorrelation half-width normalized by cell_out_px within +/-10% across H. Finite-size confidence intervals and shader sampler filter may require documented tolerance revision based on repeat runs, never silent relaxation to make a corpus pass. Expected width constant is UNCALIBRATED until actual shader field is run, so no invented absolute width target.

Invariant gates independent of subjective targets: positive spatial grain variance for enabled positive amount/strength; no zero-grain interior flat regions; cell_out_px nondecreasing in H and exact source-match scaling above 0.6 floor; identical output for identical frame+bucket; outside-picture output bit-identical; manual zero yields zero synthetic delta; HDR metadata classification independent of SDR white intensity. Clipped black/white rendered RGB can bound observed sigma, so sigma is measured in unclipped working output before output-encoding/clamp and clipping is reported separately.

Use generated flats/ramps/textures only as calibration fixtures, not substitutes for the seven named real content classes. Owner V5 samples become immutable regressions after authentic samples exist; do not fabricate owner preference data.
