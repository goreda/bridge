#!/usr/bin/env python3
"""Owner log 03:14-03:15 ([VB][next] font_changed_over_same_10s): IPTV.swift:247 127-237/10s and MusicPanel.swift:1567
271/10s re-typeset CATextLayers that nobody can see. Model of fanout -> font set with/without the visibility guard,
plus source pins. Swift uncompiled; the rate model is not a Mac measurement. Visible views behave exactly as before."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]; src = root/'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def run(visible, guard, fanouts=240):
    font_sets = 0; last = None
    for i in range(fanouts):
        if guard and not visible: continue
        f = round((i % 7) * 0.1, 1)      # a changing driven font while the mouse moves
        if f != last: font_sets += 1; last = f
    return font_sets
check('hidden view: unguarded re-typesets, guarded does not', run(False, False) > 200 and run(False, True) == 0)
check('visible view: identical with and without the guard', run(True, False) == run(True, True))
iptv = (src/'IPTV.swift').read_text(); mus = (src/'MusicPanel.swift').read_text()
check('IPTV status font listener guarded by isEffectivelyVisible', 'self.window != nil, self.isEffectivelyVisible else { return }\n            let newFont = PhotonFont.ctDriven(view: self, profile: .panel)' in iptv)
check('MusicRowView.updateFontVariation guarded', 'private func updateFontVariation() {\n        guard isEffectivelyVisible else { return }; if selected {' in mus)
check('guard helper exists (alpha/isHidden chain)', 'var isEffectivelyVisible: Bool' in (src/'VariationBroadcaster.swift').read_text())
sys.exit(1 if fails else 0)
