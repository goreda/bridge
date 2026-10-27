generic ohal writer packet (block 89/91).

id: W-0214 | date: 2026-10-27 | to: any lab | subject: Thin-stroke topology metric oracle (generic drop-in)

- rights: first runnable arm uses original procedural fixtures only, dedicated by their author to CC0-1.0. Return original code with an explicit reuse license, preferably MIT; pin dependency licenses separately. No third-party code, weights, fonts or media permission is implied. Literature access is not a reuse grant.
- return: source, generator/config, tests, exact command, versions, rights manifest, machine-readable rows, failures and measured runtime/hardware. Reject nonfinite/malformed inputs. No accounts, paid services or operations on another person's device.
- decision: Select metrics catching lost dots,breaks and merged strokes.
- interface: score_masks(ref,candidate,thresholds)->precision,recall,boundary distance,components,holes,splits,merges.
- fixture: Analytic dots,loops,diagonals,T-junctions,parallel lines0.5..3 px; remove dot/break loop/bridge/shift0.5px/background-only mutations.8 square exact and128 square AA cases.
- done-when: Pin4/8 connectivity,padding,pixel centers and coverage thresholds0.25/0.5/0.75. Ship independently derived tiny-case expectedJSON. Catch seeded topology mutations at declared thresholds; exactidentityperfect; expose disagreement with boundary metric.
- dedup: Metric module companion to the W-0198 restoration comparison, not W-0026 binarization ranking.
- limits: No glyph fonts or identity recognizer. Topology score is not OCR accuracy.

- claimed by: OPEN.
