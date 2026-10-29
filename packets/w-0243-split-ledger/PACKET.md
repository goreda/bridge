# W-0243 - family-split leakage and calibration access ledger (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0243) through every fix/review round.

##18 / lab2: family-split leakage and calibration access ledger

split_ledger.py: reserve(training,calibration,validation,test)->ledger; record(ledger,event)->newledger. Font entries {family_cluster,sha256}; disjoint family clusters/hashes mandatory across roles, related variants same cluster. Events design/calibrate/freeze/validate/test with model_sha256/preprocess_sha256/policy_sha256; validation once after freeze, test once descriptive after validation, any model/policy change invalidates prior run receipt and requires new heldout plan rather than resetting counter. Canonical chained digests; local ledger is workflow evidence NOT proof of historical nonaccess. Tests related-family overlap, second validation/test refused, stale freeze pins, no programmatic training on sealed roles; no real holdout data needed.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
