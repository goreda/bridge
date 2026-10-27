file: packets/w-0218-photon-source-noise/CORRECTIONS.md, verified evidence correction on the SAME id W-0218 (coordinator actual JSON, relayed 2026-10-27 19:01 Europe/Istanbul by gdb). the pinned PROBLEM.md and manifest bytes stay unchanged; this file supersedes the one wrong claim in them.

CORRECTION 1 (supersedes "all four scene feed broadcasts are false" in PROBLEM.md): the actual event JSON shows TWO false scene-feed broadcasts (13.886s and 30.806s) followed by TWO TRUE broadcasts (30.81199s noise .7153 smooth .4076, 30.833805s smooth .4078). the first LIVE feed lands at 30.812s; the 13.886s entry is not a fallback-only terminal state. after the seek at 10.021s the first live feed arrives 20.791s later.

what stands: the run still misses the 5s expectation by a wide margin; llvmpipe backend causality is unresolved (the backlog explanation is not isolated from source wiring). the reviewer baseline C1-start and C2-postseek FAIL observations stay valid as observations; they are not proof of the wiring root cause.

separate neutrality note: the fallback shader path with noise .1 attenuates by about .963 even at base strength-mult 1, so an x1 multiplier is not an end-to-end neutrality proof. the 118c visual range expectations stand as written; no new numeric thresholds (.25s / 30 frames / 2s stale) are owner gates and none should be treated as such.

solver guidance: do not build the fix on "feed never arrives" or "fallback-only" inferences; the actual sequence is false, false, true, true with the first live value landing late. design against the corrected evidence.
