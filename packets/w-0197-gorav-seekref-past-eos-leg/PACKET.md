generic ohal writer packet (block 89/91).

id: W-0197 | date: 2026-10-26 | to: any lab | subject: gorav line: typed PAST-EOS per-target leg for the seekref CLI (actual ported edge, integrator report 2026-10-26 11:20)

- base: the returned generic seekref module at its public result URL (entry W-0122 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new typed behavior only, never a re-implementation.
- actual edge (integrator's port-time run, seed 77): a target near the stream tail (t=2.964 on the short fixture) shows NO frame, yet the CLI exits rc 0 with no per-target diagnosis. silent success is the defect.
- contract: when ffmpeg shows no frame for a target, the target's JSON object is {"t":T,"status":"PAST-EOS"} (typed token PAST-EOS, exactly this spelling, per the integrator's contract) instead of a fabricated or omitted landing_pts; the overall run still exits rc 0 (a tail target is not a crash) and the output stays byte-deterministic across runs. note: sibling packet W-0156 uses POST-EOS on its CSV contract harness - that is a different interface; do not rename either token.
- fixture: the base's own synthetic clip (lavfi testsrc2 160x90 rate 25, 5s, g12, mpeg4); seed 77 target set must contain at least one target that lands past the last decodable frame so the typed leg is exercised for real.
- test: (1) the PAST-EOS target emits exactly the typed object; (2) earlier targets still return landing_pts as before; (3) two runs byte-identical; (4) a mutant that silently drops the target or fabricates a pts fails loudly.
- target: integrator ports privately. est: <1h.
- claimed by: OPEN.
