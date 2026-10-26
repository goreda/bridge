"""Fold manifest and pre-registration (holdout protocol v3, sections 1, 4a.7, 5).
Fail closed: every problem is returned as a string, nothing is defaulted."""
import hashlib, json
from pathlib import Path

PREREG_REQUIRED = ('primary_metric', 'direction', 'abstain_rule', 'interval_method', 'interval_level',
                   'resamples', 'max_resamples', 'seed', 'budgets', 'budget_plus_fraction', 'budget_rounding', 'equal_node_gate', 'frozen_evaluator_pin',
                   'frame', 'cogate_metrics', 'min_families_for_interval', 'unit', 'settings_tried')
ITEM_REQUIRED = ('item_id', 'font_id', 'family_id', 'style_id', 'source', 'path_label', 'file_sha256')
C2_EXACT_SHA256 = 'f93db05d48c1125574aa7fdf76d4b660506135a6d17e68f3ee056e959c238535'
BUDGETS = ('current', 'plus10', 'potrace')
DIRECTIONS = ('higher_better', 'lower_better')
SOURCES = ('vector', 'image')
UNITS = ('family', 'shape')


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def validate(m):
    """Return a list of problems. Empty list means the manifest is usable."""
    p = []
    items = m.get('items')
    if not isinstance(items, list) or not items:
        return ['items missing or empty']
    ids = set()
    for i, it in enumerate(items):
        miss = [k for k in ITEM_REQUIRED if not it.get(k)]
        if miss:
            p.append(f'item {i} missing {miss}')
            continue
        if it['item_id'] in ids:
            p.append(f'duplicate item_id {it["item_id"]}')
        ids.add(it['item_id'])
        if it['source'] not in SOURCES:
            p.append(f'item {it["item_id"]} source {it["source"]!r} not in {SOURCES}')
    labels = {it.get('path_label') for it in items}
    if len(labels) > 1:
        p.append(f'several path labels in one manifest {sorted(map(str, labels))}: results are never pooled across labels')
    design = m.get('design_family')
    if not design:
        p.append('design_family missing')
    families = {it.get('family_id') for it in items if it.get('family_id')}
    if design and design not in families:
        p.append('design_family has no item in the manifest')
    reserve = m.get('reserve_family')
    if reserve is not None:
        if reserve == design:
            p.append('reserve_family equals design_family')
        elif reserve not in families:
            p.append('reserve_family has no item in the manifest')
    pr = m.get('preregistration')
    if not isinstance(pr, dict):
        p.append('preregistration missing')
    else:
        for k in PREREG_REQUIRED:
            if k not in pr or pr[k] in (None, '', []):
                p.append(f'preregistration missing {k}')
        if pr.get('budgets') != list(BUDGETS):
            p.append(f'preregistration budgets must be exactly {list(BUDGETS)} (current node count, plus fraction CONVENTION, glyph own potrace count)')
        f = pr.get('budget_plus_fraction')
        if not (isinstance(f, (int, float)) and f >= 0):
            p.append('budget_plus_fraction must be a non-negative number (CONVENTION, 0.10)')
        if pr.get('budget_rounding') not in ('floor', 'ceil'):
            p.append('budget_rounding must be floor or ceil')
        if not isinstance(pr.get('equal_node_gate'), bool):
            p.append('equal_node_gate must be true or false (preregistered)')
        if pr.get('best_prefix_rule'):
            p.append('best_prefix_rule is forbidden')
        if pr.get('direction') not in DIRECTIONS:
            p.append('preregistration direction invalid')
        if pr.get('unit') not in UNITS:
            p.append('preregistration unit invalid')
        lvl = pr.get('interval_level')
        if not (isinstance(lvl, (int, float)) and 0 < lvl < 1):
            p.append('interval_level must be in (0,1)')
        if not (isinstance(pr.get('resamples'), int) and pr.get('resamples', 0) > 0):
            p.append('resamples must be a positive integer')
        if isinstance(pr.get('resamples'), int) and isinstance(pr.get('max_resamples'), int) and pr['max_resamples'] < pr['resamples']:
            p.append('max_resamples below resamples')
        cm = pr.get('cogate_metrics')
        if isinstance(cm, dict):
            for need in ('nodes', 'c2', 'c7'):
                if need not in cm:
                    p.append(f'cogate_metrics missing {need}')
            for need in ('c2', 'c7'):
                if need in cm and not (isinstance(cm[need], list) and cm[need] and all(isinstance(x, str) and x for x in cm[need])):
                    p.append(f'cogate_metrics {need} must be a non-empty list of evaluator column names')
            fb = pr.get('equal_fidelity_epsilon')
            if fb is not None and not (isinstance(fb, (int, float)) and fb >= 0):
                p.append('equal_fidelity_epsilon fallback must be a non-negative number when given')
            for name, d in (cm.get('directions') or {}).items():
                if d not in DIRECTIONS:
                    p.append(f'cogate direction for {name} invalid')
            comps = cm.get('tdp_components') or []
            if not isinstance(comps, list):
                p.append('tdp_components must be a list')
                comps = []
            if 'total' in comps or any('total' in str(c).lower() for c in comps):
                p.append('TDP is a vector, a total component is not allowed')
        elif 'cogate_metrics' in pr:
            p.append('cogate_metrics must be an object')
    if m.get('c2_definition_sha256') != C2_EXACT_SHA256:
        p.append('c2_definition_sha256 must equal the pinned c2_exact.py sha256 ' + C2_EXACT_SHA256)
    src = m.get('potrace_budget_source')
    if not isinstance(src, dict):
        p.append('potrace_budget_source missing (hash pinned single source of truth for the glyph own potrace node count)')
    else:
        h = src.get('sha256')
        if not (isinstance(h, str) and len(h) == 64 and all(c in '0123456789abcdef' for c in h)):
            p.append('potrace_budget_source.sha256 must be a 64 hex digest')
        if not src.get('parser_pin'):
            p.append('potrace_budget_source.parser_pin missing (node count definition shared with the common count)')
        if isinstance(pr, dict) and src.get('frame') != pr.get('frame'):
            p.append('potrace_budget_source.frame differs from the preregistered frame: budget and count must share the style frame')
    if m.get('status_claim') == 'adopted' and not m.get('reserve_family'):
        p.append('adopted needs a reserve_family')
    return p


def design_hash_set(m):
    return {it['file_sha256'] for it in m['items'] if it['family_id'] == m['design_family']}


def heldout_items(m):
    return [it for it in m['items'] if it['family_id'] != m['design_family']]


def verify_files(m, root):
    """Optional: recompute file_sha256 of every item against files under root."""
    bad = []
    for it in m['items']:
        fp = Path(root) / it.get('path', '')
        if not it.get('path') or not fp.exists():
            bad.append(f'{it["item_id"]}: file missing')
        elif sha256_file(fp) != it['file_sha256']:
            bad.append(f'{it["item_id"]}: sha256 mismatch')
    return bad
