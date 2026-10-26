"""Synthetic fonts and a STAND-IN kerning writer, built in memory by script.

STAND-IN: the writer below is a reference GPOS builder (fontTools feature compiler)
used only to exercise the checker. It says nothing about any real writer.
"""
import io
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

LETTERS = "ABCDVWXYTo"


def make_original(nocmap=()):
    """Deterministic TrueType font: .notdef plus eight box glyphs, no GPOS."""
    names = [".notdef"] + list(LETTERS)
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({ord(c): c for c in LETTERS if c not in nocmap})
    glyphs = {}
    for i, n in enumerate(names):
        p = TTGlyphPen(None)
        w = 400 + 20 * i
        p.moveTo((0, 0)); p.lineTo((0, 700)); p.lineTo((w, 700)); p.lineTo((w, 0)); p.closePath()
        glyphs[n] = p.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (500 + 20 * i, 0) for i, n in enumerate(names)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "Synthetic", "styleName": "Regular"})
    fb.setupOS2()
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, created=3786825600, modified=3786825600)
    b = io.BytesIO()
    fb.save(b)
    return b.getvalue()


def standin_write(original, fea_body, extension=False):
    """Replace only the GPOS table. fea_body is feature-file text for the kern feature."""
    tmp = TTFont(io.BytesIO(original))
    lk = "lookup standin_kern%s {\n%s\n} standin_kern;" % (" useExtension" if extension else "", fea_body)
    addOpenTypeFeaturesFromString(tmp, "feature kern {\n%s\n} kern;" % lk)
    data = tmp["GPOS"].compile(tmp)
    f = TTFont(io.BytesIO(original), lazy=True, recalcTimestamp=False, recalcBBoxes=False)
    t = DefaultTable("GPOS")
    t.data = data
    f["GPOS"] = t
    out = io.BytesIO()
    f.save(out)
    return out.getvalue()


def standin_write_mutated(original, fea_body, mutate):
    """STAND-IN: like standin_write, but `mutate(gpos_table_object)` may damage the compiled structure."""
    tmp = TTFont(io.BytesIO(original))
    addOpenTypeFeaturesFromString(tmp, "feature kern {\n%s\n} kern;" % fea_body)
    mutate(tmp["GPOS"].table)
    data = tmp["GPOS"].compile(tmp)
    f = TTFont(io.BytesIO(original), lazy=True, recalcTimestamp=False, recalcBBoxes=False)
    t = DefaultTable("GPOS")
    t.data = data
    f["GPOS"] = t
    out = io.BytesIO()
    f.save(out)
    return out.getvalue()


def add_raw_table(font_bytes, tag, data):
    """STAND-IN helper for negative cases: add a raw table (for example a legacy kern table)."""
    f = TTFont(io.BytesIO(font_bytes), lazy=True, recalcTimestamp=False, recalcBBoxes=False)
    t = DefaultTable(tag)
    t.data = data
    f[tag] = t
    out = io.BytesIO()
    f.save(out)
    return out.getvalue()


def standin_write_raw(original, gpos_bytes):
    """STAND-IN: splice already-built GPOS bytes (for hand-damaged fixtures) into the original."""
    return add_raw_table(original, "GPOS", gpos_bytes)


def standin_gpos_bytes(original, fea_body):
    tmp = TTFont(io.BytesIO(original))
    addOpenTypeFeaturesFromString(tmp, "feature kern {\n%s\n} kern;" % fea_body)
    return tmp["GPOS"].compile(tmp)
