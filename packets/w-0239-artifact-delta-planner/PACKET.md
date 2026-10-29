# W-0239 - artifact inventory and delta integrity planner (pure planner, no writes) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0239) through every fix/review round.

##14 / lab2: artifact inventory and delta integrity planner

artifact_delta.py: plan(base,target,payload,spent_ids,delivery_id)->delta. base/target maps normalized relative path->{sha256,mode}; payload map path->{sha256,mode} actual captured file bytes hashes supplied independently. Exact edits/adds/mode-only/noops; reject deletes unless explicit allow_deletes=False changed via program argument (default reject), path traversal/absolute/backslash/NUL/casefold collisions, stale payload/missing extras and spent delivery IDs. Never infers executable permission from suffix. Tests native/runtime paths flag requires_full_migration=True not approved changed-only; .DS_Store/scratch explicitly classified from caller policy, not blanket ignored. Pure planner no deletes/writes.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
