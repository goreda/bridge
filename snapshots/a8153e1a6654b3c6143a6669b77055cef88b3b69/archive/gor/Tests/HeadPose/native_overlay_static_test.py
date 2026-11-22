#!/usr/bin/env python3
"""Compile actual head publisher: native overlays fixed, camera pose unchanged."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile,json
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController_Features.swift')).read_text()
a=s.index('    private func applyHeadPose(');b=s.index('\n    func recenterHeadTracking',a)
constants='\n'.join(l.strip() for l in s.splitlines() if any(('static let '+n+':') in l for n in ['headRotationGain','headFovGain','headLeanNudgeFovDegPerUnit','headTrackingRestFovDeg','headTranslateMetersPerUnit','headIpdNudgePerUnit']))
main='''import Foundation
enum Key {case headInvert}
enum Value:Equatable {case bool(Bool)}
struct Snapshot {var effects:[Key:Value]=[:]}
@MainActor final class ThreeDStore {static let shared=ThreeDStore();var snapshot=Snapshot()}
enum VRDistance {static func mmPerPx()->Double {0.2}}
struct HeadPose {var yaw=0.12,pitch = -0.08,roll=0.3,xOffset=0.02,yOffset = -0.01,zOffset=0.1;var distanceMM:Double?=600;var distanceFallback:String?;var fusionRoll:Double?=0.25,nativeRawRoll:Double?=0.31}
final class Probe {
var recenterPosePublishing=false,headTrackingEnabled=true,loadedVideoActive=true,swapEyes=false
var projectionKind="flat-2d3d",depthDistanceMM:Double?
var subtitle:(Double,Double)=(99,99),ui=99.0,commands:[String]=[]
var onSubtitleTilt:((Double,Double)->Void)?,onUITilt:((Double)->Void)?
func sendRaw(_ value:String){commands.append(value)}
'''+constants+'\n'+s[a:b]+'''
func run(){applyHeadPose(HeadPose())}
}
MainActor.assumeIsolated {
for kind in ["vr180","vr180-tb","vr360-mono","vr360-tb","flat-2d3d","flat-sbs","flat-tb"] {
 for inverted in [false,true] {for swapped in [false,true] {
 let p=Probe();p.projectionKind=kind;p.swapEyes=swapped
 p.onSubtitleTilt={p.subtitle=($0,$1)};p.onUITilt={p.ui=$0}
 ThreeDStore.shared.snapshot.effects[.headInvert] = .bool(inverted);p.run()
 let sign=inverted ? -1.0:1.0,native=kind.hasPrefix("vr")
 if native {assert(p.ui==0 && p.subtitle.0==0 && p.subtitle.1==0)}
 else {assert(abs(p.ui-sign*0.3)<1e-10 && abs(p.subtitle.0-p.ui)<1e-10)}
 let obj=try! JSONSerialization.jsonObject(with:Data(p.commands.last!.utf8)) as! [String:Any]
 let args=obj["command"] as! [String]
 assert(abs(Double(args[6])!-sign*0.3)<1e-10)
 assert(abs(Double(args[14])!-sign*0.25)<1e-10 && abs(Double(args[15])!-sign*0.31)<1e-10)
 print("PASS native overlay static / flat overlay active, original pose retained",kind,inverted,swapped)
 } }
}
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
print('PASS actual publisher28cases; source-eye swap and native camera raw/fusion roll untouched')
