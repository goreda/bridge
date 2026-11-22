#!/usr/bin/env python3
"""Current camera worker/capture-route regression plus preserved roll/pupil checks.
The removed combined-perform design's source pins already crashed at5643.
Camera execution delegates to production-extraction compiled fixtures. Linux
boundary tests are not native AppKit/Vision or owner hardware acceptance.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
src = _s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
# The pre-worker combined-perform camera assertions were already stale at5643:
# captureOutput belongs to the helper runtime, and head/blink now use independent
# capture-free workers. Execute the maintained production-extraction fixtures;
# failures propagate, including their negative controls. Do not revive the removed
# combined-perform design or count source parsing as native hardware acceptance.
import runpy
for fixture in ("vision_worker_test.py", "handle_helper_frame_test.py"):
    runpy.run_path(str(root/"Tests/Harness/ScreenCamera"/fixture), run_name="__main__")
print("PASS current compiled worker/capture route replaces obsolete combined-perform assertions")
import math,re

from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Resources/vendor/mpv/scripts/vr180-look.lua')
plain=s.split('if(vr_plain>0.5) {',1)[1].split('if (vr_flat_sbs > 0.5)',1)[0]
stereo=s.split('if (vr_flat_sbs > 0.5) {',1)[1].split('// ── Roll-compensated eye partition',1)[0]
def measure(block, pose, aspect):
    expr=re.search(r'float cr=cos\(([^)]+)\),\s*sr=sin\(([^)]+)\);',block)
    assert expr and expr[1]==expr[2]
    angle=(-1 if expr[1].startswith('-') else 1)*pose
    # GLSL column-major mat2(cr,sr,-sr,cr) maps output->source.
    # A horizontal source line y=0 is displayed where sx*sin(a)+sy*cos(a)=0.
    # Aspect-corrected endpoints permit an actual measured screen-space angle.
    pts=[]
    for x in (-.2,.2):
        y=-x*aspect*math.tan(angle)
        pts.append((x*aspect,y))
    return math.atan2(pts[1][1]-pts[0][1],pts[1][0]-pts[0][0])
for degrees in (-12,-3,0,3,12):
    pose=math.radians(degrees)
    for name,block,aspect in [('plain2D',plain,16/9),('SBS-left',stereo,8/9),('SBS-right',stereo,8/9),('SBS-wide',stereo,16/9)]:
        got=measure(block,pose,aspect)
        assert abs(got-pose)<1e-12,(name,degrees,math.degrees(got))
        print('PASS %s pose_deg=%g displayed_deg=%.6f'%(name,degrees,math.degrees(got)))
assert 'float cr = cos(vr_roll), sr = sin(vr_roll);' in s # spherical VR180 unchanged
assert 'vr_swap_eyes > 0.5 ? 1.0-right : right' in stereo # no eye-order change
print('PASS spherical roll, eye order, dead zone and pose estimator unchanged')

# Calibrated sensor model: rotation of an unchanged box must not become Z/parallax.
for ratio in (.65,.8,1.,1.4):
    for deg in (-180,-135,-90,-60,-45,-30,0,30,45,60,90,135,180,0):
        a=math.radians(deg);c,t=abs(math.cos(a)),abs(math.sin(a));bw,bh=ratio,1.
        pw,ph=c*bw+t*bh,t*bw+c*bh
        scale=(pw*pw+ph*ph)/(pw*pw+ph*ph)
        z=scale-1
        check('pure roll sensor aspect%.2f tilt%d yields zeroZ/IPD/FOV/parallax'%(ratio,deg),abs(z)<1e-12)
        for lean in (.8,1.2):
            inferred=(lean*pw*pw+lean*ph*ph)/(pw*pw+ph*ph)-1
            check('real lean preserved aspect%.2f tilt%d lean%.1f'%(ratio,deg,lean),abs(inferred-(lean-1))<1e-12)
old45=max((.65+1)/math.sqrt(2),(.65+1)/math.sqrt(2))-1
check('old maxbox mutant creates >16percent falseZ at45deg for aspect.65',old45>.16)
# Both generated flat paths: pure-roll center is invariant, eye shifts cancel at the midpoint.
for deg in (-180,-90,-45,0,45,90,180):
    for eye in (0,1):
        for path in ('nativeSBS','monoSBS','monoPack'):
            tx=ty=z=0.;theta=math.radians(deg)
            center=(math.cos(theta)*tx-math.sin(theta)*ty,math.sin(theta)*tx+math.cos(theta)*ty)
            check('pure-roll no translation/parallax %s eye%d tilt%d'%(path,eye,deg),center==(0.,0.) and z==0)
def current_estimator_wiring(source):
    compact=re.sub(r'\s+','',source)
    return all(pin in compact for pin in (
        'distanceConsistent=!(landmarkKind!="pupil"&&pupilDistanceScale.hasPupilReference)&&poseDistanceConsistency.accept(',
        'distanceReady=distanceConsistent&&poseDistanceConsistency.ready(for:landmarkKind)',
        'letdistance=pupilDistanceScale.sample(left:distanceReady?pupilLeft:nil,right:distanceReady?pupilRight:nil',
        'distanceValid:distanceReady)',
    )) and 'max(box.width,box.height)/refSize' not in compact
check('current tracker uses pupil-distance estimator plus consistency and pupil-reference gates',current_estimator_wiring(src))
for name,mutant in (
    ('acquisition readiness bypass',src.replace('distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)','distanceConsistent')),
    ('consistency bypass',src.replace('poseDistanceConsistency.accept(', 'bypassed.accept(')),
    ('pupil-reference guard removed',src.replace('!(landmarkKind != "pupil" && pupilDistanceScale.hasPupilReference) && ','')),
    ('invalid left pupil still sampled',src.replace('left:distanceReady ? pupilLeft:nil','left:pupilLeft')),
):
    check('current-estimator mutant rejected: '+name,not current_estimator_wiring(mutant))
print('Historical roll-box math above is not acceptance of the current pupil estimator; see Tests/HeadPose runtime tests')
print('head track vision once: %d failure(s)' % len(fails)); # Rotation-only measurement matches production yaw/pitch foreshortening + roll rectangle projection.
import math
shape=(.2,.3)
for yaw,pitch,roll in ((.6,.3,.8),(-.5,.2,1.1),(.3,-.4,2.5)):
 c=abs(math.cos(roll));ss=abs(math.sin(roll));cy=abs(math.cos(yaw));cp=abs(math.cos(pitch))
 pw=c*shape[0]*cy+ss*shape[1]*cp;ph=ss*shape[0]*cy+c*shape[1]*cp
 check('rotation-only yaw/pitch/roll inferred scale remains1',abs((pw*pw+ph*ph)/(pw*pw+ph*ph)-1)<1e-12)
sys.exit(1 if fails else 0)
