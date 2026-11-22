#!/usr/bin/env python3
"""The crop-film rail is common; only the committed film receipt moves UI.
194l supersedes194h/k's subtitle-ink pivot and UI-only fit expectations.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
root=Path(__file__).resolve().parents[2]
pp=(_pp_split().path(root,'PPController.swift')).read_text()
a=pp.index('private func applyTrackedUITilt()');b=pp.index('private var vrControlPixelEvidenceSaved',a);tilt=pp[a:b]
assert 'private func rotatedFitScale' not in pp
assert 'subtitleView.trackedOverlayPlacement' not in tilt
features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
assert 'sourceIsFlatPreview && appliedPlan?.output == .vr180' in features
assert 'let frame=committedFilmFrame' in tilt
assert 'frame?["scale"]' in tilt and 'frame?["angle"]' in tilt
assert 'vrControlInput.tiltScale=fitScale' in tilt
assert 'fitScale:fitScale,clipToBounds:frame == nil' in tilt
assert 'guard self?.vr180Controller?.usesLegacyPreviewChrome == true else{return}' in pp
assert 'let spineChromeBounds = chromeBounds' in pp
assert 'controlChromeBounds = spineChromeBounds' in pp
assert 'chromeBounds=CGRect(x:CGFloat(frame["baseX"]!)' in pp
assert 'user-data/vr180-look/film-frame' in pp
assert 'let geometryChanged=' in pp
assert 'if frame != nil {layer?.mask=nil}' in tilt
print('PASS source wiring: cropped-film snapshot owns control rail, fit, angle and replica; no subtitle-ink pivot or UI-only fit')
