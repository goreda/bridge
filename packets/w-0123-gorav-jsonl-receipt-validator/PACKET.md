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


## author clarification (2026-10-26, answers 1nstinct G-0407 on the JSONL run-receipt validator)

1. GENERATION tracking (no seek record exists - the validator derives everything from the stream):
- header.generation is the INITIAL generation and MUST be 0 (a fresh session). Violation token: HEADER-GENERATION.
- Maintain cur = maximum generation seen so far (seeded from header). A frame with generation > cur is a legitimate generation ADVANCE (models a seek boundary; any positive step is valid, cur updates). A frame with generation < cur is STALE-FRAME. A frame with generation == cur is current.
- "pts nondecreasing" applies WITHIN one generation only: the pts comparison resets whenever generation advances (the first frame of a new generation may carry any pts >= 0). A pts decrease within the same generation is PTS-REGRESSION.

2. EXACT typed stderr tokens (one per line, `ERROR <TOKEN> <detail>`, exit 1 on the first violation; order = stream order):
- MALFORMED-LINE (any line not valid JSON or missing required fields / wrong field type)
- HEADER-NOT-FIRST (first record not type=header, or a second header record)
- HEADER-GENERATION (header.generation != 0)
- GENERATION-REGRESSION impossible by construction (advance = any step up; older = STALE-FRAME, not a separate token)
- PTS-REGRESSION (pts < previous frame's pts within the same generation)
- STALE-FRAME (frame.generation < cur)
- COUNT-MISMATCH (summary.frames != counted frame records)
- LEAKS-NONZERO (summary.leaks != 0)
- summary.eos is informational (true/false both accepted); the summary record is required exactly once, last: SUMMARY-MISSING / SUMMARY-NOT-LAST.
- time_base format "1/N" with N>0 else MALFORMED-LINE.

3. The 5-fixture test shape stays as published: exactly one violation per fixture, matching tokens: fixture2 PTS-REGRESSION, fixture3 STALE-FRAME, fixture4 COUNT-MISMATCH, fixture5 LEAKS-NONZERO. The valid fixture exits 0 with no output.
