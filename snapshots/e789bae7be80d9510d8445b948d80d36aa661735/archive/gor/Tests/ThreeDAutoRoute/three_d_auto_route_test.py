#!/usr/bin/env python3
"""191b: ThreeDAutoRoute itself (the pseudo-3D preview path) is unchanged; the pre-191b menu pins (quickToggle, autoMode,
menuVR2D3D/menuVRMono, the quickOn/onSingleSwitchResolved wiring) were retired by the 191b owner order - the store drives
routing now, and 191a B/C continue in their own lanes. What stays pinned here: the pure route logic (compiled when swiftc
exists) and the pre-191b behaviours of files B4/B5 did not touch."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if swiftc and os.path.exists(swiftc):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'ar'
    r = subprocess.run([swiftc, '-O', str(S / 'ThreeDAutoRoute.swift'), str(S / 'ThreeDState.swift'), str(root / 'Tests/ThreeDAutoRoute/main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('ThreeDAutoRoute compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-600:]); sys.exit(1)
    o = subprocess.run([str(exe)], capture_output=True, text=True).stdout.split('\n')
    check('MEASURED (Swift pure fn): every 3D menu row maps to a different preview parameter (mode, strength, screen depth, screen size, surround, source, quality state)', 'preview params: 0 failure(s)' in o and not any(l.startswith('FAIL') for l in o))
    check('REGRESSION: 2d3d on a mono film ends with the pseudo-3D (vr180-look flat-2d3d) ENABLED, 3D mode full_sbs, OSD "pseudo-3D preview, real render preparing"', o[0] == 'after 2d3d on mono film vr=true mode=full_sbs preview=true osd=pseudo-3D preview, real render preparing')
    check('rendered shot loaded: real store presentation source changes, explicit SBS output stays', o[1] == 'rendered shot loaded: store presentation=vr180SBS output=full_sbs')
    check('seek to an unrendered shot: store original clears generated source without rearming legacy preview', o[2] == 'seek to unrendered shot: store presentation=flat2D output=full_sbs')
    check('Off then original remains Off in the production store', o[3] == 'off then original: store presentation=flat2D output=off')
    check('sbs on a non-stereo film: old behaviour (vr on), no 3D mode change, one OSD hint, no preview', o[4].startswith('sbs on mono film vr=true mode=off preview=false osd=this film is not stereo'))
    check('vr180 on a stereo film: untouched, no OSD', o[5] == 'vr180 on stereo film vr=true mode=off preview=false osd=-')
    check('owner 15:20 REGRESSION: any mode picked on a mono film with no models/ranges ends with the pseudo-3D ENABLED + label; on a stereo film untouched', o[6] == 'any mode picked on mono film, no models vr=true mode=sbs-picked preview=true osd=pseudo-3D preview, real render preparing' and o[7] == 'mode picked on stereo film vr=false mode=sbs-picked preview=false osd=-')
    check('REGRESSION owner 15:26: 3d switch on then off returns the vr state, 3D mode and preview flag to what they were; vr item on then vr mono does the same (either item toggles the other)', o[8] == '3d switch on then off: RESTORED' and o[9] == 'vr item on then vr mono: RESTORED')
else: print('SKIPPED numeric (no swiftc)')
ar = (S / 'ThreeDAutoRoute.swift').read_text()
co = (S / 'ThreeDRenderCoordinator.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text(); pp = (_pp_split().dpath(S,'PPController.swift')).read_text()
check('coordinator (E-G applier lane): a rendered-shot end returns the store to the original film instead of re-arming the preview', 'MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.original)}' in co)
st = (S / 'ThreeDState.swift').read_text()
check('owner 15:16 blink: OFF by default - under B1 the store owns the default (blink false); the legacy gor.vr.blinkControl read left with the old menu', 'blink: .bool(false)' in st or '.blink: .bool(false)' in st or re.search(r'\.blink[^\n]*false', st) is not None)
check('controller exposes filmLooksStereo + osdLine', 'filmLooksStereo' in pp and 'osdLine' in pp)
check('191b: the menu no longer drives the route (autoMode/quickOn calls left the menu and wiring with the old menu)',
      'ThreeDMenu.shared.autoMode' not in wi and 'ThreeDMenu.shared.quickOn' not in wi)
check('single switch: PPController exposes applySingleSwitch3D forwarding to the VR180Controller (191a C lane; E-G replaced the resolve callback with the store subscription)',
      'vr180Controller?.applySingleSwitch()' in pp and 'func applySingleSwitch3D()' in pp)
check('master sees any active projection even with stale off mode', 'previewOn || projectionOn' in ar)
print('three d auto route: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
