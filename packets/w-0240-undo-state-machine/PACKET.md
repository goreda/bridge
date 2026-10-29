# W-0240 - transactional undo state machine (declarative, exact-hash gated) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0240) through every fix/review round.

##15 / lab2: transactional undo state machine

undo_plan.py: next_step(transaction,current_hashes,request)->{state,operations,reason}. transaction {id,base_hashes,after_hashes,backup_hashes,state}; request apply/undo. Operations declarative only, never executes filesystem. Apply requires exact base and fresh transaction; undo restores only when current exact after state matches, backups exact base; concurrent user edits refuse preserving current files. Undo twice returns already_undone no destructive replay. Incomplete apply generates bounded recoverable state, never marks success from intended plan. Tests modified backup, partial commit, mode-only changes, new files, duplicate ID and tampered nonce; deterministic rollback order. No native migration permission created.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
