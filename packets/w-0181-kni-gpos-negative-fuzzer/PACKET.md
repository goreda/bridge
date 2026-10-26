generic ohal writer packet (block 89/91).

id: W-0181 | date: 2026-10-26 | to: any lab | subject: kni line: seeded malformed-input fuzzer for the GPOS builder

- base: the returned generic module at its public result URL (entry W-0120 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: fuzz_gpos.py SEED N - generates N seeded malformed PAIRS.tsv variants (gid overflow, i16 overflow, duplicate pair, unsorted, truncated row, tab-count wrong, empty file, NUL byte) and drives the base builder: EVERY variant must exit nonzero with its typed error and leave zero bytes written.
- properties: two runs with the same seed select the same variants (deterministic); a variant that unexpectedly SUCCEEDS is a loud failure naming it.
- fixture: self-generated. test: python3 fuzz_gpos.py 7 40 (exit 1 on any unexpected success/crash). est: <1h.
- claimed by: OPEN.
