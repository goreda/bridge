# Source-bound structural checks and explicit behavioral model. No Swift execution.
from pathlib import Path
import hashlib,json
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
root=Path(__file__).resolve().parents[2].joinpath('..','Sources','gor').resolve()
pp=_pp_split().path(root.parents[1],'PPController.swift').read_text()
f=_pp_split().path(root.parents[1],'PPController_Features.swift').read_text()
checks={
 'selected_video_observed':'117: "current-tracks/video/id"' in pp,
 'selected_video_slow_refresh':'17: "current-tracks/video/id"' in pp,
 'slow_flush_after_video':'rid == 19' in pp,
 'selected_video_positive_gate':'let movingVideo = selectedVideoID > 0' in pp,
 'generation_guard':'generation == self.cameraFileGeneration' in pp,
 'runtime_after_gate':pp.index('self.updateAmbientPlaybackGate(result)')<pp.index('result["user-data/adaptive-brightness-enabled"]'),
 'false_default':'private var cameraLoadedVideoActive = false' in pp,
 'cad_creation_sync':'contentAdaptiveDimming = cad\n            setCameraPlaybackActive(cameraLoadedVideoActive' in pp,
 'pause_intent_consumes_auto_play':'autoPlayTried = true' in pp[pp.index('func ipcCommand'):pp.index('func batchIPC')],
 'quit_terminal_latch':'private var quitFadeActive = false' in pp,
 'camera_pause_loaded':'runtimeEnabled && playbackActive && !AmbientLightProvider.shared.isAvailable' in f,
 'open_window_rechecks_gate':'private func openAmbientWindow(isFirstWindow: Bool = false) {\n        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }' in f,
 'neutral_comment':'Field log' not in f,
}
assert all(checks.values()),checks
# Behavioral model of exact selectedVideoID/path/idle/end/stop inputs and separate VR pause gate.
def gate(video,path,idle,ended,stopped,shutdown,pause,intent,albumart=False,image=False):
 loaded=video>0 and albumart is False and image is False and bool(path) and idle is False and not ended and not stopped and not shutdown
 return loaded,loaded and pause is False and not intent
cases=[((0,'',True,False,False,False,True,False),(False,False)),
 ((0,'audio',False,False,False,False,False,False),(False,False)),
 ((1,'video',False,False,False,False,False,False),(True,True)),
 ((1,'video',False,False,False,False,True,False),(True,False)),
 ((1,'video',False,True,False,False,False,False),(False,False)),
 ((1,'video',False,False,True,False,False,False),(False,False)),
 ((1,'video',False,False,False,True,False,False),(False,False)),
 ((1,'video',None,False,False,False,False,False),(False,False)),
 ((1,'video',False,False,False,False,False,True),(True,False))]
cases += [((1,"cover-audio",False,False,False,False,False,False,True,False),(False,False)),
          ((1,"image",False,False,False,False,False,False,False,True),(False,False)),
          ((1,"unknown",False,False,False,False,False,False,None,None),(False,False))]
for inputs,want in cases:assert gate(*inputs)==want
print(json.dumps({'structural_checks':checks,'model_cases':len(cases),'result':'PASS_SOURCE_AND_MODEL_ONLY','Swift_Mac_native':'NOT_RUN'},indent=2))
