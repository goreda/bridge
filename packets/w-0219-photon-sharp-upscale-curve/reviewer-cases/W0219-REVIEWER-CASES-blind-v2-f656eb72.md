# W0219 reviewer failure cases (BLIND, v2) - 1nstinct

Delivery id: photon-sharp-curve-118g-v1. Role: reviewer. Status: PROPOSED CASES ONLY. Nothing was executed. No solver fix, source, or result was read.
Supersedes v1 (sha256 954fa04672e0c3daca2908e9b0f62adcac5d9e1c452ddc2745aadc3242262b66), an unshared draft. Do not use v1.

Inputs used (only these), sha256:
- PROBLEM.md d10de2096add90266889e869f05d625f2e9e566da2d0150708b6f45c21407707
- harness/ASSERT-118g.md cb681ca8264820b71cdfe5eb634557b256d7ab28b51a0eefe6de2780171e7fe8
- manifest 9da41a32640ab1ed08f22f9e21ae6d70da0e37a8d5a72baf05f6ad01ba567402
Not fetched: photon-sharp.lua, photon-common.lua, any solver design.

## Tag key (every case line carries one)
- [OWNER] Stated in the supplied PROBLEM/ASSERT as an owner requirement or must-not-change. A miss is a FAIL.
- [CLAIM-CONSISTENCY] Tests whether the unverified candidate claim (sqrt, clamp 0.5..2.0, m = out/src) behaves as the claim says. A miss means "claim not met", not an owner violation. Needs the solver to state the actual formula first.
- [AUTH-PROPOSAL] Authored by this reviewer. Not an owner requirement and not a gate. It becomes a FAIL only after the solver states the actual policy or geometry it chose and the behavior contradicts that statement. Until then a miss is a QUESTION for the solver.
No numeric tolerance below is an owner threshold. Tolerances shown are placeholders for the solver to replace with its own stated ones.

## Reading the claim text (conditional arithmetic, not findings)
- If the multiplier is clamp(sqrt(r), 0.5, 2.0) and the base amount is equal across films, the multiplier ratio between two films is at most 4, and 480p@1280 vs 4k@1100 is about 2.29 (r about 2.667 vs 0.509). The reported amounts 3.0601 vs 0.5566 (ratio about 5.5) would then need a per-film base difference to be explained. This is conditional: without equal-base evidence it is not a contradiction. Case C1 gathers that evidence.
- If clamped, then beyond the clamp points the multiplier is flat. That is a consequence of the claim, and needs assessment by the solver and the owner's eyes. It is not stated as an owner conflict; the supplied owner text says only that upscale raises and downscale lowers.
- PROBLEM does not give the 118c range numbers, so range questions stay open until given.

## Cases
Record for each run (ASSERT item 1): source height, output height, m, delivered PHOTON_SHARP_AMOUNT, sharp enabled, backend, mpv and libplacebo versions.

C0 [OWNER] Assertion. 480p->~1280, 1080p, 2160p->~1100. PASS needs amount(480p) >= 1.5 x amount(2160p); m>1 film above the m=1 baseline; m<1 film below it; no amount 0 and no silent-off while enabled. The packet says the assertion holds "on every run", so repeat several times and report any single miss. The count of repeats is a reviewer choice, not an owner number.

C1 [CLAIM-CONSISTENCY] Base control. Same film, same preset, vary only window size (e.g. 480p at 480 and 1280; 2160p at 2160 and 1100). If the claim is a pure multiplier on amount, amount ratio should equal multiplier ratio for the stated formula. A mismatch is evidence of a size-dependent base or extra scaling, to be explained by the solver. Also lets us check observation 1 (equal base or not).

C2 [CLAIM-CONSISTENCY] Margin. Report amount(480p@1280)/amount(2160p@1100) as a number. The owner gate is 1.5 (C0). Also sample nearby output heights for the two films, because the assertion says "about"; the sampled bands are the reviewer's choice, to show whether the pass depends on one exact size. Any margin comment is informational.

C3 [OWNER: 118c visual range must not change] Range. Solver states the 118c range, then check delivered amounts at 480p upscale stay within it. If the amount exceeds it, that is a FAIL once the range is given. No range given yet: open.

C4 [OWNER: saved look at 1:1 unchanged] Native size. At true native (480p at native, 1080p at 1080, 2160p at 2160), the delivered look equals the pre-fix look. [AUTH-PROPOSAL] The reviewer expects the amount to equal the pre-fix amount in practice, and asks the solver to state if there is any difference and why. Bit-identity and latency are not required by the owner. [AUTH-PROPOSAL] Also test output height off by 1 px and borders/OSD cases, to see the solver's stated rule for what counts as native; a jump versus gradual change is a question, not a fail.

C5 [OWNER: upscale raises] Extreme upscale beyond 2.7x (e.g. 480p to 2160, 240p to 1080). Amount rises or stays vs 2.7x per solver's policy; amount finite, not NaN/Inf, not 0. [CLAIM-CONSISTENCY] If the claim says clamp at 2.0, check the saturation occurs as stated. Whether a plateau is acceptable is for the solver to argue and for the owner's eyes.

C6 [OWNER: downscale lowers; no zero/silent-off while enabled] Extreme downscale (2160p to 270 out, window minimized or zero height). Amount lower than baseline, not 0, not NaN, no Lua error, no divide-by-zero on zero output height. [CLAIM-CONSISTENCY] check the claimed floor 0.5.

C7 [AUTH-PROPOSAL] Resize mid-playback and fullscreen toggle. Ask: after resize, does amount reflect the new geometry (no stale value), and does returning to the same size give the same amount as before (no drift)? No latency number is required. Rapid resize bursts: no Lua error or stall. FAIL only if the solver's stated behavior (e.g. "updates on next frame") is contradicted, or a Lua error/stuck old value appears (stuck value contradicts the whole purpose of OWNER up/down behavior).

C8 [AUTH-PROPOSAL] Anamorphic SAR != 1 (720x480 SAR 32:27; 1440x1080 SAR 4:3; one SAR<1). Solver must state which geometry m uses (coded or displayed, height only or both axes). The case passes if behavior matches that statement and is consistent across a SAR-tagged and the equivalent square-pixel file. Rotation metadata (90 deg): solver states which height is the source height; test against that statement. No axis is assumed correct here.

C9 [OWNER: manual floor/ceiling are manual-only, not feeding adaptive measurement] Manual override. Change manual floor/ceiling and then window size: manual values must not change the measured r or m. [AUTH-PROPOSAL] Question for the solver: does a manual ceiling bound the delivered amount after the geometric multiplier, or does the multiplier apply on top? Solver states the rule; check that the delivered value follows it, and that a user-set value is not scaled a second time unless the rule says so. Do not add owner-visible thresholds.

C10 [AUTH-PROPOSAL] Seek, cut, loop, chapter change, mid-stream resolution change. Check m is recomputed when source height changes; no frame shows amount 0 or default while sharp is enabled (that last part ties to OWNER no silent-off). Stability across a cut at constant geometry: report any change, solver explains.

C11 [AUTH-PROPOSAL] Sharp enable/disable toggle, including during resize. Off means no sharpening; on gives the amount from current geometry. Whether the very first frame after enabling is already correct is a question for the solver; the OWNER-tied part is only that the enabled state is not left at 0 or silently off.

C12 [OWNER: FACTOR stays geometry-free] Same film at different window sizes: FACTOR identical. Difference means double-scaling.

C13 [OWNER: grain/noise untouched, W-0218] Controlled equivalent input: same film, same size, same seed/time position, compare noise parameters and grain output before vs after the fix. Differences caused by different content, size or time are normal and are not a fail. Only an unexplained difference under controlled equal inputs is a FAIL.

C14 [OWNER: fine/coarse character tier unchanged] For equal inputs, tier selection identical before and after.

C15 [OWNER: no new owner-visible gates/thresholds] Diff scan: no new option, shortcut, or threshold exposed. Internal constants are not exposed gates unless surfaced in UI/config.

C16 [AUTH-PROPOSAL] Output height definition. Solver states whether output height is physical pixels or logical points, the video rectangle or the window, and how letterbox, panscan, video-zoom and HiDPI are treated. Test behavior against that statement (e.g. 1280x536 scope film in a 1280x720 window). No choice is assumed correct.

C17 [OWNER: ASSERT item 3] Backend. Record GPU or llvmpipe and mpv/libplacebo versions per run. A llvmpipe-only result is a software-render self-test, not a real-GPU verdict. [AUTH-PROPOSAL] If amount is computed in Lua, values should match across backends; report any difference.

## Scope
Proposed cases only, none executed. Solver self-tests are not runtime or product acceptance; acceptance is the owner's eyes. No accounts, spend, adoption or publication performed.
Freeze note: v2 is the blind version once main freezes it. Anything added after reading solver work must be labelled post-hoc.
