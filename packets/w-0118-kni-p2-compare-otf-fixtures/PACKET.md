# GENERIC LAB PACKET P2 - minimal synthetic sfnt/OTF fixture generator
Item: a stdlib-only generator that builds tiny valid OTF files procedurally, for
font-diff tooling tests. GENERIC piece: no font bytes, no product code; the
byte layout follows the PUBLIC OpenType specification only.
Interface: make_fixtures.py OUT_DIR -> fixture_a.otf + fixture_b.otf +
expected-rows.txt. Both fonts: minimal sfnt with head/hhea/maxp/hmtx/cmap/
name/post/loca/glyf, exactly 3 glyphs (.notdef + two codepoints). fixture_b is
fixture_a with ONE hmtx advance changed by a known delta.
expected-rows.txt describes the expected diff output: one typed row naming the
changed glyph and the advance delta; everything else byte-identical.
Negative leg: a third output with a corrupted table directory checksum must be
rejected loudly by the lab's own validator (validate.py), rc nonzero.
Test command: python3 make_fixtures.py /tmp/fx && python3 validate.py /tmp/fx/fixture_a.otf && python3 validate.py /tmp/fx/fixture_bad.otf ; echo $?
(expected: fixtures validate clean, corrupted one refuses, expected-rows match a hand-check)
Target: returned as generic code; the integrator wires it to the product diff tool.



## author clarification (2026-10-26, answers 1nstinct G-0407 on expected-rows grammar vs byte-identity)

NO conflict. The expected diff rows are FIELD-LEVEL typed rows: "changed\t<glyph>\t<field>\t<old>\t<new>" with integer font-unit values (advance and/or lsb). Checksums/hashes NEVER appear in rows. The "everything else identical" statement is an aggregate summary row (unchanged_glyph_count, unchanged_table_list), not per-glyph hashes. fixture_b differs from fixture_a in exactly one hmtx advance (e.g. +16 units on glyph index 2); the golden expects exactly one "changed" row + the summary. Byte-identity is a property the lab's own validator may check internally, but the INTERFACE is the typed rows.
