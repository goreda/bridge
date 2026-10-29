# W-0241 - bounded subprocess diagnostic runner (no shell, group kill, expected artifacts) (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0241) through every fix/review round.

##16 / lab2: bounded subprocess diagnostic runner

bounded_process.py: run(argv,timeout_s,cwd=None,env=None,max_output_bytes=...)->receipt. argv list no shell, strict positive finite timeout. Capture stdout/stderr separately, exit code, timed_out, output_truncated flags, duration; terminate child process group on timeout then bounded kill escalation, no unrelated PID killing. No success from exit0 if declared expected_artifacts absent (caller supplies expected paths separately via keyword). Never print secrets/env values; caller chooses safe argv. Tests tiny Python children success/fail/hang/child spawn/output flood; timeout cleanup verified, partial logs retained, no shell interpolation, bounded memory/output. Run only invented temp fixtures, no owner directories.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
