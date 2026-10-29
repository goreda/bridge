# W-0231 - authored smooth metadata cyclic binder (digest-pinned, index-exact) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0231) through every fix/review round.

##4. Authored smooth metadata cyclic binder

Module authored_smooth.py, bind(reference_nodes,sidecar)->new_nodes. Same node schema as unit1; sidecar {contour_digest:SHA256,entries:[{node_index:int,position:[x,y],type:'line'|'curve',smooth:bool}],rotation:int}. Digest is canonical JSON UTF8 sorted keys,separators(',',':'),allow_nan=False of reference_nodes INCLUDING their original order and values. Validate digest before applying; rotation maps authored index to serialized index modulo node count, document direction. Endpoint position/type must match exactly after rotation; entries cannot name off-curves, duplicate indices, missing endpoint population, or unknown indices. Only smooth flags change; coordinates/types/winding/controls untouched. Reject stale digest, mismatched rotation, bool index, invalid smooth flag; no nearest-position or proximity fallback. Support repeated coincident endpoint positions by index, never collapse. Tests: cyclic rotation binder preserves distinct coincident indices; stale geometry refused; full endpoint coverage; no mutation. This binds authored metadata only, never learns smoothness from shape.


## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

NOTE: contract v2 amendment 2026-10-29 03:10 +03 under the same id: the earlier API ambiguity is RESOLVED - the actual stub signature is authoritative (W-0229: verify takes integer_export=False; W-0230: validate_levels takes expected_source_sha256/expected_coordinate_frame and transform {source_sha256,coordinate_frame,origin_fu,scale_fu_per_px,evidence_pin}). Same id, no scope change.


secret scan: clean
