#!/usr/bin/env python3
"""Independent CSV replay of calibrated apply mechanics, not optical judgment."""
import argparse
import csv
import hashlib
import math
from pathlib import Path


def read(path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f, delimiter='\t', quoting=csv.QUOTE_NONE))


def legacy(path):
    return [line.split('\t') for line in path.read_text().splitlines()
            if line.strip() and not line.startswith('#')]


def check(root, out):
    pins = read(root / 'pins.tsv')
    for pin in pins:
        assert '/' not in pin['file'] and '..' not in pin['file']
        assert hashlib.sha256((root / pin['file']).read_bytes()).hexdigest() == pin['sha256']
    binding = read(root / 'binding.tsv')[0]
    sources = read(root / 'learning_source_manifest.tsv')
    assert any(s['sha256'] == binding['font_revision'] and s['role'] == 'learning' for s in sources)
    assert not any(s['sha256'] == binding['font_revision'] and s['role'] == 'held-out' for s in sources)
    evidence = read(root / 'evidence_bindings.tsv')
    assert len(evidence) == 5 and len({r['file'] for r in evidence}) == 5
    assert all(r['font_revision'] == binding['font_revision'] and r['model_revision'] == binding['model_revision'] and r['context'] == binding['context'] for r in evidence)
    ids = {r['glyph']: int(r['gid']) for r in read(root / 'glyph_ids.tsv')}
    names = {v: k for k, v in ids.items()}
    knowledge = {r[0]: (r[1], int(r[3]), int(r[4])) for r in legacy(root / 'classes.tsv')}
    walls = {}
    for g, advance, y, l, r in legacy(root / 'walls.tsv'):
        wall = walls.setdefault(g, (float(advance), {}))
        wall[1][int(y)] = (float(l), float(r))
    cells, strata, global_gap = {}, {}, None
    for section, l, r, cases, count, value in legacy(root / 'targets.tsv'):
        if section == 'CELL':
            cells[(int(l), int(r), cases)] = float(value)
        elif section == 'STRATUM':
            strata[cases] = float(value)
        elif section == 'GLOBAL':
            global_gap = float(value)
        else:
            raise AssertionError('unknown target section')
    src = {(int(r['left_gid']), int(r['right_gid'])): r for r in read(root / 'resolved_source.tsv')}
    anchors = read(root / 'training_anchors.tsv')
    held = read(root / 'independent_holdouts.tsv')
    assert anchors and held
    keys = {(r['left_gid'], r['right_gid']) for r in anchors}
    assert not any((r['left_gid'], r['right_gid']) in keys for r in held)
    noise = max(max(float(r['absolute_error_u']), float(r['measurement_uncertainty_u'])) for r in held)
    lo, hi = min(int(r['kern_u']) for r in anchors), max(int(r['kern_u']) for r in anchors)
    ver = {(int(r['left_gid']), int(r['right_gid'])): r for r in read(root / 'verifications.tsv')}
    walls_ok = {int(r['gid']) for r in read(root / 'wall_evidence.tsv') if r['font_revision'] == binding['font_revision']}
    rows = read(out / 'concrete-pairs.tsv')
    assert len(rows) == len(ids) ** 2
    assert [(int(r['left_gid']), int(r['right_gid'])) for r in rows] == sorted((l, r) for l in names for r in names)
    for row in rows:
        l, r = int(row['left_gid']), int(row['right_gid'])
        pair = l, r
        direct = pair in src
        value, tag = None, None
        if direct:
            value, provenance = int(src[pair]['kern_u']), 'source:' + src[pair]['evidence']
            state, refusal = 'SourceUnverified', 'independent optical/full-outline acceptance absent'
            uncertainty, method = '', 'unknown-source-uncertainty'
        else:
            kl, kr = knowledge.get(names[l]), knowledge.get(names[r])
            if kl and kr:
                key = kl[1], kr[2], kl[0] + kr[0]
                if key in cells:
                    value, tag = round(cells[key]), 'cell'
                elif names[l] in walls and names[r] in walls:
                    a, b = walls[names[l]], walls[names[r]]
                    shared = set(a[1]) & set(b[1])
                    if shared:
                        gap = min(a[0] + b[1][y][0] - a[1][y][1] for y in shared)
                        value, tag = round(strata.get(key[2], global_gap) - gap), 'geom'
            provenance = 'model:' + tag if tag else 'missing-model-or-geometry'
            uncertainty, method = str(noise), 'font-global-heldout-envelope-not-pair-confidence'
            if value is None:
                state, refusal = 'MissingPrediction', 'missing model coverage or shared geometry'
            elif value < lo or value > hi:
                state, refusal = 'RejectedExtrapolation', 'outside font-local signed source envelope'
            elif abs(value) < noise:
                state, refusal = 'RejectedNoise', 'below font-local empirical noise'
            else:
                state, refusal = 'Unverifiable', 'model prediction lacks independent optical/full-outline acceptance'
        optical = geometry = residual = ''
        if pair in ver:
            v = ver[pair]
            assert int(v['kern_u']) == value
            if state in ('SourceUnverified', 'Unverifiable'):
                state, refusal = 'Verified', ''
                optical, geometry = v['optical_evidence'], v['full_geometry_evidence']
                residual, uncertainty = v['residual_u'], v['uncertainty_u']
                method = 'pair-independent:' + v['uncertainty_evidence']
        if l not in walls_ok or r not in walls_ok:
            state = 'SourceUnverified' if direct else 'Unverifiable'
            refusal, optical, geometry = 'glyph lacks verified walls', '', ''
        expect = {'kern_u': '' if value is None else str(value), 'state': state,
                  'tier': 'direct-source' if direct else 'model-derived', 'mechanism': provenance,
                  'uncertainty_method': method, 'abstain': str(state != 'Verified').lower(),
                  'refusal_reason': refusal, 'provenance': provenance,
                  'optical_evidence': optical, 'full_geometry_evidence': geometry}
        for key, val in expect.items():
            assert row[key] == val, (pair, key, row[key], val)
        for key, val in [('residual_u', residual), ('uncertainty_u', uncertainty)]:
            assert (row[key] == '') == (val == ''), (pair, key)
            if val != '':
                assert math.isfinite(float(row[key])) and float(row[key]) == float(val), (pair, key)
        constants = row['constant_sources']
        assert constants == (f'MIN_ABS_KERN=derived:max-heldout-error-or-uncertainty:{noise:g};'
                             f'CLAMP_LO=derived:min-source-anchor:{lo};CLAMP_HI=derived:max-source-anchor:{hi};'
                             'GENERATION_TARGET=CONVENTION:no-quota;ROUNDING=CONVENTION:ties-to-even;INT16=CONVENTION:OpenType-format')
    calibration = read(out / 'calibration.tsv')
    assert [(r['field'], float(r['value']), r['derivation']) for r in calibration] == [
        ('noise_floor_u', noise, 'max-heldout-error-or-uncertainty'),
        ('lower_u', lo, 'min-source-anchor'), ('upper_u', hi, 'max-source-anchor')]
    metadata = read(out / 'metadata.tsv')
    expected_meta = [(k, binding[k]) for k in ('font_revision', 'model_revision', 'context', 'dataset_kind')]
    expected_meta += [('claim', 'mechanics-only-not-optical-or-real-font-certification')]
    expected_meta += [('anchor_evidence', r['evidence']) for r in sorted(anchors, key=lambda r: r['evidence'])]
    expected_meta += [('holdout_evidence', r['evidence']) for r in sorted(held, key=lambda r: r['evidence'])]
    assert [(r['field'], r['value']) for r in metadata] == expected_meta
    verified = read(out / 'verified-pairs.tsv')
    expected = [(r['left_gid'], r['right_gid'], r['kern_u']) for r in rows if r['abstain'] == 'false']
    assert [(r['left_gid'], r['right_gid'], r['kern_u']) for r in verified] == expected
    assert all(r['locked'] == 'true' for r in verified)
    return len(rows), len(verified)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('input', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--repeat-output', type=Path, required=True)
    a = p.parse_args()
    n, verified = check(a.input, a.output)
    check(a.input, a.repeat_output)
    for name in ('concrete-pairs.tsv', 'verified-pairs.tsv', 'calibration.tsv', 'metadata.tsv'):
        assert (a.output / name).read_bytes() == (a.repeat_output / name).read_bytes(), name
    print(f'independent-replay mechanics PASS rows={n} verified={verified}; not optical/real-font acceptance')


if __name__ == '__main__':
    main()
