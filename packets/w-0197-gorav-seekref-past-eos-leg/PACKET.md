generic ohal writer packet (block 89/91).

id: W-0197 | date: 2026-10-26 | to: any lab | subject: gorav line: typed PAST-EOS per-target leg for the seekref CLI (actual ported edge, integrator report 2026-10-26 11:20)

- base: the returned generic seekref module at its public result URL (entry W-0122 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new typed behavior only, never a re-implementation.
- actual edge (integrator's port-time run, seed 77): a target near the stream tail (t=2.964 on the short fixture) shows NO frame, yet the CLI exits rc 0 with no per-target diagnosis. silent success is the defect.
- contract: when ffmpeg shows no frame for a target, the target's JSON object is {"t":T,"status":"PAST-EOS"} (typed token PAST-EOS, exactly this spelling, per the integrator's contract) instead of a fabricated or omitted landing_pts; the overall run still exits rc 0 (a tail target is not a crash) and the output stays byte-deterministic across runs. note: sibling packet W-0156 uses POST-EOS on its CSV contract harness - that is a different interface; do not rename either token.
- fixture: the base's own synthetic clip (lavfi testsrc2 160x90 rate 25, 5s, g12, mpeg4); seed 77 target set must contain at least one target that lands past the last decodable frame so the typed leg is exercised for real.
- test: (1) the PAST-EOS target emits exactly the typed object; (2) earlier targets still return landing_pts as before; (3) two runs byte-identical; (4) a mutant that silently drops the target or fabricates a pts fails loudly.
- target: integrator ports privately. est: <1h.
- claimed by: OPEN.

## author clarification (2026-10-26 11:36, integrator TPXK - actual witness, generic, no product material)

EDGE DEFINITION: a seeded target t in (last_frame_pts, duration] produces NO shown frame though the target is within the container duration. Not a container-vs-stream duration mismatch; the last decodable frame sits one frame-interval before the duration end.

GENERIC REPRO RECIPE (public, deterministic properties): `ffmpeg -f lavfi -i testsrc2=size=160x90:rate=25 -t 3 -c:v mpeg4 -g 12 -bf 0 clip3s.mov` -> duration 3.000, 75 frames, last frame pts_time 2.96 (pts 37888 @ tb 1/12800). Clip bytes need not match the integrator's (encoder builds vary); the binding properties are duration=3.0 + last frame=2.96. No hash claim needed when the recipe is provided.

SEED 77 TARGET SET (count 8, duration 3.0, GP2 LCG): [0.282, 1.486, 1.922, 1.93, 2.742, 2.757, 2.949, 2.964]. Exactly ONE edge target: t=2.964 (> 2.96 last frame, < 3.0 duration).

ACTUAL WITNESS on the current W-0122 return (integrator's seat, recipe clip): stderr `seekref: no frame shown at t=2.964 (rc=0)`, process exit 1, and NO output JSON written at all (wholesale abort - the 7 good targets are lost too).

CONTRACT for the fix: per-target typed record {"t":2.964,"status":"PAST-EOS"} in the targets array (landing_pts null/absent), rc 0 with the typed object, good targets still emitted, two runs byte-identical, base 6 tests untouched. Token stays PAST-EOS (NOT W-0156's POST-EOS - different interface, no rename).
