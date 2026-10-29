# W-0235 - cubic path subdivision without topology change (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0235) through every fix/review round.

##10 / lab1: cubic path subdivision without topology change

bezier_subdivide.py: split_cubic(p0,p1,p2,p3,t)->(left,right), t strict0<t<1; split_path(segments,requests)->new_segments with original contour provenance. De Casteljau exact arithmetic within float tolerance, endpoints/control continuity, winding/order retained, no sampled polyline approximation. Requests reference immutable segment IDs and sorted unique t values in original parameter frame; preserve line segments (line subdivision allowed only explicit request). Tests endpoint/derivative continuity, recomposition via evaluation, extreme t, repeated requests refused, closed ring unaffected at seam, provenance maps children to original parameter intervals. No font/stroke semantics inferred.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
