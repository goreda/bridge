#!/usr/bin/env python3
"""Read-only identity/coverage audit. Never creates or approves a median pool."""
import argparse
import csv
import hashlib
import io
import json
import shlex
from pathlib import Path
from fontTools.ttLib import TTFont
from auto_sb_class_table import HEADER


def unique(values, label):
    if len(values) != len(set(values)):
        raise ValueError('duplicate ' + label)
    return set(values)


def audit(font_bytes, table_bytes, manifest_bytes, receipt_bytes):
    manifest = manifest_bytes.decode('utf-8')
    receipt = receipt_bytes.decode('utf-8')
    glyphs = []
    for line in manifest.splitlines():
        if line.startswith('glyph '):
            fields = shlex.split(line)
            if len(fields) != 4:
                raise ValueError('malformed glyph manifest row')
            glyphs.append(fields[2])
    if not glyphs:
        raise ValueError('manifest has no glyph rows')
    manifest_ids = unique(glyphs, 'manifest glyph')
    parsed = list(csv.reader(io.StringIO(table_bytes.decode('utf-8')), delimiter='\t'))
    if not parsed or parsed[0] != HEADER:
        raise ValueError('wrong class table header')
    rows = parsed[1:]
    if any(len(r) != len(HEADER) for r in rows):
        raise ValueError('wrong class row arity')
    table_ids = unique([r[0] for r in rows], 'class glyph')
    with TTFont(io.BytesIO(font_bytes), lazy=False) as font:
        font_ids = unique(font.getGlyphOrder(), 'font glyph')
    lines = [line.split('\t') for line in receipt.splitlines()]
    receipt_ids = unique([r[1] for r in lines if r[0] == 'glyph' and len(r) > 1], 'receipt glyph')
    pins = [r[1] for r in lines if r[0] == 'manifest_pin' and len(r) == 2]
    source_sha = hashlib.sha256(manifest_bytes).hexdigest()
    flags = [r for r in lines if r[0] == 'partial_output']
    spacing = [r for r in lines if r[0] == 'spacing']
    unclassified = [(r[0], side) for r in rows for side, v in zip(('left', 'right'), r[5:7])
                    if v == 'unclassified']
    return {
        'schema': 'auto-sb-binding-audit-v1',
        'input_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in
                         [('font',font_bytes),('table',table_bytes),('manifest',manifest_bytes),('receipt',receipt_bytes)]},
        'counts': {'manifest_glyphs': len(manifest_ids), 'receipt_glyphs': len(receipt_ids),
                   'font_glyphs': len(font_ids), 'table_glyphs': len(table_ids),
                   'unclassified_sides': len(unclassified)},
        'manifest_pin_matches_receipt': pins == [source_sha],
        'table_matches_font_glyph_ids': table_ids == font_ids,
        'manifest_matches_receipt_glyph_ids': manifest_ids == receipt_ids,
        'manifest_missing_in_table': sorted(manifest_ids - table_ids),
        'extra_font_glyphs_not_in_manifest': sorted(font_ids - manifest_ids),
        'partial_output_rows': flags,
        'spacing_complete': spacing[0][1:3] if len(spacing) == 1 else 'UNMAPPED',
        # Generic fallback rows count geometry line spans, not A2 eligibility.
        'a2_solved_population': 'UNMAPPED: no A2 eligible-glyph identity receipt bound here',
        'font_receipt_execution_binding': 'UNMAPPED: matching glyph IDs are not execution provenance',
        'unclassified_sides': unclassified,
        'pool_publication': 'NOT_PERFORMED',
        'production_accepted': False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('font','table','manifest','receipt'):
        p.add_argument(name, type=Path)
    a = p.parse_args()
    print(json.dumps(audit(*(getattr(a,n).read_bytes() for n in ('font','table','manifest','receipt'))),
                     sort_keys=True, indent=2))


if __name__ == '__main__': main()
