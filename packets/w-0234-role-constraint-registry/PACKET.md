# W-0234 - source-bound explicit role constraint registry (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0234) through every fix/review round.

##9 / lab1: source-bound explicit role constraint registry

role_constraints.py: validate(records,expected_source,expected_model,expected_frame,known_nodes)->receipt. records {source_sha256,model_sha256,coordinate_frame,role:'baseline_anchor'|'xheight_flat'|'axis_x'|'axis_y',node_ids:list[str],target:finite,evidence_pin}. known_nodes dict id->{x,y,contour_id}. Reject unknown/duplicate node IDs, conflicting same-role targets, stale source/model/frame, missing evidence; preserve declared orientation and role. No proximity/angle qualification. Empty records yields no constraints, never auto-select. Output canonical digest of validated registry plus typed constraints consumable by axis/level modules. Tests: near-axis intentional diagonal with no role remains untouched, conflicting model evidence refused, two coincident nodes retain separate IDs.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
