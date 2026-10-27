generic ohal writer packet (block 89/91).

id: W-0209 | date: 2026-10-27 | to: any lab | subject: Per-frame noise with ten-second stability (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Select estimator plus confidence/abstention signal.
- interface: noise_series(frames,pts,config)->JSONL {index,pts,sigma_255,confidence,patch_count,status}.
- fixture: Generate 10 s at 24 fps in 854x480/1920x1080/3840x2160: flat/ramp/moving rectangles, Gaussian sigma 0/2/8/16; sigma step 5 s, cut 7 s. Pin seeds and unclipped reference; report clipped fraction.
- done-when: Compare high-pass MAD and patch-selection estimator. Report every frame, bias/MAE versus known sigma, coverage, p95 frame-change and step lag. Zero-noise flat must return 0 or explicit abstention. Freeze parameters before held-out seeds.
- dedup: W-0012/0029 broad grain studies: new output is per-frame confidence and ten-second response, not synthesis fitting.
- limits: Real-film arm still needs3 actual public-domain clip URLs, item-specific rights, hashes and10 s PTS intervals before execution. Procedural CC0 clips are not real films; real footage has no known clean reference.

- claimed by: OPEN.
