"""Production coordinator runtime with only GPU/player/service boundaries mocked."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2];here=Path(__file__).parent
with tempfile.TemporaryDirectory() as d:
 p=Path(d);co=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text())
 # Keep the entire implementation; remove only the platform availability wrapper.
 co=co.replace('#if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)','').removesuffix('#endif\n')
 if os.environ.get('GOR_LIVE_EDIT_NEGATIVE'):
  co=co.replace('let selected=fresh ? (url:out,prefs:prefs):lastGood[hit.shot]', 'if !fresh {backTo2D(pts,filmURL:filmURL)}\n        let selected=fresh ? (url:out,prefs:prefs):lastGood[hit.shot]')
 (p/'Coordinator.swift').write_text(co)
 player=p/'fake-mpv';player.write_text('#!/bin/sh\necho hevc\n');player.chmod(0o700)
 names=['RenderRevision','PrepareSupport','FovTrackBuilder','ShotComfort','RenderPrefsReader','OutputModes','RenderedShotPlan','RenderedShotMPV','ThreeDState','ThreeDPresentation','DepthShotIndex']
 # 195y G2: ShotComfort.swift now carries the real ShotComfortShot span; the runtime keeps its stub, so compile the file without that span
 sc=(lambda _b: _b[_b.index('// BEGIN relocated '+'ShotComfort.swift'+' '):_b.index('// END relocated '+'ShotComfort.swift'+'\n')])((_threed_split().path(root)).read_text())
 sc=sc[:sc.index('// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)')]+sc[sc.index('// END relocated ShotComfortShot.swift'):]
 (p/'ShotComfort.swift').write_text(sc)
 # 195y G2: DepthShotIndex is a relocated span inside DepthContainerWriter.swift; the runtime keeps its DZCFile stub, so compile the span alone
 cw=(lambda _b: _b[_b.index('// BEGIN relocated '+'DepthContainerWriter.swift'+' '):_b.index('// END relocated '+'DepthContainerWriter.swift'+'\n')])((_threed_split().path(root)).read_text())
 si=cw.split('// BEGIN relocated DepthShotIndex.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthShotIndex.swift')[0]
 (p/'DepthShotIndex.swift').write_text('import Foundation\n'+si)
 srcs=[str(p/f'{n}.swift') if n in ('ShotComfort','DepthShotIndex') else str(root/'Sources/gor'/f'{n}.swift') for n in names]
 subprocess.run([os.environ.get('SWIFTC','swiftc'),'-swift-version','5',*srcs,str(p/'Coordinator.swift'),str(here/'runtime_stubs.swift'),str(here/'runtime_main.swift'),'-o',str(p/'runtime')],check=True)
 for mode in (['full_sbs'] if os.environ.get('GOR_LIVE_EDIT_NEGATIVE') else ['full_sbs','half_sbs','over_under','anaglyph']):
  subprocess.run([str(p/'runtime')],check=True,timeout=15,env=dict(os.environ,TEST_MODE=mode,TEST_CACHE=str(p/'cache'/mode),TEST_PLAYER=str(player),GOR_STORE_ACCEPTANCE_DIR='1'))
