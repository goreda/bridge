# W-0238 - source/crop/frame-bound diagnostic receipt assembler (quality_approved always False) (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0238) through every fix/review round.

##13 / lab1: source/crop/frame-bound diagnostic receipt assembler

diagnostic_receipt.py: assemble(expected,stages)->receipt. expected {run_id,source_sha256,coordinate_frame,regions:[{id,crop_sha256}]}; stages list {stage_id,source_sha256,coordinate_frame,region_results:[{id,crop_sha256,status:'ok'|'abstained'|'failed',reason,artifact_sha256}]} . Exact region populations, no duplicate stage or stale crop/source/frame; no status string self-authorizes quality. Keep per-stage status, partial/abstained output explicit, complete only nonempty population all required stagesok; quality_approved=False always. Tests partial/no-stage/empty run not complete, changed crop refused, failure not hidden by later stage, input order deterministic canonical serialization.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
