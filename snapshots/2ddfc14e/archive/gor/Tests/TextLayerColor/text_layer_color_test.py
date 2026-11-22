#!/usr/bin/env python3
"""Text pins for the equal-colour skip (Swift not compiled here, Linux only)."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, c):
    print(('PASS ' if c else 'FAIL ') + n)
    if not c: fails.append(n)
h = (lambda s:s.split('// BEGIN station-move TextLayerColor.swift\n',1)[1].split('// END station-move TextLayerColor.swift\n',1)[0])((S / 'PhotonFont.swift').read_text())
check('helper compares with CFEqual and assigns otherwise', 'CFEqual(cur, color)' in h and 'foregroundColor = color' in h)
def body(f, sig, n=40):
    t = (S / f).read_text().split('\n'); i = next(k for k, l in enumerate(t) if sig in l); return '\n'.join(t[i:i + n])
iptv = (S / 'IPTV.swift').read_text(); mus = (S / 'MusicPanel.swift').read_text()
check('IPTV row listeners use the helper', iptv.count('setForegroundIfChanged(') >= 9)
check('MusicPanel row listener uses the helper', mus.count('setForegroundIfChanged(') >= 3)
check('mouseDown/mouseUp press colours still assign directly', 'titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor' in iptv)
check('hidden guards unchanged', 'guard isEffectivelyVisible else { return }; let p = verticalProximity(radius: 180)' in iptv and 'guard isEffectivelyVisible else { return }; if selected {' in mus)
# Line ceilings retired by arch196g; helper behavior and consumers stay tested.
sys.exit(1 if fails else 0)
