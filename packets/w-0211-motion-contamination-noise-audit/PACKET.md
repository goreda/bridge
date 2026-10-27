generic ohal writer packet (block 89/91).

id: W-0211 | date: 2026-10-27 | to: any lab | subject: Motion contamination audit for noise (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Choose temporal fallback/abstention trigger.
- interface: audit_noise(estimator_cmd,manifest)->CSV {sigma_true,sigma_est,velocity,cut_distance,status}.
- fixture: 128 square, 120 frames; analytic subpixel edges at0/0.25/1/4px per frame,texture,cut,brightness ramp; sigma 0/4/12. Retain clean signal/noise.
- done-when: Compare spatial-patch and temporal-difference estimates. Frozen trigger tested on held-out seeds; full motion/noise/cut bias and false-positive/negative table. Noiseless moving-edge negative required. A failing method is valid output.
- dedup: Complements W-0209; do not rewrite the W-0209 estimator; use pinned callable or separate baseline.
- limits: No optical-flow weights unless their reuse terms verified. Motion residual is not automatically noise.

- claimed by: OPEN.
