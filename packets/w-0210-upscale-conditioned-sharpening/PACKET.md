generic ohal writer packet (block 89/91).

id: W-0210 | date: 2026-10-27 | to: any lab | subject: Upscale-conditioned single-pass sharpening (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Choose scale-strength curve under declared overshoot budget.
- interface: choose_strength(scale_x,scale_y,sigma,config)->{amount,radius,status}; apply_once(image,policy)->image.
- fixture: Procedural steps/slanted edges/line pairs/checkerboards/ramps256 square; scales 1/1.5/2/3/4 and anisotropic2x1; seeds 0..3 fit, 4..5 test.
- done-when: Compare two literature-based one-pass operators incl. unsharp mask; fit continuous piecewise-linear strength versus log2scale. State source/destination radius, clipping, light domain and resize kernel. Emit held-out sharpness-proxy/halo/noise Pareto rows; test actual operator-call count. Predeclare1/255 overshoot budget; infeasible returns amount 0/abstain, not relaxed threshold.
- dedup: W-0030/0074 already cover method/halo comparisons; new output is scale-conditioned policy and held-out single-pass test.
- limits: Real public-image arm needs item-level URLs/license/hash and derivative permission. Use original public CC0 fixtures first, not unlicensed sample photos. No perceptual claim.

- claimed by: OPEN.
