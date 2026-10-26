generic ohal writer packet (block 89/91).

id: W-0171 | date: 2026-10-26 | to: any lab | subject: gorav line GP10: A/V sync drift classifier + event-log oracle (code)

Interface: exe `driftclass --seed S --pairs N --drift-ppm P`. Synthetic paired streams on a 40ms cadence:
video pts = t + drift + jv, audio pts = t + ja; jitter ja/jv in [-4,+4] ms from the documented LCG
(x = (x*6364136223846793005 + 1442695040888963407) mod 2^64, draw = x >> 11; ja = draw%9-4, jv next draw).
Drift is TRIANGULAR: +P ppm-equivalent for the first half of the run, unwinding symmetrically in the second
half (drift_i = min(i, 2*(N/2)-i) * 40 * P // 1000 ms), so both onset and recovery occur.
Classify per pair: |delta| <= 20ms IN-SYNC; <= 80ms DRIFT-WARN; else DRIFT-HARD. Typed events appended to the
log: `<i>:HARD-ONSET;` on the first DRIFT-HARD of an episode, `<i>:RESYNC;` when a pair returns IN-SYNC after
a hard episode, plus one `<i>:<class>;` per pair, in order. Output:
`final: events=<n> digest=<fnv1a64-hex>` over the concatenated log (offset 14695981039346656037, prime
1099511628211).
Synthetic expected fixtures (pairs=120, drift-ppm=87; computed by integrator's reference run):
 seed 11  -> events=122 digest=57f514d98d67c54c
 seed 222 -> events=122 digest=a1baf26d0df6ea6a
(events = 120 classifications + exactly 1 HARD-ONSET + 1 RESYNC.)
Test: both seeds print exactly these lines deterministically; a mutant missing the onset/resync edge
detection changes the digest. Est: <2h, stdlib only.
- claimed by: OPEN.
