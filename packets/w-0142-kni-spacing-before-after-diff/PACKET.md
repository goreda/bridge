# GENERIC LAB PACKET P6 - typed before/after spacing diff reporter
Item: a drop-in reporter that compares two glyph-metric dumps and emits typed
diff rows. GENERIC piece: no product source or real fonts; dumps are synthetic.
Input: two TSV files "glyph\tlsb\trsb\tadvance" (same header, arbitrary row
order). Synthetic only, produced by the lab's fixture generator.
Interface: diff_metrics.py BASE.tsv CAND.tsv -> typed rows, one per glyph:
- "changed\t<glyph>\tlsb\t<old>\t<new>\tdelta\t<d>" (same for rsb/advance),
- "added\t<glyph>" / "removed\t<glyph>",
- a final summary row: glyphs_common, glyphs_changed, rows_changed,
  zero_change_pairs_explicit (glyphs identical must be COUNTED, not omitted).
Refusals (loud, rc nonzero): malformed header, duplicate glyph within one file,
non-numeric field, empty file. Exit 0 with a valid "no differences" summary is
a success state, never an error.
Determinism: shuffled row order in either input yields byte-identical output.
Synthetic fixtures: make_fixture.py emits base/cand pairs covering: one changed
field, one added glyph, one removed glyph, an all-identical pair, shuffled
order, and each refusal leg; golden outputs included.
Test command: python3 make_fixture.py /tmp/fx && python3 diff_metrics.py /tmp/fx/base.tsv /tmp/fx/cand.tsv | diff - /tmp/fx/golden_diff.tsv && python3 run_refusal_legs.py /tmp/fx
Target: returned as generic code; the integrator ports it into the product branch.
