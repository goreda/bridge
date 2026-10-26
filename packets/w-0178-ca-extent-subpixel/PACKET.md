generic ohal writer packet (block 89/91).

id: W-0178 | date: 2026-10-26 | to: any lab | subject: ca line: subpixel extent refinement for extentOutside

- base: the returned generic module at its public result URL (entry W-0116 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: extentOutsideSub(field, w, h, level, rect) -> fractional-pixel extents via bilinear interpolation of the sampled field (crossing position solved linearly between the last-below and first-above samples per row/column).
- fixture: a linear ramp field where the crossing position is analytically exact (expected value a fraction like 2.5 px); integer-pixel result must differ, proving the refinement.
- files: lib/extent-subpixel.js, test/extent-subpixel.test.js. est: <2h.
- claimed by: OPEN.
