#!/usr/bin/env python3
"""199az item 2 (owner decision 2026-11-21): blink in normal playback must own the camera -
eligibility must not require VR. Compiles the exact live CaptureConsumerRules.swift and runs
the full eligibility matrix; statically pins the single acquisition site and its wiring. No
camera, no AppKit. The pp_split rebuild is NOT used here on purpose: for this part the rebuild
is the historical pre-edit text (see the part's historical_fixture), while this test pins the
CURRENT product rule."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Sources/gor/Camera/CaptureConsumerRules.swift').read_text()
def block(marker):
    assert s.count(marker)==1,marker
    a=s.index(marker);b=s.index('{',a);depth=1;e=b+1
    while depth:
        if s[e]=='{':depth+=1
        elif s[e]=='}':depth-=1
        e+=1
    return s[a:e]
program='import Foundation\n'+block('enum CaptureConsumerRules {')+'''
func check(_ ok:Bool,_ name:String){precondition(ok,name);print("PASS "+name)}
// The owner rule itself: blink on, normal playback (no VR), file loaded, camera allowed.
check(CaptureConsumerRules.blinkShouldRun(blinkOn:true,vrEnabled:false,loadedVideoActive:true,cameraAllowed:true),"blink on in normal playback owns the camera (owner 2026-11-21)")
check(CaptureConsumerRules.blinkShouldRun(blinkOn:true,vrEnabled:true,loadedVideoActive:true,cameraAllowed:true),"blink on in VR keeps working")
// VR must not influence the verdict in ANY state: same inputs, both vrEnabled values, same answer.
for on in [false,true] { for loaded in [false,true] { for allowed in [false,true] {
 check(CaptureConsumerRules.blinkShouldRun(blinkOn:on,vrEnabled:false,loadedVideoActive:loaded,cameraAllowed:allowed) == CaptureConsumerRules.blinkShouldRun(blinkOn:on,vrEnabled:true,loadedVideoActive:loaded,cameraAllowed:allowed),"eligibility is VR-independent for on=\\(on) loaded=\\(loaded) allowed=\\(allowed)")
}}}
// The surviving legs still gate.
for vr in [false,true] {
 check(!CaptureConsumerRules.blinkShouldRun(blinkOn:false,vrEnabled:vr,loadedVideoActive:true,cameraAllowed:true),"blink off never runs (vr=\\(vr))")
 check(!CaptureConsumerRules.blinkShouldRun(blinkOn:true,vrEnabled:vr,loadedVideoActive:false,cameraAllowed:true),"no loaded file never runs (vr=\\(vr))")
 check(!CaptureConsumerRules.blinkShouldRun(blinkOn:true,vrEnabled:vr,loadedVideoActive:true,cameraAllowed:false),"no-camera mode never runs (vr=\\(vr))")
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);(p/'main.swift').write_text(program)
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
# Static: the only blink camera acquisition site stays updateCaptureConsumers, wired through the rule.
vr=(root/'Sources/gor/Stereo/VR180Controller.swift').read_text()
assert vr.count('HeadTracker.shared.start(owner: 2)')==1
assert 'blinkShouldRun(blinkOn: HeadTracker.shared.blinkLogEnabled,' in vr
assert 'vrEnabled: vrModeEnabled,' in vr
print('PASS single blink acquisition site routes through CaptureConsumerRules.blinkShouldRun')
print('UNVERIFIED native camera delivery, permission and recognizer; Darwin acceptance stays with the Mac runs')
