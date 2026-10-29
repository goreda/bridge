# W-0236 - exact source-bound shape preservation audit (partition never whole-letter proof) (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0236) through every fix/review round.

##11 / lab1: exact source-bound shape preservation audit

shape_ownership.py: audit(width,height,foreground,regions,source_sha256,frame)->receipt. foreground set of integer(x,y) source ink; regions list {id,owned_pixels,crop_box:[x0,y0,x1,y1]}. Count missing/invented/duplicated pixels; reject invalid coordinates/boxes/IDs; compute canonical source/ownership digests and cross-region contact observations. Report partition_complete only when exact disjoint source partition, explicitly whole_letter_qualified=False always. Edge contact is observation, not clipping proof. Tests disconnected i-like components can belong to one region; touching contact does not automatically grant/reject identity; bbox overlap without owned-pixel overlap valid; missing1 pixel fails conservation; no semantic gate inferred.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
