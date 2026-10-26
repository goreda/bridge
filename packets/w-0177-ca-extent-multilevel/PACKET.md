generic ohal writer packet (block 89/91).

id: W-0177 | date: 2026-10-26 | to: any lab | subject: ca line: multi-level sweep extension for extentOutside

- base: the returned generic module at its public result URL (entry W-0116 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: extentOutsideMulti(field, w, h, levels[], rect) -> one {left,right,top,bottom,areaOutside} per level from a SINGLE scan of the field (assert one pass: instrument the scan with a cell-visit counter in the test).
- fixture: seeded blob field; per-level expected extents computed analytically for two disk blobs at two levels.
- files: extend lib/extent-outside.js + test. est: <1h.
- claimed by: OPEN.
