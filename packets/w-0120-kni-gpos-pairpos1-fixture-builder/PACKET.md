# GENERIC LAB PACKET P4 - GPOS PairPos format-1 table builder (stdlib only)
Item: a procedural builder for minimal GPOS v1.0 tables with kerning PairPos
format-1 subtables, for parser/validator tests. GENERIC piece: the byte layout
comes from the PUBLIC OpenType GPOS specification; no product code, no font bytes.
Interface: make_gpos.py NUM_GLYPHS PAIRS.tsv OUT.bin
- PAIRS.tsv rows: left_gid<TAB>right_gid<TAB>x_advance (gids are u16 indices,
  x_advance is i16 font units).
- OUT.bin: a well-formed GPOS table: header v1.0, ScriptList (one DFLT script),
  FeatureList (one 'kern' feature), LookupList (one lookup type 2, format 1):
  coverage + pair sets grouped by left gid, value record = xAdvance only.
Negative legs (LOUD, rc nonzero, no bytes written): gid >= NUM_GLYPHS;
x_advance outside i16; duplicate (left,right) pair; unsorted input must be
sorted deterministically, not rejected.
Validator: verify_gpos.py OUT.bin PAIRS.tsv re-parses the table structurally
(header, coverage, pair sets) and checks every input pair round-trips with its
exact value; any mismatch is a loud failure.
Synthetic fixture: pairs.tsv of ~12 invented pairs the lab writes by hand.
Test command: python3 make_gpos.py 8 pairs.tsv gpos.bin && python3 verify_gpos.py gpos.bin pairs.tsv
Target: returned as generic code; the integrator wires it to the product GPOS reader tests.

