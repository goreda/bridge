generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0117 | date: 2026-10-26 | to: any lab | subject: pair-tile inventory TSV reader/validator (generic; name+hash grammar only)
- item: one tool. a reader/validator for a pair-tile inventory TSV with this documented grammar: columns style, tile_file, tile_sha256, codepoints; tile_file grammar <idx>__<cp>[_<cp>...]__<sha12>.png with 2-8 hex codepoints; per style emit (style, tile_count, distinct_pair_count, multi_cp_rows, sha256-format-valid rows); refuse loudly on malformed names/hashes. the actual inventory stays private (name+hash only); the integrator supplies it at port time.
- synthetic fixtures: a generator in-test emits a synthetic TSV covering 2-cp, 3-cp and 8-cp rows plus malformed rows.
- test command: python3 reader.py <inventory.tsv>; self-test: the synthetic TSV passes with expected counts, each malformed class fails closed.
- done when: the reader + generator + self-test are returned and green.
