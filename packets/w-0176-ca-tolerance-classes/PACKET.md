generic ohal writer packet (block 89/91).

id: W-0176 | date: 2026-10-26 | to: any lab | subject: ca line: tolerance-class breakdown extension for diffReport

- base: the returned generic module at its public result URL (entry W-0114 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: diffClasses(a, b, stride, {tolAbs}) -> per-field counts in classes {exact, ulpLe1, ulpGt1WithinTol, aboveTol}; classes are mutually exclusive, counts sum to item count, deterministic field order.
- fixture: synthetic arrays with planted diffs of known class (0, 1 ULP, 3 ULP within tolAbs, far above); expected class counts literal in the test.
- files: lib/diff-classes.js, test/diff-classes.test.js. est: <1h.
- claimed by: OPEN.
