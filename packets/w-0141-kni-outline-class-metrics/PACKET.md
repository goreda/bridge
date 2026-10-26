# GENERIC LAB PACKET P5 - outline shape-class assignment + class median metrics
Item: a drop-in module that assigns shape classes to synthetic outline
descriptions and computes per-class-pair median offsets with explicit
tie-breaking. GENERIC piece: no product source; contracts are stated here.
Input A (synthetic outlines): JSON list of {name, rings:[[seg...]]} where seg =
{kind: line|quad, pts:[[x,y]...]} (small integers, coordinate system arbitrary
but fixed). Input B (observations): TSV "glyph\tlsb\trsb".
Interface: classify.py outlines.json -> TSV "glyph\tleft_class\tright_class";
class vocabulary = flat_stem | round | other, assigned by a STATED deterministic
rule the lab defines and documents (e.g. dominant vertical-run coverage vs
curvature coverage); unclassifiable = "other", never an exception.
medians.py pool.tsv tie_break(A|B) -> per (left_class,right_class) median
lsb/rsb; tie_break A = mean of the two middles, B = lower middle; empty class
pair = the literal token "empty"; non-finite inputs = loud refusal.
Synthetic fixtures: make_fixture.py emits ~12 invented outlines covering each
class + ties of even/odd observation counts + a non-finite negative leg, plus
golden outputs.
Test command: python3 make_fixture.py /tmp/fx && python3 classify.py /tmp/fx/outlines.json | diff - /tmp/fx/golden_classes.tsv && python3 medians.py /tmp/fx/pool.tsv A | diff - /tmp/fx/golden_medians_A.tsv
Target: returned as generic code; the integrator ports it into the product branch.
