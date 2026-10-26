# GENERIC LAB PACKET P9 - tiny even-odd rasterizer with golden bitmaps
Item: drop-in rasterizer: JSON rings -> fixed-grid ASCII PGM (P2), even-odd
fill rule, integer scanline math only (no antialiasing, no float accumulation).
GENERIC piece: no product outlines or renderer.
Input contract: {"grid":[W,H], "glyphs":[{"name":..., "rings":[[[x,y],...]]}]}
with integer coordinates inside the grid; ring = closed polygon, >=3 points.
Interface: rasterize.py input.json OUT_DIR -> one <name>.pgm per glyph +
index TSV "name\tW\tH\tink_pixels\tsha256-of-pgm-bytes".
Refusals (loud, rc nonzero): non-integer/out-of-grid coordinate, <3 points,
self-intersecting ring (detect by segment-intersection check), non-finite
number, empty glyph list.
Correctness pins (golden): axis-aligned square, right triangle, donut (two
rings, even-odd hole), single-pixel glyph, degenerate duplicate-point leg.
Synthetic fixtures: make_fixture.py emits the five pins + refusal legs +
golden PGM bytes.
Test command: python3 make_fixture.py /tmp/fx && python3 rasterize.py /tmp/fx/in.json /tmp/fx/out && diff -r /tmp/fx/out /tmp/fx/golden
Target: returned as generic code; the integrator wires it to readback fixtures.
