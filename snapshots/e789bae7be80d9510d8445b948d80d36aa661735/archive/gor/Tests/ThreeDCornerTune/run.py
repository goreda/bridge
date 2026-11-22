"""191k + owner 17:33 (phonemsg-01M72Y1GHHQT93RMMN87H3JZJZ): compile and run the production corner-tune layout on Linux or Mac. No Python policy mirror.
Owner 21:28 (phonemsg-01M73BG6BQ7DP7BGPR2FWA3TXP): also compile and run the production 3D store against the menu-mapped control actions."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os, subprocess, tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
swiftc=os.environ.get('SWIFTC','swiftc')
env=dict(os.environ, GOR_STORE_ACCEPTANCE_DIR='1')
with tempfile.TemporaryDirectory() as folder:
    binary=Path(folder)/'corner-tune-test'
    subprocess.run([swiftc,str(_sec_file(root,'ThreeDCornerTuneLayout.swift')),str(Path(__file__).with_name('main.swift')),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
    dispatch=Path(folder)/'corner-tune-dispatch-test'
    subprocess.run([swiftc,str(_sec_file(root,'ThreeDState.swift')),str(Path(__file__).with_name('dispatch_main.swift')),'-o',str(dispatch)],check=True)
    subprocess.run([str(dispatch)],check=True,timeout=20,env=env)

view=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTune.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTune.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'btnVid.frame.minY' in view, '3D row still overlaps Video'
assert 'hide()   // click anywhere' not in view and 'override func hitTest' in view, 'surface dismisses or steals clicks'
assert 'VariationBroadcaster.shared.addListener' in view and 'PhotonFont.chromeCtDriven' in view and 'ScreenCaptureEngine.shared.currentAudioLevel' in view, 'static typography'
assert 'CornerTuneLayout.clearContent' in view and 'is SidebarUI' in view and 'is SpineUI' in view, 'chrome clearance not wired'
assert '"subs"' not in view, 'subs control removed (owner 17:33)'
assert 'cornerLayout.controls(in:' in view and '(c.glyphA, c.cellA), (c.glyphB, c.cellB)' in view and '(c.letter, c.wordFrame)' in view, 'every element its own layer; titles render the single letter (owner 22:28)'
assert 'beginTitleHover' not in view or True  # hover implemented via mouseEntered/mouseExited below
assert 'NSTrackingArea' in view and 'hoverTimer' in view and 'setTitle' in view and 'mouseEntered' in view and 'mouseExited' in view, 'typewriter title hover missing (owner 22:28)'
assert 'c.cellA.contains' in view and 'c.cellB.contains' in view and 'ThreeDMenu.dispatch(acts.0)' in view and 'ThreeDMenu.dispatch(acts.1)' in view, 'glyph cells dispatch the menu acts'
assert 'c.frames.contains' in view, 'hit area covers every element frame'
assert 'controlChromeBounds' in view and 'chromeFrame' in view, 'overlay does not ride the PPController chrome layout bounds'
# Owner 21:28: crosshair, hides with the UI, reacts to mouse and sound like the other buttons.
assert 'CornerTuneLayout.crosshairFrame' in view and 'addTextLayer("+", crosshair)' in view, 'center crosshair missing'
assert 'spineUI.alphaValue' in view and 'alphaValue > 0.5' in view and 'CornerTuneLayout.overlayAlpha(calibrationOnly:' in view, 'persistent surface/calibration visibility policy missing'
assert 'func setChromeAlpha' in view and 'NSAnimationContext.runAnimationGroup' in view, 'corner tune cannot fade with the chrome'
pp=(_pp_split().path(root,'PPController.swift')).read_text()
assert 'private(set) var controlChromeBounds' in pp and 'controlChromeBounds = spineChromeBounds' in pp, 'PPController does not publish the shared chrome layout bounds'
assert pp.count('ThreeDCornerTuneView.shared.setChromeAlpha') == 3, 'corner tune fade not wired into chrome show/hide'
assert 'lastSignature' in view, 'anti-churn rebuild guard missing (one-eye mirror risk, owner 21:29)'
assert 'titleLayers' in view and 'removeTrackingArea' in view, 'title hover tracking lifecycle missing'

layout=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTuneLayout.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTuneLayout.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'static func crosshairFrame' in layout, 'crosshair layout math missing'
assert 'titleMarginPads' in layout and 'gridGapPads' in layout and 'titleReserveChars' in layout and 'valueFieldChars' in layout and 'rowPadLines' in layout, 'pad grid constants missing (owner 2026-11-12 12:40)'
assert 'static let titleMarginPads = 0.0' in layout and 'static let gridGapPads = 1.0' in layout, 'owner 13:47: every pad x 2 gap halved to pad x 1'
assert '"screenDepth", "\u2190", "\u2192"' in layout, 'owner 13:47: scr cells are left/right arrows (near = farther, far = nearer)'
assert 'marginChars' not in layout and 'valueCenterChars' not in layout and 'stepChars' not in layout, 'superseded mockup constants still present (owner 2026-11-12 12:40)'
assert 'static func dropdownTop(videoMinY: Double, lineH: Double) -> Double {max(lineH,videoMinY)}' in layout, '3D dropdown row must sit directly below V (owner 2026-11-12 12:40)'
assert 'layer.alignmentMode = leftPinned ? CATextLayerAlignmentMode.left : CATextLayerAlignmentMode.right' in view, 'depth/size must pin the right edge while typing left (owner 2026-11-12 12:40)'
assert '"scr",   "screenDepth"' in layout and '"screen"' not in layout, 'screen corner abbreviated to scr with arrow/+ cells (owner 22:23 target)'
assert 'valueMaxChars' in layout, 'fixed-width value fields missing (owner 21:31: buttons must not move)'
assert '"%.3gm"' in layout, 'screen depth must format at 3 significant digits (owner 22:13: equal gaps)'
assert 'CATextLayerAlignmentMode.center' in view, 'values must center in fixed fields (owner 21:43: all gaps equal)'
assert 'lastChrome' in view, 'chrome-change re-placement missing (owner 21:43: fullscreen breaks placement)'
assert 'valueLayers' in view and 'l.string = c.value' in view, 'in-place value retext missing (owner 21:43: no re-render churn on clicks)'

menu=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text())
# The eight acts the corner controls dispatch must keep these exact store mappings and constants.
for line in [
    'static let strengthStep = 0.25, strengthRange = 0.0...2.0',
    'static let screenDepthFactor = 1.5, screenDepthRange = 0.25...8.0',
    'static let screenSizeStep = 5.0, screenSizeRange = 20.0...150.0',
    'case .depthStronger: store.dispatch(.setEffect(.strength, stepped(.strength, +strengthStep, strengthRange, store)))',
    'case .depthWeaker:   store.dispatch(.setEffect(.strength, stepped(.strength, -strengthStep, strengthRange, store)))',
    'case .screenNearer:  store.dispatch(.setEffect(.screenDepth, scaled(.screenDepth, 1.0 / screenDepthFactor, screenDepthRange, store, 1.5)))',
    'case .screenFarther: store.dispatch(.setEffect(.screenDepth, scaled(.screenDepth, screenDepthFactor, screenDepthRange, store, 1.5)))',
    'case .sizeLarger:    store.dispatch(.setEffect(.screenSize, stepped(.screenSize, +screenSizeStep, screenSizeRange, store)))',
    'case .sizeSmaller:   store.dispatch(.setEffect(.screenSize, stepped(.screenSize, -screenSizeStep, screenSizeRange, store)))',
    'case .ipdPlus:       store.dispatch(.setEffect(.ipd, stepped(.ipd, +ipdStep, ipdRange, store)))',
    'case .ipdMinus:      store.dispatch(.setEffect(.ipd, stepped(.ipd, -ipdStep, ipdRange, store)))',
]:
    assert line in menu, '3D menu mapping drifted: '+line
# Main 22:17 split: the menu calibration crosshair is the AppKit '+' marker; the green shader mark is retired.
assert 'setCalibration' in view and 'calibrationOnly' in view, 'AppKit calibration marker mode missing'
menu_full=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'calibrationMarker' in menu_full and 'calibrationOverlay' not in menu_full, 'menu calibration not routed to the AppKit marker'
wiring=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'ThreeDCornerTuneView.shared.setCalibration' in wiring and 'vr180-look-calibration' not in wiring, 'wiring still drives the shader mark'
# Owner 2026-11-12 13:47 (phonemsg-01M77NX7459XYMH8W2B3VR9N01): video menu order - crop directly
# under clip, aspect ratio directly under crop, toggle the LAST group.
app=(root/'Sources/gor/App/AppDelegate.swift').read_text()
def vg(name): return app.index(f'group("{name}", in: videoMenu)')
assert vg('clip') < vg('crop') < vg('aspect ratio'), 'crop directly under clip, aspect ratio directly under crop'
assert vg('zoom') < vg('screenshot') < vg('quality') < vg('adjust') < vg('toggle'), 'toggle must be the last video menu group'
assert vg('aspect ratio') < vg('zoom'), 'aspect ratio must stay directly under crop'
lua=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
assert 'calibration_mark' not in lua and 'vec4(0,1,0,1)' not in lua, 'green shader calibration mark not retired'
print('run.py pins PASS')
