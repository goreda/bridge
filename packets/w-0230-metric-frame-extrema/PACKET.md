# W-0230 - baseline/x-height coordinate transform + exact analytic cubic extrema (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0230) through every fix/review round.

##3. Baseline/x-height coordinate transform and exact cubic extrema

Module metric_frame.py, transform_level(y_px,origin_fu,scale_fu_per_px)->float using origin_fu-y_px*scale (positive finite scale). validate_levels(levels,expected_source_sha256,expected_coordinate_frame,transform)->receipt. Each level also carries source_sha256 and coordinate_frame, checked against independently supplied expected values. transform is {source_sha256,coordinate_frame,origin_fu,scale_fu_per_px,evidence_pin}; its source/frame must match expected values. levels list[{role:'baseline'|'xHeight'|'capHeight'|'ascender'|'descender',y_px:finite,state:'declared'|'confirmed'|'qualified_measured',evidence_pin:SHA256}]. Do not infer semantic roles from extrema. Unknown levels absent; no omitted-to-zero default. Receipt keeps absolute output positions separate from baseline-relative semantic heights (cap/x require baseline). Reject duplicate roles, wrong source/frame bindings, nonfinite/bool inputs, incompatible level ordering (page y increases down; ascender<=cap<=xHeight<baseline<=descender where both are present). Separate cubic_extrema(p0,p1,p2,p3) solves derivative roots analytically for both axes on[0,1], including endpoints/degenerate lines. Tests: cubic y[0,-100,-100,0] minimum-75; partial levels do not invent baseline; baseline alone0 semantic not cap/x; scale/translation cases and roundtrip positions. No font writer or guessed guides.


## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

NOTE: contract v2 amendment 2026-10-29 03:10 +03 under the same id: the earlier API ambiguity is RESOLVED - the actual stub signature is authoritative (W-0229: verify takes integer_export=False; W-0230: validate_levels takes expected_source_sha256/expected_coordinate_frame and transform {source_sha256,coordinate_frame,origin_fu,scale_fu_per_px,evidence_pin}). Same id, no scope change.


secret scan: clean
