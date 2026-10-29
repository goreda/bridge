# W-0230 - baseline/x-height coordinate transform + exact analytic cubic extrema (generic production-code unit 3)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0230) through every fix/review round.

## 3. Baseline/x-height coordinate transform and exact cubic extrema

Module metric_frame.py, transform_level(y_px,origin_fu,scale_fu_per_px)->float using origin_fu-y_px*scale (positive finite scale). validate_levels(levels,source_sha256,coordinate_frame,transform)->receipt. levels list[{role:'baseline'|'xHeight'|'capHeight'|'ascender'|'descender',y_px:finite,state:'declared'|'confirmed'|'qualified_measured',evidence_pin:SHA256}]. Do not infer semantic roles from extrema. Unknown levels absent; no omitted-to-zero default. Receipt keeps absolute output positions separate from baseline-relative semantic heights (cap/x require baseline). Reject duplicate roles, wrong source/frame bindings, nonfinite/bool inputs, incompatible level ordering (page y increases down; ascender<=cap<=xHeight<baseline<=descender where both are present). Separate cubic_extrema(p0,p1,p2,p3) solves derivative roots analytically for both axes on[0,1], including endpoints/degenerate lines. Tests: cubic y[0,-100,-100,0] minimum-75; partial levels do not invent baseline; baseline alone0 semantic not cap/x; scale/translation cases and roundtrip positions. No font writer or guessed guides.

## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

NOTE: requester clarification PENDING on this same id (API ambiguity, not privacy): the exact source/frame fields the validate_levels receipt must carry and how the transform argument is pinned inside it; until the clarification lands the solver must NOT guess the receipt schema - failure cases may proceed.


secret scan: clean
