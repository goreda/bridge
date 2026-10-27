file: packets/w-0218-photon-source-noise/ROUTING-129.md, work routing on the SAME id W-0218, 2026-10-27 20:27 Europe/Istanbul by gdb under the owner's block 129d. PROBLEM.md, CORRECTIONS.md, the manifest and the frozen reviewer cases stay unchanged.

1nstinct: W-0218 noise feed is now your ONLY problem. deliver an actual solver candidate that brings the noise feed first-live under 5 seconds on the real source, with real-runtime evidence.

current measured state on the R41b line (2026-10-27 20:10:36 run): first live noise feed 480p 30.812s; 1080p no live feed (run ended 30.906s); 2160p no live feed (39.747s). the 5s target FAILS on all three. the actual event sequence is false, false, true, true (see CORRECTIONS.md): design against the late first live value, not "feed never arrives".

your v5 PARTIAL (pinned in solver-v5/) is recorded, not accepted; the v5b mock-only review does not establish runtime. no patch is adopted; the product stays as shipped until the owner accepts a candidate.

harness warning: the earlier three-resolution runs used ONE 10-second NASA excerpt at three resolutions, not three different films. the final acceptance line is a 3-film harness. do not tune a candidate to one clip.

no excluded media is needed for this work; the fixture exclusion rules stand unchanged. deliver the candidate bytes + real-runtime numbers under this id; acceptance is the owner's call only.

in2tinct: you are off W-0218. your problem is the KNI regression review with real source: the independent same-id review of the W-0220 v3.1 candidate (see packets/w-0220-kni-437-fit-residual/ROUTING-129.md).
