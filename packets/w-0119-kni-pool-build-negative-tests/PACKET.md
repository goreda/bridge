# GENERIC LAB PACKET P3 - pooled-observation TSV builder + negative-test group
Item: a builder that compiles a pooled 4-column observation TSV from per-item
spacing rows, plus a loud-refusal negative-test group. GENERIC piece: the
contract below is the whole interface; no product source is attached.
Pool TSV contract (target format): header exactly
"left_class\tright_class\tlsb\trsb"; rows of verbatim tokens; the literal token
"empty" means no-class; negative values are legal; rows sorted by
(left_class, right_class, source_row) deterministically regardless of input
scan order.
Input contract (synthetic): a per-item spacing TSV with header
"glyph\tlsb\trsb\tadvance" plus a class-assignment TSV "glyph\tleft_class\tright_class".
Interface: build_pool.py --spacing SPACING.tsv --classes CLASSES.tsv --out POOL.tsv
Negative legs (all LOUD, rc nonzero, named cause on stderr):
(a) bad spacing header; (b) duplicate glyph row; (c) glyph in classes but
missing from spacing; (d) non-finite lsb/rsb token; (e) empty input scan
produces a typed header-only pool with rc=0 (NOT an error).
Determinism leg: shuffled input order yields byte-identical POOL.tsv.
Synthetic fixture: make_fixture.py emits ~25 invented glyph rows
(names g001..g025, invented classes flat/round/other), including the negative
variants as separate files.
Test command: python3 make_fixture.py /tmp/fx && python3 build_pool.py --spacing /tmp/fx/spacing.tsv --classes /tmp/fx/classes.tsv --out /tmp/fx/pool.tsv && python3 run_negative_legs.py /tmp/fx
Target: returned as generic code; the integrator ports it to the product builder.



## author clarification (2026-10-26, answers 1nstinct G-0407 on sort key + missing-glyph direction)

The sort key is the triple (left_class, right_class, glyph) compared byte-wise on the verbatim tokens; the sort is total, so ANY input row order yields byte-identical output (that is the determinism leg). A missing glyph in EITHER direction is a loud refusal: classes-without-spacing (leg c) and spacing-without-classes (unclassified input is never silently dropped) both exit nonzero naming the glyph.
