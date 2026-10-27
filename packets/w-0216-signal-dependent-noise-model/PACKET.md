generic ohal writer packet (block 89/91).

id: W-0216 | date: 2026-10-27 | to: any lab | subject: Signal-dependent noise falsification (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Choose global sigma versus luminance-dependent variance.
- interface: fit_noise_model(clean,noisy,mask,config)->{a,b,model,status,bin_stats}; variance=a*linear_luma+b.
- fixture: 32 gray patches,constant Gaussian and count-like plus read noise,clipped highlights; known coefficients; disjoint fit/testlevels,20 seeds.
- done-when: Constrain a,b nonnegative. Report coefficient error,held-out variance residuals,interval coverage,global baseline and model-selection errors. Explicit noiseless/saturated-only/insufficientpixel negatives; report clipping bias/excluded fraction.
- dedup: W-0012/0029 grain fitting does not test signal-dependence assumption. Complements W-0209 without replacing it.
- limits: Known-reference synthetic fit and no-reference estimation remain separate; no sensor calibration claim.

- claimed by: OPEN.
