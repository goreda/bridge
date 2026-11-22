#!/usr/bin/env python3
"""191a C1/C5: per-channel pose direction test (owner report 2026-11-09
phonemsg-01M70RPX610GYR2Y53DTTAC6TT: looking right shifted the picture LEFT -
"everything reversed"). Asserts the end-to-end screen direction of EVERY pose
channel against the window/content-follows-head semantic, using the LIVE Swift
sign constants parsed out of ScreenCaptureEngine.swift (a wrong future flip
fails here, not on the owner's screen), plus the gain constants' text pins,
plus the deterministic pose trace golden showing the sign per channel.
Audit and conventions: tools/head_pose/pose_signs.py.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import pose_signs as ps  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def info(line):
    print("INFO " + line)


def sphere(action):
    return ps.sphere_screen_effect(ps.chain(action))


# --- the owner's channel (VR180 sphere path): content follows the head ---
e = sphere("look right")
check("yaw: look right -> content moves RIGHT (was the owner's complaint)", e["content_dx"] > 0.1)
e = sphere("look left")
check("yaw: look left -> content moves LEFT", e["content_dx"] < -0.1)
e = sphere("look down")
check("pitch: look down -> content moves DOWN", e["content_dy"] > 0.1)
e = sphere("look up")
check("pitch: look up -> content moves UP", e["content_dy"] < -0.1)
e = sphere("tilt left")
check("roll: tilt head left -> picture top tips LEFT (world-fixed horizon, owner-approved 2026-11-05)",
      e["picture_roll"] < -0.1)
e = sphere("move right")
check("x: move head right -> content moves RIGHT (window parallax)", e["content_dx"] > 0.01)
e = sphere("move up")
check("y: move head up -> content moves UP", e["content_dy"] < -0.01)
e = sphere("lean in")
check("z: lean in -> content grows (magnification > 1)", e["magnification"] > 1.5)
check("z: lean in -> convergence nudge increases (distance-linked, owner 2026-11-05)",
      e["ipd_nudge"] > 0)

# --- mutants: every sign constant is load-bearing ---
def with_swift_const(name, value):
    import re
    patched = re.sub(r"(static let %s:\s*Double = )[-\d.]+" % name,
                     r"\g<1>%s" % value, ps.SWIFT)
    assert patched != ps.SWIFT
    signs = tuple(ps._swift_const(n, patched)
                  for n in ("yawSign", "pitchSign", "rollSign", "xOffsetSign", "yOffsetSign"))
    return lambda action: ps.sphere_screen_effect(ps.chain(action, signs=signs))


s = with_swift_const("yawSign", "-1.0")
check("mutant: yawSign -1 -> look right moves content LEFT (the owner's bug, caught)",
      s("look right")["content_dx"] < -0.1)
s = with_swift_const("pitchSign", "1.0")
check("mutant: pitchSign +1 -> look down moves content UP (caught)",
      s("look down")["content_dy"] < -0.1)
s = with_swift_const("rollSign", "-1.0")
check("mutant: rollSign -1 -> tilt left tips the picture RIGHT (caught)",
      s("tilt left")["picture_roll"] > 0.1)
s = with_swift_const("xOffsetSign", "1.0")
check("mutant: xOffsetSign +1 -> move right moves content LEFT (caught)",
      s("move right")["content_dx"] < -0.01)
s = with_swift_const("yOffsetSign", "-1.0")
check("mutant: yOffsetSign -1 -> move up moves content DOWN (caught)",
      s("move up")["content_dy"] > 0.01)

# --- Swift gain pins (the other half of the chain) ---
pp = _s3read(_pp_split().path(root,'PPController_Features.swift'))
for frag in ("static let headRotationGain: Double = 1.0",
             "static let headTranslateMetersPerUnit: Double = 0.20",
             "static let headLeanNudgeFovDegPerUnit: Double = -150.0",
             "private static let headZTranslateSign: Double = -1.0"):
    check("swift pin: " + frag, frag in pp)
lua = _s3read(root / "Resources/vendor/mpv/scripts/vr180-look.lua")
check("lua pin: positive pitch looks down convention documented",
      "positive pitch looks down" in lua)

# --- flat projection path (post-812702cb E-G alignment): every channel must
# AGREE in direction with the sphere path ---
for action, key, name in (("look right", "content_dx", "yaw"),
                          ("look down", "content_dy", "pitch"),
                          ("move right", "content_dx", "head_x"),
                          ("move up", "content_dy", "head_y")):
    fe = ps.flat_screen_effect(ps.chain(action))[key]
    se = sphere(action)[key]
    check("flat agrees with sphere: %s (%s: flat %+.3f vs sphere %+.3f)"
          % (name, action, fe, se), fe * se > 0)
# shader text pins for the aligned form (manual pitch keeps its own - sign)
check("lua pin: flat aligned (vr_yaw,vr_pitch)", "(vec2(vr_yaw,vr_pitch)" in lua)
check("lua pin: flat aligned (-vr_head_x,vr_head_y)*0.5",
      "vec2(-vr_head_x,vr_head_y)*0.5" in lua)

# --- pose trace golden: the audit artifact, sign visible per channel ---
golden = root / "Tests/HeadPose/pose_sign_trace.jsonl"
rows = ps.trace_rows()
if not golden.exists():
    check("trace golden exists: Tests/HeadPose/pose_sign_trace.jsonl", False)
else:
    check("pose trace matches golden (sign per channel visible)",
          _s3read(golden).splitlines() == rows)

# Compile the actual production publisher, then compare emitted IPC fields.
# The switch changes mapping only. It does not alter camera calibration, stored
# source/output, gains, physical distance or anatomical convergence measurements.
import os, subprocess, tempfile, re
start=pp.index('    private func applyHeadPose(')
end=pp.index('\n    func recenterHeadTracking',start)
method=pp[start:end]
constants='\n'.join(line.strip() for line in pp.splitlines() if any(('static let '+n+':') in line for n in ['headRotationGain','headFovGain','headLeanNudgeFovDegPerUnit','headTrackingRestFovDeg','headTranslateMetersPerUnit','headIpdNudgePerUnit']))
probe=r'''import Foundation
enum Key {case headInvert}
enum Value:Equatable {case bool(Bool)}
struct Snapshot {var effects:[Key:Value]=[:]}
@MainActor final class ThreeDStore {static let shared=ThreeDStore();var snapshot=Snapshot()}
enum VRDistance {static func mmPerPx()->Double {0.2}}
struct HeadPose {var yaw=0.1,pitch=0.2,roll=0.3,xOffset=0.4,yOffset=0.5,zOffset=0.1;var distanceMM:Double?=600;var distanceFallback:String?;var fusionRoll:Double?=0.35,nativeRawRoll:Double?=0.4}
final class Probe {
var recenterPosePublishing=false
var headTrackingEnabled=true,loadedVideoActive=true,projectionKind="flat-2d3d",swapEyes=false
var depthDistanceMM:Double?;var onSubtitleTilt:((Double,Double)->Void)?;var onUITilt:((Double)->Void)?
func sendRaw(_ value:String) {print(value)}
''' + constants + '\n' + method + r'''
func run(){applyHeadPose(HeadPose())}
}
MainActor.assumeIsolated {
let p=Probe()
for native in [false,true] {
 p.projectionKind=native ? "vr180":"flat-2d3d"
 for inverted in [false,true] {
  ThreeDStore.shared.snapshot.effects[.headInvert] = .bool(inverted);p.run()
 }
}
}
'''
with tempfile.TemporaryDirectory() as folder:
 q=pathlib.Path(folder);(q/'main.swift').write_text(probe)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(q/'main.swift'),'-o',str(q/'probe')],check=True)
 rows=[json.loads(line)['command'][3:] for line in subprocess.check_output([str(q/'probe')],text=True).splitlines()]
 for i in (0,2):
  normal,inverse=rows[i],rows[i+1]
  for index in [0,1,3,5,6,11,12]:check('actual publisher invert axis %d native=%s'%(index,i==2),abs(float(normal[index])+float(inverse[index]))<1e-9)
  if i==2:
   check('native publisher invert distance zoom around135',abs(float(normal[2])+float(inverse[2])-270)<1e-9)
  else:
   import math
   magnifications=[math.tan(math.radians(135)/2)/math.tan(math.radians(float(row[2]))/2) for row in [normal,inverse]]
   check('flat publisher invert measured scale around1',abs(sum(magnifications)-2)<1e-9)
  check('physical convergence/distance measurements unchanged',all(normal[k]==inverse[k] for k in [4,7,8,9,10]))

print("pose signs: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
