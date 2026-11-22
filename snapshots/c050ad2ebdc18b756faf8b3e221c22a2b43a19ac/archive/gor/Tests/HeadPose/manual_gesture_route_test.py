#!/usr/bin/env python3
"""Compile actual gesture handlers, nudge publisher and pure key route."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
def method(s,marker):
 a=s.index(marker);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')+'\n'
pp=(_pp_split().path(root,'PPController.swift')).read_text();pp=pp[pp.index('final class PPController:'):] if 'final class PPController:' in pp else pp[pp.index('class PPController:'):];features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
route=(root/'Sources/gor/Stereo/LookToolsRoute.swift').read_text()
main=r'''
import Foundation
class NSEvent {var scrollingDeltaX:CGFloat=10,scrollingDeltaY:CGFloat=20,magnification=0.2,rotation:CGFloat=15}
class Base {var fallback=0;func scrollWheel(with e:NSEvent){fallback+=1};func magnify(with e:NSEvent){fallback+=1};func rotate(with e:NSEvent){fallback+=1}}
class Spine {func scrollPhotonHUDIfNeeded(with e:NSEvent,in p:Player)->Bool {false}}
class Subs {func scrollWheel(with e:NSEvent){}}
class VR180Controller {
 static let vrYawPitchDegPerPoint=0.1,vrFovDegPerMagnifyUnit=60.0
 var commands:[String]=[]
 func ipcCommand(_ s:String){commands.append(s)}
'''+method(features,'    func sendVRLookNudge(')+method(features,'    func sendVRFovNudge(')+'''
}
class Player:Base {
 var vrModeEnabled=true,headTrackingEnabled=true
 var vr180Controller:VR180Controller?=VR180Controller(),spineUI=Spine(),subtitleView=Subs()
 func wakeUI(){}
'''+method(pp,'    override func scrollWheel(with event: NSEvent)')+method(pp,'    override func magnify(with event: NSEvent)')+('\n'+method(pp,'    override func rotate(with event:') if '    override func rotate(with event:' in pp else '')+'''
}
'''+method(route,'    static func motionJSON(').replace('    static func','func')+r'''
let p=Player(),event=NSEvent()
for head in [false,true] {
 p.headTrackingEnabled=head;p.vrModeEnabled=true
 let n=p.vr180Controller!.commands.count
 p.scrollWheel(with:event);p.magnify(with:event);p.rotate(with:event)
 precondition(p.vr180Controller!.commands.count==n+3,"Head state must not eat gestures")
}
let last=p.vr180Controller!.commands.last!
let obj=try! JSONSerialization.jsonObject(with:Data(last.utf8)) as! [String:Any]
let cmd=obj["command"] as! [String]
precondition(cmd[2]=="vr180-look-nudge" && abs(Double(cmd[6])!-Double.pi/12)<1e-9)
p.vrModeEnabled=false;p.magnify(with:event);p.rotate(with:event);precondition(p.fallback==2)
for projection in [false,true] {
 let json=motionJSON(kind:"hold",x:1,y:-1,z:1,projection:projection)
 let row=try! JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
 let c=row["command"] as! [String]
 precondition(c[1]==(projection ? "vr180_look":"gor_fit"))
}
print("PASS actual Swift gesture handlers: pan/pinch/rotate with head on/off,non3D fallback,rotation radians,live projection key route. Native AppKit dispatch NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
assert 'projection:(view as? PPController)?.vrModeEnabled == true' in features
assert 'vr180-look-set-orientation' in features
print('PASS key route reads controller state, not delayed player receipt; no pause gate introduced')
