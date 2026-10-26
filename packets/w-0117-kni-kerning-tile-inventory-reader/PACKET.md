# GENERIC LAB PACKET P1 - pair-tile inventory reader/validator
Item: a drop-in reader/validator for a pair-tile inventory TSV. GENERIC piece:
no product data, no real inventory is attached or referenced.
Input contract (the interface the lab codes against):
- TSV, header exactly: style\ttile_file\ttile_sha256\tcodepoints
- tile_file grammar: <idx>__<cp>[_<cp>...]__<sha12>.png ; cp = 4-6 uppercase hex
  digits, 1..8 codepoints per tile; sha12 = 12 lowercase hex chars.
- tile_sha256 = 64 lowercase hex chars.
Interface: reader.py INVENTORY.tsv -> per-style summary rows
(style, tile_count, distinct_codepoint_rows, multi_cp_rows, malformed_rows);
malformed names or hashes are LOUD refusals (nonzero exit, named rows), never
silently skipped.
Synthetic fixture (the lab generates it, no real data): make_fixture.py emits a
~40-row TSV with invented style names (e.g. "Alpha|One"), invented tile names
covering: normal 2-cp pairs, a 3-cp row, an 8-cp row, 2 malformed-name rows,
1 malformed-hash row. Expected output checked by diff against a golden file.
Test command: python3 make_fixture.py /tmp/fx && python3 reader.py /tmp/fx/inventory.tsv ; echo $?
(expected: summary matches golden; rc nonzero on the malformed fixture, 0 on the clean one)
Target: returned as generic code; the integrator ports it into the product branch.



## author clarification (2026-10-26, answers 1nstinct G-0407 on distinct_codepoint_rows)

distinct_codepoint_rows = the number of distinct values of the ORDERED codepoint tuple in the codepoints column. Two tiles with the identical ordered tuple (e.g. 0x59,0x6F) count once regardless of how many tile files carry it; a 3-cp tuple (0x66,0x2E,0x2019) and an 8-cp tuple are each their own distinct row. Example: tiles t1=[48,48], t2=[48,48], t3=[48,48,48] -> distinct_codepoint_rows=2, tile_count=3, multi_cp_rows=1 (rows with >2 codepoints).
