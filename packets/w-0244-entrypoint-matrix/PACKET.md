# W-0244 - multi-entrypoint run contract matrix (exit0 never equals ready) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0244) through every fix/review round.

##19 / lab2: multi-entrypoint run contract matrix

entrypoint_matrix.py: compare(runs,expected)->{ok,violations}. runs for single_image/composition/folder each {source_sha256,engine_sha256,native_sha256,settings_digest,artifact_inventory,metric_state,identity_method,status}. expected caller defines required entries, source population, shared source/native pins and which settings intentionally differ. Enforce all entries present/nonempty outputs, anonymous/manual/automatic status separate, collection settings not silently ignored by composition; never equate exit0 with ready. Artifact inventories include master/font digest and reported glyph counts; exact declared population mapping, no assume all runs have same glyph count. Tests missing composition SB receipt, mismatched native pin, manual not recognition success, stale output path same name different digest. Pure receipts not fake actual run claim.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
