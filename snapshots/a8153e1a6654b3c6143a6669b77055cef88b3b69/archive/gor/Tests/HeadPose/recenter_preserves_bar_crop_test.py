#!/usr/bin/env python3
"""Compile actual PPController Shift+R entry: crop and fitted frame stay untouched."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController.swift')).read_text()
a=s.index('    func recenterHeadTracking() {');b=s.index('\n    func adjustBaseIPD',a)
method=s[a:b]
program='''import Foundation
class Camera {var resets=0;func recenterHeadTracking(){resets+=1}}
class Probe {
var stereoManualAspect:Double?=1.5
let vr180Controller:Camera?=Camera()
var detectorCrop=CGRect(x:0.15,y:0.2,width:0.7,height:0.6),clears=0
func clearOwnedCropFromMenu(){clears+=1;detectorCrop=CGRect(x:0,y:0,width:1,height:1)}
'''+method+'''
}
let p=Probe(),before=p.detectorCrop
p.recenterHeadTracking()
precondition(p.detectorCrop==before && p.clears==0,"Shift+R destroyed accepted detector bar crop")
precondition(p.stereoManualAspect==1.5,"Shift+R changed accepted fitted frame")
precondition(p.vr180Controller!.resets==1,"Shift+R did not reach live tracker reset")
print("PASS actual PPController Shift+R preserves accepted bar crop/frame and reaches tracker")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
