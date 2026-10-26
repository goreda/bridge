#!/usr/bin/env python3
"""Pinned IM Fell spacing experiment. No optical-quality winner is inferred."""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import subprocess
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
import uharfbuzz as hb

PIN = 'fe9705bbde51af802719246d4608d08d37bde956ab99d9a590da996a5221a24c'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def width(data, text):
    font = hb.Font(hb.Face(data))
    hb.ot_font_set_funcs(font)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    # Pair-fitting experiment, not ligature design. GPOS kern remains enabled.
    hb.shape(font, buf, {'kern': True, 'liga': False, 'clig': False, 'calt': False})
    if any(g.codepoint == 0 for g in buf.glyph_infos):
        raise ValueError('word contains missing glyph: ' + text)
    return sum(p.x_advance for p in buf.glyph_positions), len(buf.glyph_infos)


def save_bytes(font):
    out = io.BytesIO()
    font.save(out, reorderTables=False)
    return out.getvalue()


def bounds(font):
    gs = font.getGlyphSet()
    result = {}
    for name in font.getGlyphOrder():
        pen = BoundsPen(gs)
        font['glyf'][name].draw(pen, font['glyf'])
        result[name] = pen.bounds
    return result


def translated_glyph(font, name, dx):
    gs = font.getGlyphSet()
    pen = TTGlyphPen(gs)
    recording = DecomposingRecordingPen(gs)
    font['glyf'][name].draw(recording, font['glyf'])
    recording.replay(TransformPen(pen, (1, 0, 0, 1, dx, 0)))
    return pen.glyph()


def strip_reference(data):
    font = TTFont(io.BytesIO(data), recalcTimestamp=False)
    if 'glyf' not in font or any(t in font for t in ('fvar', 'HVAR', 'VVAR')):
        raise ValueError('adapter requires static glyf input')
    bb = {}
    for n in font.getGlyphOrder():
        g = font['glyf'][n]
        g.recalcBounds(font['glyf'])
        bb[n] = (g.xMin,g.yMin,g.xMax,g.yMax) if g.numberOfContours else None
    # Decompose composites before changing any glyph coordinate system.
    shapes = {n: translated_glyph(font, n, -(b[0] if b else 0)) for n, b in bb.items()}
    for n, g in shapes.items():
        font['glyf'][n] = g
        b = bb[n]
        font['hmtx'][n] = (round(b[2] - b[0]) if b else 0, 0)
    removed = []
    for tag in ('GPOS', 'kern', 'kerx', 'morx', 'trak', 'hdmx', 'LTSH', 'DSIG'):
        if tag in font:
            del font[tag]
            removed.append(tag)
    stripped = save_bytes(font)
    check = TTFont(io.BytesIO(stripped))
    for name in check.getGlyphOrder():
        g = check['glyf'][name]
        g.recalcBounds(check['glyf'])
        advance, lsb = check['hmtx'][name]
        if lsb != 0 or (g.numberOfContours and (g.xMin != 0 or advance != g.xMax)) or (not g.numberOfContours and advance):
            raise ValueError('strip verification failed: ' + name)
    return stripped, removed


class FlattenPen(BasePen):
    def __init__(self, gs, tolerance):
        super().__init__(gs)
        self.tolerance = tolerance
        self.rings = []
        self.ring = None
        self.point = None

    def _moveTo(self, p):
        if self.ring is not None:
            raise ValueError('unclosed contour')
        self.ring = [p]
        self.point = p

    def _lineTo(self, p):
        self.ring.append(p)
        self.point = p

    def _curveToOne(self, a, b, end):
        def flatten(p, a, b, q, depth=0):
            dx, dy = q[0]-p[0], q[1]-p[1]
            length = math.hypot(dx, dy)
            def distance(v):
                return abs((v[0]-p[0])*dy - (v[1]-p[1])*dx)/length if length else math.dist(v, p)
            if max(distance(a), distance(b)) <= self.tolerance:
                self.ring.append(q)
                return
            if depth >= 24 or len(self.ring) >= 100000:
                raise ValueError('flatten budget exhausted')
            mid = lambda u, v: ((u[0]+v[0])/2, (u[1]+v[1])/2)
            pa, ab, bq = mid(p,a), mid(a,b), mid(b,q)
            x, y = mid(pa,ab), mid(ab,bq)
            m = mid(x,y)
            flatten(p,pa,x,m,depth+1)
            flatten(m,y,bq,q,depth+1)
        flatten(self.point,a,b,end)
        self.point = end

    def _qCurveToOne(self, control, end):
        p = self.point
        a = tuple(p[i]+2*(control[i]-p[i])/3 for i in (0,1))
        b = tuple(end[i]+2*(control[i]-end[i])/3 for i in (0,1))
        self._curveToOne(a,b,end)

    def _closePath(self):
        if self.ring[-1] == self.ring[0]:
            self.ring.pop()
        if len(self.ring) >= 3:
            self.rings.append(self.ring)
        self.ring = None
        self.point = None

    def _endPath(self):
        raise ValueError('open contour')


def protocol(data, tolerance, selected_codepoints=None):
    font = TTFont(io.BytesIO(data))
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    reverse = {}
    for cp, name in sorted(cmap.items()):
        reverse.setdefault(name, cp)
    lines = ['UPM\t' + str(font['head'].unitsPerEm)]
    excluded = []
    selected_names = {cmap[cp] for cp in selected_codepoints if cp in cmap} if selected_codepoints is not None else None
    for gid, name in enumerate(font.getGlyphOrder()):
        if selected_names is not None and name not in selected_names:
            excluded.append(name)
            continue
        pen = FlattenPen(gs, tolerance)
        font['glyf'][name].draw(pen, font['glyf'])
        if not pen.rings:
            excluded.append(name)
            continue
        lines.append('G\t%s\t%d' % (name, reverse.get(name, 0xF0000+gid)))
        for ring in pen.rings:
            lines.append('R\t' + '\t'.join('%.12g,%.12g' % p for p in ring))
        lines.append('E')
    return '\n'.join(lines)+'\n', excluded


def apply_engine(stripped, response, spacing_delta=0, expected_names=None, flatten_tolerance=0):
    font = TTFont(io.BytesIO(stripped), recalcTimestamp=False)
    metrics, pairs, stats = {}, [], {}
    def nearest(v):
        return math.floor(v+0.5) if v >= 0 else math.ceil(v-0.5)
    for line in response.splitlines():
        c = line.split('\t')
        if c[0] == 'G' and len(c) == 5:
            if c[1] in metrics:
                raise ValueError('duplicate engine glyph')
            vals = [float(v) for v in c[2:]]
            if not all(math.isfinite(v) for v in vals):
                raise ValueError('nonfinite engine metrics')
            metrics[c[1]] = vals
        elif c[0] == 'K' and len(c) == 4:
            pairs.append((c[1],c[2],int(c[3])))
        elif c[0] == 'S' and len(c) == 3:
            stats[c[1]] = int(c[2])
        else:
            raise ValueError('unknown engine output')
    bb = bounds(font)
    expected = {n for n,b in bb.items() if b and b[0] < b[2] and b[1] < b[3]}
    if set(metrics) != (expected if expected_names is None else expected_names):
        raise ValueError('engine glyph coverage mismatch')
    shapes = {}
    for n,(lsb,rsb,advance) in metrics.items():
        if abs(advance-lsb-rsb-(bb[n][2]-bb[n][0])) > 2*flatten_tolerance+1e-5:
            raise ValueError('engine metrics frame mismatch')
        a, l = nearest(advance)+spacing_delta, nearest(lsb)+math.floor(spacing_delta/2)
        if not 0 <= a <= 65535 or not -32768 <= l <= 32767:
            raise ValueError('unrepresentable calibrated metrics')
        shapes[n] = translated_glyph(font,n,l-bb[n][0])
        font['hmtx'][n] = (a,l)
    for n,g in shapes.items():
        font['glyf'][n] = g
    if len({(l,r) for l,r,v in pairs}) != len(pairs):
        raise ValueError('duplicate engine pair')
    if any(l not in metrics or r not in metrics or not -32768 <= v <= 32767 for l,r,v in pairs):
        raise ValueError('invalid engine pair')
    if pairs:
        feature = 'languagesystem DFLT dflt; languagesystem latn dflt; feature kern {\n'
        feature += '\n'.join('pos \\%s \\%s %d;' % p for p in pairs)
        feature += '\n} kern;'
        addOpenTypeFeaturesFromString(font, feature)
    return save_bytes(font), stats


def run(args):
    original = Path(args.reference).read_bytes()
    if digest(original) != PIN:
        raise ValueError('reference SHA256 mismatch; expected '+PIN)
    font = TTFont(io.BytesIO(original))
    descriptions = [n.toUnicode() for n in font['name'].names if n.nameID == 10]
    if not any('Autospaced and autokerned using iKern' in s for s in descriptions):
        raise ValueError('pinned reference lacks iKern attribution')
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=False)
    words = list(dict.fromkeys([args.anchor]+args.words))
    target, count = width(original,args.anchor)
    stripped, removed = strip_reference(original)
    (out/'stripped.ttf').write_bytes(stripped)
    selected = set(map(ord,args.characters)) if args.characters is not None else None
    if selected is not None and not set(map(ord,''.join(words))).issubset(selected):
        raise ValueError('requested words outside explicit character scope')
    wire, excluded = protocol(stripped,args.flatten,selected)
    expected_names = {line.split('\t')[1] for line in wire.splitlines() if line.startswith('G\t')}
    wirepath = out/'outlines.tsv'
    wirepath.write_text(wire)
    candidates = []
    for index, (lam,dcap) in enumerate((l,d) for l in args.lambdas for d in args.dcaps):
        command = [str(Path(args.engine).resolve()), str(wirepath.resolve()), str(lam), str(dcap), str(args.row_step), str(args.jobs)]
        response_path = out/f'candidate-{index}.tsv'
        with response_path.open('w') as stdout, (out/f'candidate-{index}.stderr').open('w') as stderr:
            subprocess.run(command, stdout=stdout, stderr=stderr,text=True,timeout=args.timeout,check=True)
        response = response_path.read_text()
        base,stats = apply_engine(stripped,response,expected_names=expected_names,flatten_tolerance=args.flatten)
        raw,n = width(base,args.anchor)
        if n != count:
            raise ValueError('shaping glyph count changed')
        # Integer post-spacing is a disclosed calibration knob, never pair fitting.
        delta = round((target-raw)/n)
        calibrated,stats = apply_engine(stripped,response,delta,expected_names=expected_names,flatten_tolerance=args.flatten)
        actual,_ = width(calibrated,args.anchor)
        filename = f'candidate-{index}.ttf'
        (out/filename).write_bytes(calibrated)
        candidates.append(dict(index=index,lambda_=lam,dcap=dcap,post_advance_delta=delta,
            width_before=raw,width_after=actual,error=actual-target,stats=stats,font=filename))
    best = min(candidates,key=lambda c:(abs(c['error']),c['index']))
    candidate = (out/best['font']).read_bytes()
    pair_chars = sorted(set(''.join(words)))
    pair_rows = []
    for left in pair_chars:
        for right in pair_chars:
            ref = width(original,left+right)[0]-width(original,left)[0]-width(original,right)[0]
            ours = width(candidate,left+right)[0]-width(candidate,left)[0]-width(candidate,right)[0]
            pair_rows.append(dict(pair=left+right,reference_adjustment=ref,kni_adjustment=ours,error=ours-ref))
    (out/'pair-errors.json').write_text(json.dumps(pair_rows,indent=2)+'\n')
    report = dict(schema='kni.ikern-benchmark.v1',reference_sha256=PIN,stripped_sha256=digest(stripped),
        candidate_sha256=digest(candidate),upm=font['head'].unitsPerEm,reference_iKern_description=descriptions[0],
        removed_tables=removed,geometry_source='same pinned outlines with source LSB/RSB and kern removed',
        engine_path=str(Path(args.engine).resolve()),engine_sha256=digest(Path(args.engine).read_bytes()),
        row_step=args.row_step,flatten_tolerance=args.flatten,jobs=args.jobs,excluded_glyphs=excluded,
        population_scope='full-font' if selected is None else 'explicit-characters',characters=args.characters,engine_glyph_count=len(expected_names),
        candidates=candidates,selected=best,anchor=args.anchor,target_width=target,
        calibration_matched=abs(best['error']) <= args.tolerance,width_tolerance=args.tolerance,
        words=[dict(word=w,role='calibration' if w==args.anchor else 'held-out',reference_width=width(original,w)[0],kni_width=width(candidate,w)[0],error=width(candidate,w)[0]-width(original,w)[0]) for w in words],
        calibration_rule='uniform integer per-glyph advance delta=round((reference_anchor_width-raw_KNI_anchor_width)/anchor_glyph_count); LSB receives floor(delta/2); kern values unchanged',
        geometry_metric_tolerance=2*args.flatten+1e-5,
        pair_evaluation_characters=''.join(pair_chars),pair_count=len(pair_rows),pair_adjustment_mae=sum(abs(r['error']) for r in pair_rows)/len(pair_rows),
        quality_winner=None,quality_note='Width matching is calibration, not an optical-quality score. Whole-word visual assessment remains required.',
        export_note='Only ready pairs exported. Held/rejected/fallback pairs counted, never silently presented as solved.',
        shaping=dict(kern=True,liga=False,clig=False,calt=False))
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(report=str(out/'report.json'),matched=report['calibration_matched'],error=best['error'])))
    return 0 if report['calibration_matched'] else 3


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference',required=True)
    p.add_argument('--engine',required=True,help='compiled metrics example ikern_benchmark')
    p.add_argument('--out',required=True,help='new experiment directory')
    p.add_argument('--anchor',required=True)
    p.add_argument('--words',nargs='*',default=[])
    p.add_argument('--characters',default=None,help='explicit bounded experiment only; absent means full inked font')
    p.add_argument('--lambdas',nargs='+',type=float,default=[0.])
    p.add_argument('--dcaps',nargs='+',default=['auto'])
    p.add_argument('--row-step',type=float,default=4.)
    p.add_argument('--flatten',type=float,default=0.25)
    p.add_argument('--jobs',type=int,default=1)
    p.add_argument('--timeout',type=int,default=900)
    p.add_argument('--tolerance',type=float,default=1.)
    a=p.parse_args()
    if not a.anchor or not all(math.isfinite(x) and x > 0 for x in (a.row_step,a.flatten)) or a.jobs<1 or not math.isfinite(a.tolerance) or a.tolerance<0:
        p.error('invalid numeric policy/anchor')
    try:
        return run(a)
    except (ValueError,OSError,subprocess.SubprocessError) as e:
        p.exit(2,'IKERN-BENCHMARK-REFUSED: '+str(e)+'\n')


if __name__ == '__main__':
    raise SystemExit(main())
