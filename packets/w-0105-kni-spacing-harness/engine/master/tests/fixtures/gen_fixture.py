#!/usr/bin/env python3
"""Decode one glyph of a CFF/OTF into the kni-master fixture text format.
usage: gen_fixture.py FONT.otf GLYPH STROKE_NAMES_COMMA > out.glyph
Stroke names are given in contour order."""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
f = TTFont(sys.argv[1]); g = sys.argv[2]; names = sys.argv[3].split(',')
gs = f.getGlyphSet(); p = RecordingPen(); gs[g].draw(p)
print(f"glyph {g} {gs[g].width} {f['head'].unitsPerEm}")
i = -1
for op, a in p.value:
    if op == 'moveTo':
        i += 1; print(f"stroke {names[i]}"); print("M %g %g" % a[0])
    elif op == 'lineTo': print("L %g %g" % a[0])
    elif op == 'curveTo': print("C " + " ".join("%g %g" % q for q in a))
    elif op in ('closePath', 'endPath'): print("Z")
