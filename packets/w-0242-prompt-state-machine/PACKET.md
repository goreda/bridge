# W-0242 - CLI cancellation/EOF settings state machine (no-commit terminals) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0242) through every fix/review round.

##17 / lab2: CLI cancellation/EOF settings state machine

prompt_state.py: transition(state,event)->{state,decision,reason}. states awaiting_settings/awaiting_confirmation/confirmed/cancelled; events {kind:'input'|'eof'|'interrupt',value}. Settings typed lsb_add/rsb_add integer pair and optional explicit metric role map; blank means no declaration, never zero defaults. EOF/interrupt/cancel produce terminal no-commit; exact confirmation required, editing invalidates old confirmation. No OCR or metric truth inferred from user-entered labels; manual provenance explicit. Tests negative integers, partial pair, bool/fraction/NaN, invalid confirmation, reentry and cancellation between stages; no input()/device effects, actual caller can wrap.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
