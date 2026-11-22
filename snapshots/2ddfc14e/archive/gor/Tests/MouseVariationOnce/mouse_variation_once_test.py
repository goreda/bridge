#!/usr/bin/env python3
"""H1 (heat v2, mouse-moving): SpineUI must run the OSD font-axis pass and glyph hover scan once per NSEvent, not once per
handler that sees it. Swift compiles only on gor-ci/Mac; this pins the text and runs a Python model of the guard (event stream with
duplicate deliveries: work count must equal distinct events, outputs identical to the unguarded run)."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
src = (root/'Sources/gor/UI/SpineUI.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
ext = src[src.index('func handleExternalMouseMoved'):]; ext = ext[:ext.index('func handleExternalMouseExited')]
mm = src[src.index('override func mouseMoved(with e: NSEvent)'):]; mm = mm[:mm.index('\n    }\n')]
check('mouseMoved delegates the pointer passes to handleExternalMouseMoved', 'handleExternalMouseMoved(with: e)' in mm and 'applyVariationToOSDLayers()' not in mm and 'updateGlyphHover(' not in mm)
check('external handler guards on event.timestamp before both passes', ext.index('guard e.timestamp != lastVariationEventTimestamp else { return }') < ext.index('applyVariationToOSDLayers()') < ext.index('updateGlyphHover(selfPt: pt)'))
check('guard stores the timestamp', 'lastVariationEventTimestamp = e.timestamp' in ext)
check('pointer position still published before the guard (no stale proximity)', ext.index('VariationBroadcaster.shared.update(windowPt: winPt)') < ext.index('guard e.timestamp'))
check('layout-driven callers still call applyVariationToOSDLayers directly (no stale layers)', len(re.findall(r'\n\s+(?:self\.)?applyVariationToOSDLayers\(\)', src)) >= 3)
# model: stream of (timestamp, pt); each event delivered 1 or 2 times
def run(stream, once):
    last = -1; work = []; 
    for ts, pt in stream:
        if once and ts == last: continue
        last = ts; work.append((ts, pt))
    return work
events = [(i * 0.008, (i, i % 7)) for i in range(120)]
deliveries = [e for e in events for _ in (0, 1)]
base, once = run(deliveries, False), run(deliveries, True)
check('model: unguarded does 2x the work', len(base) == 240)
check('model: guarded does exactly one pass per distinct event', len(once) == 120)
check('model: every distinct event still gets processed with the same input', once == events)
check('model: single delivery unchanged', run(events, True) == run(events, False))
check('mutant (no timestamp guard) is caught', len(run(deliveries, False)) != len(events))
print('mouse variation once: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
