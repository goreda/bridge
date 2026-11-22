#!/usr/bin/env python3
"""Recompute reported metrics from saved samples, without invoking the scheduler."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'Evidence'
summary = {}
for path in sorted(root.glob('*.evidence.json')):
    data = json.loads(path.read_text())
    samples = data.pop('samples')
    measured = max(abs(s['pts']-s['master']) for s in samples)
    assert measured == data['maxAbsOffset']
    assert len(samples) == data['presentations']
    assert data['ticks'] == 600001
    for s in samples:
        assert s['offset'] == s['pts']-s['master']
        assert abs(s['offset']) <= .040+1e-9
    drifts = []
    for seg in sorted(set(s['segment'] for s in samples)):
        part = [s for s in samples if s['segment']==seg]
        drifts.append(abs(part[-1]['offset']-part[0]['offset']))
    assert drifts == data['segmentDrifts']
    assert max(drifts) <= .040+1e-9
    for seek in data['seeks']:
        assert abs(seek['after']-seek['target']) <= .001
        assert abs(seek['next']-seek['target']-.001) < 1e-10
        assert seek['newGeneration'] == seek['oldGeneration']+1
    summary[data['fixture']] = data
existing = json.loads((root/'summary.json').read_text())
assert summary == existing
print('Verified all sample-derived metrics in', len(summary), 'runs')
