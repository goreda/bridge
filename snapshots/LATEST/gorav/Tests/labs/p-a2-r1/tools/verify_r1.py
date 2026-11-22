#!/usr/bin/env python3
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'R1Evidence'
d = json.loads((root/'adapter-five-seeks.evidence.json').read_text())
samples = d['samples']
assert d['ticks'] == 600001 and len(samples) == d['presentations'] == 15000
assert d['staleChecks'] == 90 and d['drops'] == 0
assert max(abs(s['pts']-s['master']) for s in samples) == d['maxAbsOffset']
for s in samples:
    assert s['offset'] == s['pts']-s['master']
    assert abs(s['offset']) <= .040+1e-9
    assert s['generation'] == s['segment']+1
measured=[]
for seg in range(6):
    part=[s for s in samples if s['segment']==seg]
    measured.append(abs(part[-1]['offset']-part[0]['offset']))
assert measured == d['segmentDrifts'] and max(measured) <= .040+1e-9
assert [s['tick'] for s in d['seeks']] == [60000,150000,240000,360000,480000]
assert [s['target'] for s in d['seeks']] == [10,300,20,500,100]
for s in d['seeks']:
    assert s['after'] == s['target']
    assert abs(s['next']-s['target']-.001)<1e-10
    assert s['freshGeneration'] == s['oldGeneration']+1
print('Verified R1 sample-derived metrics, five seeks, six segments, 15000 samples')
