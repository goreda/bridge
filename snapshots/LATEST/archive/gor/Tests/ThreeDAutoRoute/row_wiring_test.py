#!/usr/bin/env python3
"""191b B4/B5: every 3d menu row reaches the store. Chain per row: ThreeDKeymap row -> ThreeDMenu.dispatch -> ThreeDStore action
(E-G's store/applier own RenderPrefs.write, mpv projection, effects and OSD; the menu never writes defaults, B1).
The pre-191b pins (menu -> ThreeDSettings -> RenderPrefs.write, numeric picker submenus, menuVRToggle/toggleFromKeyboard)
were retired by the 191b owner order (ledger: Tests/MenuStructure/required-items.json). Mac behaviour unmeasured here."""
import pathlib, sys
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
S = pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor'
t = lambda n: (S / n).read_text()
menu, km, features = t('ThreeDMenu.swift'), t('ThreeDKeymap.swift'), _pp_split().path(S.parents[1], 'PPController_Features.swift').read_text()
ad, wi = t('AppDelegate.swift'), t('ThreeDWiring.swift')
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)

check('B1/E-G: menu handlers only store.dispatch - no RenderPrefs.write, no ThreeDSettings load/save, no UserDefaults write in the menu',
      'RenderPrefs.write(' not in menu and 'ThreeDSettings.load(' not in menu and 'ThreeDSettings.save(' not in menu
      and 'UserDefaults' not in menu and '.setVRModeEnabled(' not in menu and '.select3DOutput(' not in menu and '.publishProjection(' not in menu)
import re as _re
_nocomment = lambda s: '\n'.join(_re.sub(r'//.*', '', ln) for ln in s.splitlines())
_disp = menu[:menu.index('static func statusTitle')] + menu[menu.index('func validateMenuItem'):]  # statusTitle() is a display read helper
check('B1: store state is read only in dispatch (the sanctioned write path: read-add-dispatch), validateMenuItem and the statusTitle display helper',
      'ThreeDStore.shared.snapshot' not in _nocomment(menu[:menu.index('static func dispatch')])
      and 'ThreeDStore.shared.snapshot' not in _nocomment(_disp[_disp.index('// MARK: - install'):_disp.index('func validateMenuItem')]))
for row, disp in [('strength', '.setEffect(.strength, stepped(.strength'), ('screen depth', '.setEffect(.screenDepth, scaled(.screenDepth'),
                  ('screen size', '.setEffect(.screenSize, stepped(.screenSize'), ('surround', '.setEffect(.surround, .text('),
                  ('quality', '.setEffect(.quality, .text('), ('ipd', '.setEffect(.ipd, stepped(.ipd')]:
    check(f'{row}: row -> dispatch -> store effect', disp in menu)
check('B4: depth/screen/size are live read-add-dispatch steps, not numeric submenus',
      'stepped(' in menu and 'scaled(' in menu and 'sub("strength")' not in menu and 'pickStrength' not in menu)
check('B4: quality Best/Fast are HIDDEN until a learned runner registers (not labelled "not implemented")',
      'i.isHidden = ThreeDRunnerRegistry.runner == nil' in menu and 'not implemented' not in menu)
check('B4: quality Auto is always present', '_ = row(.qualityAuto)' in menu)
check('B4: status line always visible and disabled', 'status.tag = -1' in menu and 'status.isEnabled = false' in menu)
check('one 3d menu: no vr extras in AppDelegate, one install call, no old selectors',
      'vrMenu' not in ad and ad.count('ThreeDMenu.shared.install(in: videoMenu)') == 1
      and all(s not in ad for s in ['menuVRSwapEyes', 'menuHeadTracking', 'menuVRBlinkLog', 'menuHeadRecenter', 'menuIPDPlus', 'menuIPDMinus']))
check('191b: no old menu entry points remain anywhere (menuVRToggle/toggleFromKeyboard/autoMode/pickQuality/selectOutput)',
      all(s not in (menu + t('MenuActions.swift') + features) for s in ['menuVRToggle', 'toggleFromKeyboard', 'autoMode', 'pickQuality', 'selectOutput(']))
check('B5: one keymap drives menu key equivalents AND the keyboard path',
      'ThreeDKeymap.rows' in menu and 'ThreeDKeymap.match(' in features)
check('Shift+V = View VR180 through the table; toggles back to Off when already VR180 (the store owns the decision)',
      'Row(act: .viewVR180,     chord: Chord("v", shift: true)' in km
      and 'store.dispatch(.setOutput(store.snapshot.current.output == .vr180 ? .off : .vr180))' in menu)
check('Shift+D (E-G integration): the legacy keyCode==2 special case is gone; the keyboard path matches the keymap table and dispatches, repeats ignored',
      'Row(act: .toggle3D,      chord: Chord("d", shift: true)' in km
      and 'e.keyCode==2' not in features
      and 'ThreeDKeymap.match(charactersIgnoringModifiers:' in features
      and 'if !event.isARepeat { MainActor.assumeIsolated {ThreeDMenu.dispatch(act)} }' in features)
check('no shipped mpv Shift+D binding before the app-owned route',
      not any(line.split()[0] in ('D', 'Shift+d', 'shift+d', 'Shift+D')
              for line in (pathlib.Path(__file__).resolve().parents[2] / 'Resources/vendor/mpv/input.conf').read_text().splitlines()
              if line.strip() and not line.startswith('#')))
check('subtitle depth is the only non-store dispatch (subtitle render offset, not 3D state) and is wired to the controller',
      'shared.subtitleDepth(' in menu and 'ThreeDMenu.shared.subtitleDepth = ' in wi)
check('wiring keeps only read-only menu hooks (detectedSource, subtitleDepth); the onSourceResolved subscription is gone',
      'controller?.onSourceResolved' not in wi and 'ThreeDMenu.shared.on' not in wi and 'refreshPreview()' not in wi)
check('pre-191b axes-acceptance harness removed with the old menu (191b-T self-test replaces it)',
      not (S / 'ThreeDAxesAcceptance.swift').exists())

# 191a pins that survive 191b (those files are untouched by B4/B5):
co, ar = t('ThreeDRenderCoordinator.swift'), t('ThreeDAutoRoute.swift')
recognition = (S / 'Stereo/StereoDetection.swift').read_text()
check('191a repeated/delayed detection never reads historical projection cache',
      'dictionary(forKey:Self.fileChoicesKey)' not in
      features[features.index('func autoDetectFromVideoParams'):features.index('/// GOR_VR_SIM_POSE')])
check('191a stale global mode/cache cannot replace Off or native source',
      'SourceFormatChoice.output(sourceFilm.path) != "off"' in co and 'StereoSourceGate.shared.route(for:sourceFilm)?.route == .depth else' in co)
check('no geometry-only VR180 promotion',
      'reason:"geometryEquiSBS180"' not in recognition and 'if result.circularProfile {result.projection="vr180"}' not in recognition)
check('full and half SBS/TB have distinct source aspect math',
      all(x in features for x in ['source=="sbs" {return width*latestPixelAspect/height/2}', 'source=="half_sbs" {return width*latestPixelAspect/height}',
                                  'source=="ou" {return width*latestPixelAspect/height*2}', 'source=="half_ou" {return width*latestPixelAspect/height}']))
print('row wiring: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
