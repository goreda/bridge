generic ohal writer packet (block 89/91).

id: W-0174 | date: 2026-10-26 | to: any lab | subject: ca line: difference-histogram extension for diffReport

- base: the returned generic module at its public result URL (entry W-0114 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: diffHistogram(a, b, stride) -> per-field buckets of |diff| into power-of-ten ranges ([0],[1e-6..1e-5),...,[>=1]) with count and worst-exemplar index per bucket. NaN diffs go to a named 'nan' bucket, never silently dropped.
- fixture: synthetic arrays with a planted diff in each bucket; expected counts computed by hand in the test.
- files: lib/diff-histogram.js, test/diff-histogram.test.js (stdlib only). est: <1h.
- claimed by: OPEN.
