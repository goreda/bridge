#!/usr/bin/env python3
"""Compile real retire + receipt methods; late SBS receipt must not undo Off."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2];s=(_pp_split().path(root,'PPController.swift')).read_text()
def method(sig):
 a=s.index(sig);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')
program='''import Foundation
class VR {var expectsSBSFilmFrame=true}
class Probe {
 let vr180Controller:VR?=VR();var filmFrameSequenceFloor:[String:Double]=[:]
 var committedFilmFrame:[String:Double]?=nil,pendingFilmFrame:[String:[String:Any]]=[:]
 var filmFramePath="Movie",filmIdentityPending=false,filmFirstReceiptAt=Date.distantPast
 var vrModeEnabled=true,appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero,bounds=CGRect(x:0,y:0,width:819,height:546),layouts=0
 func applyTrackedUITilt(){}
 func applyVideoFrame(bounds:CGRect){layouts+=1}
 func traceFilmUI(_ s:String,receiptPath:String?=nil){}
'''+method('private func clearCommittedFilmFrame(')+'\n'+method('private func retireSBSFilmFrame(')+'\n'+method('private func noteFilmFrame(')+'''
}
let p=Probe()
var frame:[String:Any]=["path":"Movie"]
for key in ["sequence","scale","angle","leftX","leftY","replicaX","replicaY","width","height","frameW","frameH","baseX","baseY","layout","instances","clipX","clipY","clipW","clipH"] {frame[key]=NSNumber(value:1)}
frame["layout"]=NSNumber(value:3);frame["angle"]=NSNumber(value:0.25)
p.noteFilmFrame(frame);precondition(p.committedFilmFrame?["layout"]==3)
p.vrModeEnabled=false;p.retireSBSFilmFrame()
precondition(p.committedFilmFrame==nil,"Off retained SBS rail")
p.noteFilmFrame(frame)
precondition(p.committedFilmFrame==nil,"late SBS receipt undid Off")
frame["layout"]=NSNumber(value:0);frame["sequence"]=NSNumber(value:10);p.noteFilmFrame(frame)
let latest=p.committedFilmFrame
frame["sequence"]=NSNumber(value:9);p.noteFilmFrame(frame)
precondition(p.committedFilmFrame==latest,"old get reply rolled back newer observation")
frame["sequence"]=NSNumber(value:11)
precondition(p.committedFilmFrame?["layout"]==0,"plain head-tools receipt rejected after Off")
p.retireSBSFilmFrame();precondition(p.committedFilmFrame?["layout"]==0,"Off retirement removed plain frame")
p.vrModeEnabled=true;frame["layout"]=NSNumber(value:3);p.noteFilmFrame(frame)
precondition(p.committedFilmFrame?["layout"]==3,"SBS re-entry lost valid frame")
p.retireSBSFilmFrame();p.vr180Controller!.expectsSBSFilmFrame=false
frame["sequence"]=NSNumber(value:20);p.noteFilmFrame(frame)
precondition(p.committedFilmFrame==nil,"late SBS accepted after VR180/TB mode")
for layout in [1.0,2.0] {
 frame["layout"]=NSNumber(value:layout);frame["sequence"]=NSNumber(value:21+layout);p.noteFilmFrame(frame)
 precondition(p.committedFilmFrame?["layout"]==layout,"steady TB/anaglyph preview receipt rejected after transient SBS")
}
p.clearCommittedFilmFrame();frame["layout"]=NSNumber(value:3)
p.vr180Controller!.expectsSBSFilmFrame=true;frame["sequence"]=NSNumber(value:10);p.noteFilmFrame(frame)
precondition(p.committedFilmFrame==nil,"rapid SBS-Off-SBS accepted older frame")
frame["sequence"]=NSNumber(value:24);p.noteFilmFrame(frame)
let before=p.layouts
frame.removeValue(forKey:"frameW");p.noteFilmFrame(frame)
precondition(p.committedFilmFrame==nil && p.layouts==before+1,"partial receipt kept stale rail without relayout")
frame["frameW"]=NSNumber(value:1);frame["sequence"]=NSNumber(value:25);p.noteFilmFrame(frame)
let beforeFalse=p.layouts;p.noteFilmFrame(false)
precondition(p.committedFilmFrame==nil && p.layouts==beforeFalse+1,"false receipt kept stale rail without relayout")
print("PASS actual mode exit: SBS->Off retires rail, late same-path SBS cannot restore it; plain independent-tools receipt survives and SBS reentry works")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
 # The negative mutation exactly removes the newly added mode barrier.
 mutant=program.replace('''        if fields["layout"]==3,(!vrModeEnabled || vr180Controller?.expectsSBSFilmFrame != true) {
            traceFilmUI("FILM-FRAME-REJECT retired-sbs-mode",receiptPath:path);return
        }
''','')
 (p/'main.swift').write_text(mutant)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'red')],check=True)
 red=subprocess.run([str(p/'red')],capture_output=True,text=True)
 assert red.returncode!=0 and 'late SBS receipt undid Off' in red.stderr
 print('PASS mode-barrier negative control RED')
