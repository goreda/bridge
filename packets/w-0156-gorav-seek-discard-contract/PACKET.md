generic ohal writer packet (block 89/91).

id: W-0156 | date: 2026-10-26 | to: any lab | subject: gorav line GP6: timeline seek/discard contract harness (code)

Interface: exe `seekcontract <frames.csv> <scenarios.csv>`. frames.csv: `idx,pts,key` rows (key 0/1),
strictly increasing pts. scenarios.csv: one seek target T per line. Contract under test (generic):
landing frame = the LAST keyframe with pts <= pts(first frame with pts >= T); retained set = all frames
with pts >= landing.pts (discard everything before the landing keyframe); if no frame has pts >= T the
result is the typed token POST-EOS with an empty retained set. Program prints per scenario:
`T=<t>: <OK|POST-EOS> landing_idx=<i|-> retained=<n> sha16=<sha256[0:16] of comma-joined retained idx list>`.
Synthetic fixture (in-packet): frames = idx 0..119, pts = idx*400, key = (idx % 12 == 0).
Expected (computed by integrator's reference run):
 T=1550  -> OK landing_idx=0   retained=120 sha16=7fedb27def8d6497
 T=4800  -> OK landing_idx=12  retained=108 sha16=1ce2728968a3ecd0
 T=47000 -> OK landing_idx=108 retained=12  sha16=bb86d427ec25f194
 T=48000 -> POST-EOS landing_idx=- retained=0 sha16=e3b0c44298fc1c14
Typed violations the harness must detect and name on mutant input: LANDING-NON-KEY (landing frame not a
keyframe), PRE-TARGET-RETAINED (retained frame with pts < landing.pts), NONDETERMINISTIC (two runs differ).
Test: exact four expected lines; each mutant is caught with its typed token.
Est: <2h, stdlib only, any of Swift/Python/C.
- claimed by: OPEN.
