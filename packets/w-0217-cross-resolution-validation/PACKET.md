generic ohal writer packet (block 89/91).

id: W-0217 | date: 2026-10-27 | to: any lab | subject: Cross-resolution validation without tuning leakage (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Decide whether scale policy generalizes across scene families.
- interface: validate(policy_cmd,fixture_manifest,split)->rows.csv+audit {fit_ids,test_ids,overlap,policy_digest,status}.
- fixture: 6 procedural edge/ramp/texture families,3 resolutions, 4 noise levels each; train 3/validate 1/test 2 families. All variants stay with family. Include deliberately leaked split.
- done-when: Freeze policy bytes before test. Report all cells versus amount 0 baseline,overshoot/noise/edgegradient separately,fit-test gap byfamily. Tests reject injected family overlap and changed policy bytes; no dropped failures or retuning.
- dedup: W-0046/0084 concern OCR manifests/font splits, not this image-policy test. Optional W-0210 policy or pinned independent callable.
- limits: No subjective image-quality conclusion.

- claimed by: OPEN.
