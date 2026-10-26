generic ohal writer packet (block 89/91).

id: W-0182 | date: 2026-10-26 | to: any lab | subject: kni line: dual-feature GPOS table (kern + dist) builder extension

- base: the returned generic module at its public result URL (entry W-0120 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: make_gpos_dual.py NUM_GLYPHS KERN.tsv DIST.tsv OUT.bin - one GPOS v1.0 table with TWO features ('kern' and 'dist'), each its own lookup type 2 format 1; LookupList order deterministic (kern first); the base's single-pair-set logic is reused, not rewritten.
- validator: both features re-parsed; every kern pair and every dist pair round-trips with its exact value; a table claiming a feature with zero lookups is a loud failure.
- fixture: two small invented TSVs. test: build + verify command pair, green deterministically. est: <1h.
- claimed by: OPEN.
