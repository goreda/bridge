#!/usr/bin/env python3
"""s37 wiring pins (text): ThreeDWiring asks StereoSourceGate before any depth prepare; override wins; unknown = nothing starts; the OSD note shows once."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib
root = pathlib.Path(__file__).resolve().parents[2]
w = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(root)).read_text()); g = (lambda _b: _b[_b.index('// BEGIN relocated '+'StereoSourceGate.swift'+' '):_b.index('// END relocated '+'StereoSourceGate.swift'+'\n')])((_threed_split().path(root)).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('wiring: non-depth route or undecided -> mode off for the launcher and the model fetch', 'StereoSourceGate.shared.route(for: f)' in w and 'g.route != .depth { mode = "off"' in w and '} else { mode = "off" }' in w)
check('wiring: launcher and wantsModels use the gated mode, not s.mode', 'l.update(mode: mode, film: film,' in w and 'let wantsModels = mode != "off"' in w)
check('wiring: OSD note once per film', 'StereoSourceGate.shared.once(film: f, note: g.note)' in w and 'func once(film: URL, note: String)' in g)
check('gate: override keyed into the cache, flat override short-circuits to depth', 'ov=Self.override(defaults,source:source),key=film.path+"|"+source' in g and 'guard let v=source,v != "auto" else{return nil}' in g and 'd.string(forKey:overrideKey)' not in g and 'if let ov, case .flat = ov' in g)
check('gate: filename candidate is pixel-confirmed only without an override; route() decides', 'if ov == nil, let v = verdict, v.source == .filename' in g and 'StereoSource.route(verdict: verdict, pixelConfirmed: confirmed, override: ov)' in g)
check('gate: pending check-and-insert under one lock hold', 'let started = pending.insert(key).inserted' in g and 'let hit = cache[key], busy' not in g)
check('gate: work off the main thread', 'DispatchQueue(label: "gor.stereo-source", qos: .utility)' in g and 'q.async' in g)
rw = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderShotWriter.swift'+' '):_b.index('// END relocated '+'RenderShotWriter.swift'+'\n')])((_threed_split().path(root)).read_text())
check('rendered-shot writer sets a quality (no AVAssetWriter default bitrate)', 'AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9]' in rw)
print('stereo gate pins: %d failure(s)' % len(fails)); raise SystemExit(1 if fails else 0)
