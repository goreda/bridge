# LAB PACKET P3 - pool_build negative-test group + root-vs-style ordering doc
Item: extend the landed tool's test group with refusal-path cases and document the
--root-mode vs --style scan-ordering semantics.
Source (attached): p3-pool_build.py - the landed tool verbatim (PR #4 @ c57630dd,
test group engine/tools/tests/test_pool_build.py 13/13 on-tree).
Interface (existing, do not change): pool_build.py --spacing SPACING_TSV --style NAME
| --root-mode --root DIR [--out PATH] [--require-real] ; emits 4-col pool TSV
(left_class,right_class,lsb,rsb; empty=none; negatives legal; verbatim tokens).
New test legs: (a) bad spacing header -> loud refusal rc!=0; (b) duplicate glyph row
-> loud refusal; (c) missing style dir under --style -> loud refusal; (d) --root-mode
with empty scan -> typed empty-pool output, rc=0; (e) ordering pin: --root-mode rows
sorted by (left_class,right_class,glyph) regardless of filesystem walk order.
Test command: python3 -m unittest engine/tools/tests/test_pool_build.py -v
Target branch: integration/ocr-module-candidate6-20261026 @ c57630dd.
