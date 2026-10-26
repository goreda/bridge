# LAB PACKET P4 - GPOS PairPos1 minimal fixture builder (CODE-GENERATED ONLY)
Item: stdlib-only builder that emits minimal GPOS PairPos format-1 tables for
extraction/validation tests (88e item 1/2 test support). NO font bytes in the lab
(88f) - the lab generates tables procedurally.
Source (attached): p4-gpos_pairpos1.rs (the engine's existing PairPos1 writer - the
byte-layout CONTRACT to mirror) and p4-kerning-letters-fixture-excerpt.rs (how the
engine's own fixture tests construct GPOS inputs).
Interface: python3 make_gpos.py num_glyphs pairs.tsv out.bin where pairs.tsv is
left_gid<TAB>right_gid<TAB>x_advance ; out.bin is a valid GPOS v1.0 table with one
kern feature, PairPos subtables format 1, coverage + pair sets per the attached
writer's layout. Negative legs: gid out of range / x_advance out of i16 range ->
loud refusal, no bytes written.
Validation: the engine's kern_scope.rs reader (on target branch) must parse the
generated table and return exactly the input pairs.
Test command: python3 make_gpos.py 4 pairs.tsv gpos.bin && python3 verify_gpos.py gpos.bin pairs.tsv
Target branch: integration/ocr-module-candidate6-20261026 @ c57630dd.
