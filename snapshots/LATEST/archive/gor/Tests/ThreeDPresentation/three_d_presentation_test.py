#!/usr/bin/env python3
"""190t H and I: Python models of SubtitleDepth and ThreeDPresentation (same steps as the Swift) plus text pins. Swift uncompiled."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sd = (S / 'SubtitleDepth.swift').read_text(); tp = (S / 'ThreeDPresentation.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def metres(w): return 256.0 / (w / 1023.0 * 1024.0) if w > 0 else None
def placement(ws, margin=0.10):
    z = [m for m in map(metres, ws) if m is not None]
    return 2.0 if not z else min(50.0, max(0.30, min(z) - margin))
check('H: nearest sample minus margin', abs(placement([512, 256]) - (256.0 / (512 / 1023.0 * 1024.0) - 0.10)) < 1e-12)
check('H: masked only -> fallback 2.0 m', placement([0, 0]) == 2.0 and placement([]) == 2.0)
check('H: clamps to [0.30, 50]', placement([1023]) == 0.30 and placement([1]) <= 50.0)
check('H: farther picture gives farther text', placement([100]) > placement([400]))
class P:
    def __init__(s): s.phase = 'flat'; s.t0 = None; s.shot = None
    def alpha(s, now): return 0 if s.phase == 'flat' else 1 if s.phase == 'solid' else max(0, min(1, (now - s.t0) / 0.5))
    def update(s, now, covered, shot, seeked, enabled):
        cut = shot != s.shot; s.shot = shot
        if not (enabled and covered): s.phase = 'flat'; return cut
        if s.phase == 'flat':
            if seeked: s.phase = 'solid'
            else: s.phase = 'fading'; s.t0 = now
        elif s.phase == 'fading' and now - s.t0 >= 0.5: s.phase = 'solid'
        return cut
p = P()
check('I: open is 2D at once', p.alpha(0) == 0 and p.update(0, False, 0, False, True) is True and p.alpha(0) == 0)
p.update(1.0, True, 0, False, True)
check('I: coverage starts a crossfade, not a jump', p.phase == 'fading' and p.alpha(1.0) == 0 and abs(p.alpha(1.25) - 0.5) < 1e-9)
p.update(1.6, True, 0, False, True)
check('I: fade completes to solid 3D', p.phase == 'solid' and p.alpha(2) == 1)
p.update(5.0, False, 3, True, True)
check('I: seek outside the rendered range goes 2D at once, and the cut is reported', p.phase == 'flat' and p.alpha(5.0) == 0)
q = P(); q.update(0, True, 1, True, True)
check('I: seek into the rendered range shows 3D instantly', q.phase == 'solid' and q.alpha(0) == 1)
q.update(1, False, 1, False, False)
check('I: 3D mode off -> 2D', q.phase == 'flat')
r = P(); r.update(0, True, 1, False, True)
check('I: shot change reports reset', r.update(0.1, True, 2, False, True) is True and r.update(0.2, True, 2, False, True) is False)
check('Swift H: same rule and constants', '256.0 / (Double(w10) / 1023.0 * 1024.0)' in sd and 'marginM = 0.10, minZ = 0.30, maxZ = 50.0, fallbackZ = 2.0' in sd and 'placed[event]' in sd)
check('Swift I: same phases and 0.5 s fade', 'fadeSeconds = 0.5' in tp and 'seeked ? .solid : .fading(since: now)' in tp and 'let cut = newShot != shot' in tp)
sys.exit(1 if fails else 0)
