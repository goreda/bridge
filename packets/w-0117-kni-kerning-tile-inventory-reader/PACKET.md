# LAB PACKET P1 - kerning/ pair-tile inventory + frame-contract reader
Item: build a reader/validator over the kerning pair-tile inventory so pair-extraction
work (88e item 1) has a typed, verifiable input contract.
Source (attached): p1-kerning-tile-inventory-r1.tsv (sha d3a02d62...) - 4552 rows,
name+hash ONLY per 88f; NO tile bytes, NO captures. Columns: style, tile_file,
tile_sha256, codepoints. Name grammar: <idx>__<cp>[_<cp>...]__<sha12>.png with 2-8
codepoints (pairs, triples like f.period.quote, H runs).
Interface: parse the TSV; per style emit (style, tile_count, distinct_pair_count,
multi_cp_rows, sha256-format-valid rows); refuse loudly on malformed names/hashes.
Test command: python3 reader.py p1-kerning-tile-inventory-r1.tsv ; expected: 4552 rows,
18 styles, 0 malformed, per-style counts reproduced.
Target branch: integration/ocr-module-candidate6-20261026 @ c57630dd.
