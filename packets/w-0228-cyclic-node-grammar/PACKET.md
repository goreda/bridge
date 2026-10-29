# W-0228 - cyclic line/cubic node grammar (decode/encode, rotation-invariant closed rings) (generic production-code unit 1)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0228) through every fix/review round.

## 1. Cyclic line/cubic node grammar

Module cyclic_nodes.py, decode(nodes)->segments and encode(segments)->nodes. Node schema {x:finite number,y:finite number,type:'line'|'curve'|'offcurve',smooth:bool}. Closed ring; every on-curve point ends an incoming segment. A line endpoint requires zero immediately preceding off-curves; cubic endpoint requires exactly two. Ring may start at any node, including an on-curve cubic endpoint whose two controls are at ring end. Reject0/1/3 controls before cubic, controls before line, all-offcurve rings, nonfinite coords, and fewer than two on-curve endpoints. Segment schema {start:[x,y],end:[x,y],controls:[]|[[x,y],[x,y]],smooth_end:bool}. Encode canonical rotation only, no reversal or winding change. Preserve all genuine line segments/closing cubic. No duplicate artificial zero-length closing segment. Return typed ValueError on malformed input, no mutation. Tests: cyclic rotations equivalent modulo rotation; decode(encode(segments)) exact geometry; two terminal controls before first curve accepted,0/1/3 rejected. Independent property tests required.

## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

secret scan: clean
