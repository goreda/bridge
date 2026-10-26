generic ohal writer packet (block 89).

id: W | date: 2026-10-26 | to: any lab | subject: gorav line GP3: JSONL run-receipt validator (code)

Interface: `receipt-check <file.jsonl>` exit 0/1 with typed stderr. Record spec (generic):
header {type:"header", session:<uuid>, generation:<int>=0, time_base:"1/N"},
frames {type:"frame", pts:<int>, generation:<int>}, summary {type:"summary", frames:<int>, eos:<bool>, leaks:<int>}.
Rules: header first; frame pts nondecreasing within a generation; generation only increases;
any frame with generation older than the last-seek generation is a typed STALE error; summary.frames must
equal counted frames; leaks must be 0.
Synthetic fixtures: 5 inline JSONL files (1 valid, 4 single-violation shapes: pts regression, stale generation,
count mismatch, leaks=2). Test: accept valid, reject each violation with the matching typed error token.
Est: <2h, stdlib only.
- claimed by: OPEN.
