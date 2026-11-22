import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
r=Path(__file__).resolve().parents[2]
s=(_pp_split().path(r,'PPController.swift')).read_text();m=(r/'Sources/gor/UI/MenuActions.swift').read_text();lua=(r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text();fit=(r/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()
menu=m[m.index('private func applyCrop('):m.index('// MARK: - Audio Menu')]
assert 'applyMenuCrop' in menu and 'vf' not in menu
crop=s[s.index('func applyMenuCrop('):s.index('private func refreshStereoMenuGeometry')]
# Current menu records an explicit transition intent; pixel property encoding
# is owned by the actual presentation method, not synchronous menu queryBatch.
import subprocess, sys
_semantic = subprocess.run([sys.executable, str(r/'Tests/ConsumerContracts/run.py'), 'block'])
assert _semantic.returncode == 0, 'actual menu/presentation Swift execution did not pass'
current=(r/'Sources/gor/Player/PPController.swift').read_text()
request=current[current.index('private func requestRealCrop('):current.index('private func cancelCropMotion(')]
assert 'guard rect.minX>=0' in request and '.allSatisfy({$0.isFinite})' in request
assert 'cropBoundLaunchSession != Self.cropPacketSession {return}' in request
assert 'host.cropMotionGeneration==generation,host.currentFilePath==source,host.cropPacketToken==openingToken' in request
assert 'host.applyCropPresentation(sample,publish:capture)' in request
assert 'host.cancelCropMotion();return' in request
assert 'cropPacketFinal' in current and 'cropPacketAcceptance' in current

assert 'stereo-window-owned' in s and 'stereo-window-owned' in fit
assert 'openingFitPending' in s[s.index('private func refreshStereoMenuGeometry'):s.index('func noteAspectMenuSelection')]
assert 'clearOwnedCropFromMenu()' in s[s.index('func resetCrop()'):s.index('func reDetectCrop()')]
assert 'clearStereoMenuCrop()' in s[s.index('func clearOwnedCropFromMenu()'):s.index('private func requestRealCrop')]
assert 'stereoMenuCropAspect = nil' in s[s.index('private func resetCropForOpening'):s.index('func clearOwnedCropFromMenu')]
assert 'refreshStereoMenuGeometry(force:true)' in s[s.index('func noteVrGapPublication'):s.index('func refreshEffectiveGap')]
assert 'uv = (uv - vec2(0.5)) * vec2(vr_crop_x,vr_crop_y)' in lua and 'if(blink_top_bottom>0.5)' in lua
assert 'eye_aspect *= vr_crop_y / vr_crop_x' in lua
print('PASS production routing: no whole-vf replacement; current menu intent + actual source-pixel presentation, separate request generation/path/token fences; stereo window authority; opening barrier; reset/file/gap; per-eye crop before packing; projection compensation. Static source wiring, not native behavior.')

assert 'if vrModeEnabled { refreshStereoMenuGeometry(force:true) }' in s[s.index('private func runCropActions'):s.index('private func refitWindowForCrop')]
print('PASS late owned-crop refit replies cannot resize VR to packed-source ratio')

for name,end in [('func setVRModeEnabled(', 'func setVRModeManually('),('func setVRModeManually(', 'func selectVRProjection(')]:
 block=s[s.index(name):s.index(end)]
 assert 'if !enabled {offReset();redetectCropAfter3DOff();return}' in block
reset=current[current.index('private func offReset()'):current.index('private func redetectCropAfter3DOff()')]
assert 'clearStereoMenuCrop(refit:false)' in reset and 'video-aspect-override' in reset and 'restoreStereoMenuFrame()' in reset
# Current projection selection dispatches through the store; full-eye geometry
# explicitly excludes detector crop rather than clearing old feature-local fields.
vr=(r/'Sources/gor/Stereo/VR180Controller.swift').read_text()
select=vr[vr.index('func selectProjection('):vr.index('func noteManualEnabled(')]
manual=vr[vr.index('func applyManualSource('):vr.index('func applySourceOutput(')]
geometry=vr[vr.index('func knownEyeAspect('):vr.index('func publishProjection(')]
assert 'applyManualSource(map[kind] ?? "flat",enable:false)' in select
assert 'ThreeDStore.shared.dispatch(.setSource(SourceFormatChoice.source(value)))' in manual
assert 'cropWidth:nil,cropHeight:nil' in geometry and 'latestSourceCrop' not in geometry and 'sourceMeasuredEyeAspect' not in geometry
print('PASS mode-off delegates shared reset/refit; manual packing dispatches actual store and projection eye aspect excludes stale detector crop')
