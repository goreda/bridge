#!/usr/bin/env python3
"""Language-agnostic capture/cmap coverage audit over a captured collection and, optionally, an exported font.

The required codepoint set is always an input (--codepoints / --codepoints-file); nothing is built in.
Classifies each required codepoint per family/style as
PRESENT (distinct source tile), PLACEHOLDER (tile byte-identical to the
style's dominant repeated tile, i.e. glyph absent from the source font) or
ABSENT (no tile captured). Never composes or invents outlines.
With --font, also checks the exported cmap: every PRESENT codepoint must be
mapped and no PLACEHOLDER/ABSENT codepoint may be mapped.
"""
import argparse, collections, hashlib, json, re, sys
from pathlib import Path

TILE = re.compile(r'__([0-9A-Fa-f]{4,6})__')


def parse_codepoints(text):
    out = []
    for tok in re.split(r'[\s,]+', text.strip()):
        if not tok:
            continue
        rng = [int(x.removeprefix('U+'), 16) for x in tok.split('-U+' if '-U+' in tok else '..')]
        out.extend(range(rng[0], rng[-1] + 1))
    return sorted(set(out))


def classify(glyph_dir, required):
    hashes = {}
    for p in Path(glyph_dir).iterdir():
        m = TILE.search(p.name)
        if m and p.suffix.lower() in ('.png', '.jpg', '.jpeg'):
            hashes.setdefault(int(m.group(1), 16), set()).add(hashlib.sha256(p.read_bytes()).hexdigest())
    count = collections.Counter(h for s in hashes.values() for h in s)
    # a repeated tile is a placeholder only if it repeats; the data decides, no fixed count
    top, n = count.most_common(1)[0] if count else (None, 0)
    out = {}
    for cp in required:
        if cp not in hashes:
            out[cp] = 'ABSENT'
        elif n > 1 and top in hashes[cp]:
            out[cp] = 'PLACEHOLDER'
        else:
            out[cp] = 'PRESENT'
    return out, {'tiles': sum(len(s) for s in hashes.values()), 'placeholder_group': n}


def audit_collection(root, required):
    rows = {}
    for fam in sorted(Path(root).iterdir()):
        if not fam.is_dir():
            continue
        for sty in sorted(fam.iterdir()):
            g = sty / 'glyph'
            if g.is_dir():
                c, meta = classify(g, required)
                rows[f'{fam.name}/{sty.name}'] = {'status': {f'U+{k:04X}': v for k, v in c.items()}, **meta}
    return rows


def check_cmap(status, font_path):
    from fontTools.ttLib import TTFont
    cmap = TTFont(font_path).getBestCmap()
    bad = []
    for k, v in status.items():
        mapped = int(k[2:], 16) in cmap
        if v == 'PRESENT' and not mapped:
            bad.append(f'{k} PRESENT but not in cmap')
        if v != 'PRESENT' and mapped:
            bad.append(f'{k} {v} but mapped (invented)')
    return bad


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--collection', required=True)
    ap.add_argument('--codepoints', help='e.g. U+00C7,U+0100-U+017F')
    ap.add_argument('--codepoints-file')
    ap.add_argument('--font')
    ap.add_argument('--style', help='family/style key for --font')
    ap.add_argument('--output')
    a = ap.parse_args()
    spec = a.codepoints or (Path(a.codepoints_file).read_text() if a.codepoints_file else None)
    if not spec:
        ap.error('give --codepoints or --codepoints-file')
    rows = audit_collection(a.collection, parse_codepoints(spec))
    rc = 0
    if a.font:
        bad = check_cmap(rows[a.style]['status'], a.font)
        rows[a.style]['cmap_violations'] = bad
        rc = 1 if bad else 0
    text = json.dumps(rows, indent=1, ensure_ascii=True) + '\n'
    Path(a.output).write_text(text) if a.output else sys.stdout.write(text)
    sys.exit(rc)
