generic ohal writer packet (block 89/91).

id: W-0179 | date: 2026-10-26 | to: any lab | subject: ca line: self-checking straddle-fixture generator for extentOutside

- base: the returned generic module at its public result URL (entry W-0116 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: makeStraddleField(w, h, rect, seed) -> {field, expected} where the generator places blobs so the {field>=level} region straddles each rect side by an exact integer number of pixels it records in 'expected'; the returned expected feeds extentOutside directly.
- self-check: the generator's own analytic expectation must match a brute-force rescan of the produced field inside the test.
- files: lib/straddle-field.js, test/straddle-field.test.js. est: <1h.
- claimed by: OPEN.
