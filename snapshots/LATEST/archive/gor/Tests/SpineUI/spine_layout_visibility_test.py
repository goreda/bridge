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
import re

root = Path(__file__).resolve().parents[2]
pp = (_pp_split().path(root,'PPController.swift')).read_text()
spine = (root / 'Sources/gor/UI/SpineUI.swift').read_text()
failures = []


def check(ok: bool, message: str) -> None:
    if not ok:
        failures.append(message)


def extract_func(src: str, signature: str) -> str:
    start = src.find(signature)
    if start < 0:
        return ''
    brace = src.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    raise AssertionError(f'unclosed function: {signature}')


apply_frame = extract_func(pp, 'private func applyVideoFrame(bounds: CGRect)')
wake_ui = extract_func(pp, 'func wakeUI()')
set_mirror_opacity = extract_func(pp, 'private func setVRMirrorChromeOpacity(_ opacity: Float, duration: CFTimeInterval)')

# The owner-facing contract: the rail always starts from the cropped film
# frame, and the canonical layout scale shrinks its metrics uniformly. There is
# no separate window-height or SBS layout branch.
check(bool(apply_frame), 'applyVideoFrame not found')
check('let spineChromeBounds = chromeBounds' in apply_frame,
      'spine rail does not start from the cropped film frame')
check('spineUsesWindowHeight' not in apply_frame,
      'window/SBS-specific spine rail branch returned')
check('spineUI.frame = CGRect(x:spineChromeBounds.minX,y:spineChromeBounds.minY,' in apply_frame,
      'spine frame does not use shared spine chrome bounds')
check('height:spineChromeBounds.height' in apply_frame,
      'spine frame height does not use shared spine chrome bounds')
check('PhotonFont.setChromeLayoutScale(PhotonFont.chromeLayoutScale(for: spineChromeBounds))' in apply_frame,
      'film layout does not publish the canonical chrome scale')

# The SBS clip must cover the same taller rail. Otherwise the right-eye mirror
# and the replicator mask cut the controls back to the picture height.
check('vrChromeMask.frame = spineChromeBounds' in apply_frame,
      'VR chrome mask does not cover the full spine rail')
check('vrChromeMask.frame = chromeBounds' not in apply_frame,
      'old picture-height VR chrome mask remains')
check('vrControlMirrorClip = spineChromeBounds.offsetBy(dx: vrEyeShift, dy: 0)' in apply_frame,
      'VR control mirror clip does not cover the full spine rail')
check('vrControlMirrorClip = chromeBounds.offsetBy(dx: vrEyeShift, dy: 0)' not in apply_frame,
      'old picture-height VR control mirror clip remains')

check('private var PAD:   CGFloat { PhotonFont.chromePad }' in spine,
      'SpineUI padding no longer comes from canonical scaled PhotonFont metrics')
check('private var BTN_H: CGFloat { PhotonFont.chromeLineH }' in spine,
      'SpineUI row height no longer comes from canonical scaled PhotonFont metrics')
check('btnT, btnA, btnVid, btnO' in spine,
      'settings/video control set changed')

# Red geometry case: a short letterboxed window used to grow the rail to the
# drawable while keeping fixed control metrics. The new contract keeps the film
# rect and scales the metrics instead, so normalized gaps stay identical.
def spine_chrome(fullscreen: bool, replicating: bool, win_h: float, chrome_y: float, chrome_h: float):
    return (chrome_y, chrome_h)

pad, btn_h = 16.0, 32.0
required_open_settings_height = 2 * pad + 12 * btn_h - 10
window_h, chrome_y, letterboxed_h = 540.0, 120.0, 300.0
fullscreen_h = 900.0
check(letterboxed_h < required_open_settings_height < window_h,
      'geometry red case no longer distinguishes short picture from window')
check(spine_chrome(False, False, window_h, chrome_y, letterboxed_h) == (chrome_y, letterboxed_h),
      'windowed model does not use the film frame')
check(spine_chrome(False, True, window_h, chrome_y, letterboxed_h) == (chrome_y, letterboxed_h),
      'SBS model does not use the film frame')
check(spine_chrome(True, False, fullscreen_h, 90.0, 720.0) == (90.0, 720.0),
      '2D fullscreen model changed')
check(spine_chrome(True, True, fullscreen_h, 90.0, 720.0) == (90.0, 720.0),
      'fullscreen SBS model does not use the film frame')

# vrControlMirrorRoot is a CALayer. Do not rely on NSView animator conveniences;
# animate its opacity explicitly and leave the model value at the final state.
check(bool(set_mirror_opacity), 'explicit CALayer opacity animation helper missing')
check('vrControlMirrorRoot.animator()' not in pp,
      'CALayer mirror root incorrectly uses animator()')
check('CABasicAnimation(keyPath: "opacity")' in set_mirror_opacity,
      'mirror opacity does not use CABasicAnimation')
check('let fromOpacity = vrControlMirrorRoot.presentation()?.opacity ?? vrControlMirrorRoot.opacity' in set_mirror_opacity,
      'mirror opacity animation does not capture the presentation value')
check('animation.fromValue = fromOpacity' in set_mirror_opacity,
      'mirror opacity animation does not start from the captured presentation value')
check('vrControlMirrorRoot.add(animation, forKey: key)' in set_mirror_opacity,
      'mirror opacity animation is not added to the CALayer')
check(set_mirror_opacity.count('vrControlMirrorRoot.opacity = opacity') == 2,
      'mirror opacity model value is not set on animated and immediate paths')
check('vrControlMirrorRoot.removeAnimation(forKey: key)' in set_mirror_opacity,
      'prior mirror opacity animation is not cancelled')

# Show and hide use the same durations as the AppKit chrome animation.
check(bool(wake_ui), 'wakeUI not found')
check('setVRMirrorChromeOpacity(1.0, duration: 0.2)' in wake_ui,
      'mirror show opacity does not follow the 0.2s chrome show')
check('setVRMirrorChromeOpacity(0.0, duration: 0.5)' in wake_ui,
      'mirror hide opacity does not follow the 0.5s chrome hide')
show_block = re.search(r'NSAnimationContext\.runAnimationGroup \{\n\s+\$0\.duration = 0\.2(?P<body>.*?)\n\s+\}', wake_ui, re.S)
hide_block = re.search(r'NSAnimationContext\.runAnimationGroup \{\n\s+\$0\.duration = 0\.5(?P<body>.*?)\n\s+\}', wake_ui, re.S)
check(bool(show_block), '0.2s chrome show block missing')
check(bool(hide_block), '0.5s chrome hide block missing')
if show_block:
    for marker in ('spineUI.animator().alphaValue   = 1.0', 'sidebarUI.animator().alphaValue = 1.0'):
        check(marker in show_block.group('body'), f'chrome show lost {marker}')
if hide_block:
    for marker in ('spineUI.animator().alphaValue   = 0.0', 'sidebarUI.animator().alphaValue = 0.0'):
        check(marker in hide_block.group('body'), f'chrome hide lost {marker}')


# Owner 23:55 (phonemsg-01M7669NPB20JMGDTH6CK0WN77): the Settings > Video > 3D
# surface is ThreeDCornerTuneView, not the SpineUI button stack alone. It must
# use the same PPController chrome rect and fade out with the idle UI.
_b3d = (_threed_split().path(root)).read_text()
def _sec3d(n):
    return _b3d[_b3d.index('// BEGIN relocated ' + n + ' '):_b3d.index('// END relocated ' + n + '\n')]
check('// BEGIN relocated ThreeDCornerTune.swift ' in _b3d, 'ThreeDCornerTune.swift section missing')
check('// BEGIN relocated ThreeDCornerTuneLayout.swift ' in _b3d, 'ThreeDCornerTuneLayout.swift section missing')
view = _sec3d('ThreeDCornerTune.swift')
layout = _sec3d('ThreeDCornerTuneLayout.swift')

check('private(set) var controlChromeBounds:CGRect = .zero' in pp,
      'PPController does not publish the shared chrome layout bounds')
check('controlChromeBounds = spineChromeBounds' in apply_frame,
      'shared chrome layout bounds are not populated from the spine rail geometry')
check('private func chromeFrame(in rootView: NSView)' in view,
      'corner tune chrome-frame helper missing')
check('pc.controlChromeBounds != .zero { return pc.controlChromeBounds }' in view,
      'corner tune does not prefer the PPController chrome layout bounds')
check('frame = chromeFrame(in: rootView)' in view,
      'corner tune attach does not use the chrome layout bounds')
check('let chromeBounds = chromeFrame(in: rootView)' in view and 'frame = chromeBounds; placedFrame = frame' in view,
      'corner tune refresh does not re-place on chrome layout changes')
check('func setChromeAlpha(_ alpha: CGFloat, duration: TimeInterval)' in view,
      'corner tune chrome fade entry point missing')
check('self.animator().alphaValue = alpha' in view,
      'corner tune fade is not animated')
check(pp.count('ThreeDCornerTuneView.shared.setChromeAlpha') == 3,
      'corner tune fade is not wired into chrome show/hide paths')

overlay_alpha = extract_func(layout, 'static func overlayAlpha(calibrationOnly: Bool, chromeAlpha: Double) -> Double')
check(bool(overlay_alpha), 'overlayAlpha missing')
check('calibrationOnly ? chromeAlpha : 1' not in overlay_alpha,
      'full 3D surface still ignores the chrome fade')
overlay_alpha_body = overlay_alpha[overlay_alpha.index('{') + 1:overlay_alpha.rindex('}')] if overlay_alpha else ''
check(overlay_alpha_body.strip() == 'chromeAlpha',
      'overlayAlpha no longer returns the chrome alpha')

# The rail, panel frame, mask and mirror clip stay on the same film rect in
# windowed, SBS and fullscreen 2D. Only the canonical layout scale changes.
check(spine_chrome(False, False, 540.0, 120.0, 300.0) == (120.0, 300.0),
      'windowed shared chrome bounds moved')
check(spine_chrome(False, True, 540.0, 120.0, 300.0) == (120.0, 300.0),
      'SBS shared chrome bounds moved')

if failures:
    raise AssertionError('\n'.join(f'- {failure}' for failure in failures))

print('PASS SpineUI/ThreeD controls share the film chrome rect, canonical scaled Photon metrics, and fade with the UI; 2D/SBS layout relationships are unchanged.')
