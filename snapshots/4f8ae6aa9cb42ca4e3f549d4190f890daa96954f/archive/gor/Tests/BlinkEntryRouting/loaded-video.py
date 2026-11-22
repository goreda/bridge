#!/usr/bin/env python3
"""Run the production loaded-video/pause gate without AppKit or a camera."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController.swift')).read_text()
def method(signature):
    start=s.index(signature);opening=s.index('{',start);depth=1;end=opening+1
    while depth:
        if s[end]=='{':depth+=1
        elif s[end]=='}':depth-=1
        end+=1
    return s[start:end].replace('private func','func')
program='''import Foundation
final class State {var playbackActive=false;var loadedVideoActive=false}
final class Ambient {var playbackActive=false}
final class Gate {
 var vr180Controller:State?=State();var contentAdaptiveDimming:Ambient?=Ambient()
 var cameraLoadedVideoActive=false;var cameraPlaybackShutDown=false
 var cameraPauseIntentPending=false;var ambientPlaybackFileEnded=false;var isTorrentStopped=false
 var cameraFileGeneration:UInt64=0
'''
for signature in ['private func setCameraPlaybackActive(', 'private func updateAmbientPlaybackGate(', 'func shutDownPlaybackCamera()', 'func suspendPlaybackCamera()']:
    program+=method(signature)+'\n'
program+='''}
let g=Gate();let v=g.vr180Controller!
func poll(_ paused:Bool,_ path:String="film.mkv",_ id:Int=1,_ idle:Bool=false,_ album:Bool=false,_ image:Bool=false){
 g.updateAmbientPlaybackGate(["path":path,"pause":paused,"current-tracks/video/id":id,
 "idle-active":idle,"current-tracks/video/albumart":album,"current-tracks/video/image":image])
}
poll(true);precondition(v.loadedVideoActive && !v.playbackActive)
print("PASS actual poll gate: loaded PAUSED video retains blink authority without head-motion playback authority")
poll(false);precondition(v.loadedVideoActive && v.playbackActive)
g.cameraPauseIntentPending=true;poll(false);precondition(v.loadedVideoActive && !v.playbackActive)
poll(true);precondition(v.loadedVideoActive && !v.playbackActive && !g.cameraPauseIntentPending)
print("PASS playing, pending manual pause and confirmed pause preserve separate authorities")
for kind in 0..<6 {
 g.ambientPlaybackFileEnded=false;g.isTorrentStopped=false
 switch kind {
 case 0:poll(true,"",1)
 case 1:poll(true,"audio.m4a",0)
 case 2:poll(true,"cover.jpg",1,false,true,false)
 case 3:poll(true,"still.png",1,false,false,true)
 case 4:poll(true,"film.mkv",1,true)
 default:g.ambientPlaybackFileEnded=true;poll(true)
 }
 precondition(!v.loadedVideoActive && !v.playbackActive)
}
g.ambientPlaybackFileEnded=false;g.isTorrentStopped=true;poll(true)
precondition(!v.loadedVideoActive && !v.playbackActive)
print("PASS empty/audio/album-art/still/idle/ended/stopped video release both authorities")
g.isTorrentStopped=false;poll(true);g.suspendPlaybackCamera()
precondition(!v.loadedVideoActive && !v.playbackActive)
g.ambientPlaybackFileEnded=false;poll(true);g.shutDownPlaybackCamera();poll(false)
precondition(!v.loadedVideoActive && !v.playbackActive)
print("PASS sleep/shutdown release authority; late poll cannot restart shutdown controller")
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);(p/'main.swift').write_text(program)
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'gate')],check=True)
    subprocess.run([str(p/'gate')],check=True)
# Source contract for boundaries whose whole event loop depends on AppKit/IPC.
init=s[s.index('if vr180Controller == nil'):s.index('if iptvModeController == nil')]
assert 'setCameraPlaybackActive(cameraLoadedVideoActive,' in init
for event,end in [('case "start-file":','case "file-loaded":'),('case "end-file":','case "shutdown":'),('case "shutdown":','case "video-reconfig":')]:
    assert 'setCameraPlaybackActive(false)' in s[s.index(event):s.index(end,s.index(event))]
stop=s[s.index('if ["stop","loadfile","quit","quit-watch-later"]'):]
assert 'setCameraPlaybackActive(false)' in stop.split('if name == "script-message-to"')[0]
pause=s[s.index('cameraPauseIntentPending = true',s.index('func ipcCommand(')):]
assert 'vr180Controller?.playbackActive = false' in pause.split('if name == "seek"')[0]
assert 'loadedVideoActive = false' not in pause.split('if name == "seek"')[0]
print('PASS static attach/event/stop/reset routing and pause leaves loaded-video authority intact')
print('UNVERIFIED native camera and recognizer; Features owner tests the downstream loadedVideoActive consumer')
