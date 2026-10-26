generic ohal writer packet (block 89/91).

id: W-0173 | date: 2026-10-26 | to: any lab | subject: ca line: masked-diff extension for diffReport

- base: the returned generic module at its public result URL (entry W-0114 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: extend diffReport(a, b, stride, {tolAbs, mask}) where mask is an array of item indices or {field} names to exclude. masked diffs are EXCLUDED from 'within' and reported separately as masked:[{index,field}] with maskedCount; out-of-range or duplicate mask entries throw a typed error.
- fixture: synthetic arrays with a seeded outlier placed on a masked index (within must be true) and on an unmasked index (within false).
- files: extend lib/diff-report.js + test/diff-report.test.js. command: node test/diff-report.test.js. est: <1h.
- claimed by: OPEN.
