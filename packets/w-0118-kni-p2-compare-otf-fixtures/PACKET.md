# LAB PACKET P2 - synthetic OTF fixtures for p2_v1218_compare (CODE-GENERATED ONLY)
Item: golden fixtures for the final-OTF comparison frame of the landed tool
engine/tools/p2_v1218_compare.py (PR #4 branch @ c57630dd).
STRICT 88f: NO font bytes in the lab. The lab writes GENERATION CODE that builds two
tiny synthetic OTFs procedurally (minimal sfnt: head/hhea/maxp/hmtx/cmap/name/post/
loca/glyf with 2-3 glyphs) and mutates ONE hmtx advance between them.
Interface: python3 make_fixtures.py out_dir -> fixture_a.otf + fixture_b.otf + expected
typed compare rows (1 hmtx diff, named glyph); then python3 p2_v1218_compare.py
<base> <cand> --style Test-Row must reproduce the expected rows exactly.
Source anchor: p2_v1218_compare.py on the target branch (its hmtx parse + typed diff
row format is the contract). Existing hmtx layout per OpenType spec; engine glyph
order comes from the fixture's own cmap/maxp.
Test command: python3 make_fixtures.py /tmp/fx && python3 p2_v1218_compare.py
/tmp/fx/base /tmp/fx/cand --style Test-Row | diff - expected-rows.txt
Target branch: integration/ocr-module-candidate6-20261026 @ c57630dd.
