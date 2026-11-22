#!/usr/bin/env python3
"""Generate compact, exact integer-tick fixture definitions, no random state."""
import json
from pathlib import Path
out = Path(__file__).resolve().parents[1] / 'Tests/AudioMasterSchedulerTests/Fixtures'
base = dict(schema=1, durationTicks=600000, tickSeconds=0.001,
            audioEveryTicks=10, videoEveryTicks=40, jitterTicks=[-2,0,2,0])
seeks = [dict(hostTick=h*1000, mediaSeconds=m, pendingLeadSeconds=0.123+i*0.001)
         for i,(h,m) in enumerate(zip([60,150,240,360,480],[10,300,20,500,100]))]
fixtures = {
    'clock-600s-25fps.json': dict(base, seeks=[]),
    'clock-five-seeks.json': dict(base, seeks=seeks),
    'clock-boundary40ms.json': dict(schema=1, hostSeconds=100, audioSeconds=100,
        cases=[dict(pts=100.001, expected='wait'),dict(pts=100,expected='present'),
               dict(pts=99.960000001,expected='present'),dict(pts=99.96,expected='present'),
               dict(pts=99.959999998,expected='drop'),dict(pts=99.9,expected='drop')])
}
for name,data in fixtures.items():
    (out/name).write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')
