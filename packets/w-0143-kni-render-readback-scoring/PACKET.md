# GENERIC LAB PACKET P7 - rendered-pixel readback scorer (synthetic bitmaps)
Item: a drop-in scorer that compares two equal-size grayscale bitmaps and emits
a bounded difference score with typed threshold verdicts. GENERIC piece: no
fonts, no captures, no renderers; bitmaps are procedural PGM (ASCII P2) files
the lab generates.
Interface: score_readback.py A.pgm B.pgm --threshold-max-frac F --threshold-max-abs A
-> typed rows: dims, pixels_total, pixels_differing, max_abs_delta,
frac_differing, verdict(PASS|FAIL) plus refusal rows.
Refusals (loud, rc nonzero): dimension mismatch, non-grayscale/depth>255,
NaN/blank file, threshold outside (0,1] / [0,255].
Rules: integer arithmetic only where possible; no smoothing, no heuristics -
the score is the stated metric, nothing fancier. Identical inputs must score
exactly 0 differing pixels with verdict PASS.
Synthetic fixtures: make_fixture.py emits 64x48 PGM pairs: identical, one-pixel
diff, block diff, dimension mismatch, 16-bit depth, blank file; golden outputs.
Test command: python3 make_fixture.py /tmp/fx && python3 score_readback.py /tmp/fx/a.pgm /tmp/fx/b.pgm --threshold-max-frac 0.01 --threshold-max-abs 32 | diff - /tmp/fx/golden_rows.txt && python3 run_refusal_legs.py /tmp/fx
Target: returned as generic code; the integrator wires it to the product render readback.
