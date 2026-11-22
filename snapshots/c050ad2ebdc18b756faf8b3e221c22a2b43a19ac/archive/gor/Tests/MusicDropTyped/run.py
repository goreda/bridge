#!/usr/bin/env python3
"""Actual extracted drag/drop control flow plus backend command capture.
Foundation Swift seam only. No AppKit dragging, mpv socket or native UI claim.
"""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--emit',type=Path);a=p.parse_args()
r=a.root
source=(r/'Sources/gor/Modes/MusicPanel.swift').read_text();backend=(r/'Sources/gor/Engine/MPVCommand.swift').read_text()
def block(text,signature):
 start=text.index(signature);brace=text.index('{',start);depth=0
 for i in range(brace,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[start:i+1]
 raise AssertionError('unclosed '+signature)
drag=block(source,'    override func performDragOperation(')
assert 'ctrl.playbackOperations.addSubtitle(path:url.path)' in drag
assert 'ctrl.playbackOperations.openMedia(path:url.path)' in drag
assert 'MPVCommand' not in drag and 'ipcCommand' not in drag
builder=block(backend,'enum MPVCommand {');operations=block(backend,'struct PlayerPlaybackOperations {');sample=block(backend,'enum PlayerCropSample {');packet=block(backend,'struct PlayerCropPacket {')
# Only the AppKit override keyword/type collaborators are adapted. The complete
# actual function body and actual backend operation struct execute unchanged.
harness='''import Foundation
struct Kind { static let fileURL=Kind() }
struct Item {let value:String?;func string(forType:Kind)->String? {value}}
struct Board {let pasteboardItems:[Item]?}
struct Sender {let draggingPasteboard:Board}
typealias NSDraggingInfo=Sender
final class PPController {
 var iptvChannelTitle="keep"
 var captured:[String]=[]
 var playbackOperations:PlayerPlaybackOperations {PlayerPlaybackOperations(command:{self.captured.append($0)},persistent:{_ in},packet:{_,_,_ in},reset:{_ in})}
}
final class Panel {var superview:AnyObject?
'''+drag.replace('override func','func',1)+'''
}
func demand(_ value:@autoclosure()->Bool,_ label:String){precondition(value(),label)}
var count=0
func sender(_ values:[String?]?)->Sender {Sender(draggingPasteboard:Board(pasteboardItems:values?.map{Item(value:$0)}))}
func decoded(_ lines:[String])->[[String]] {lines.map {let d=try! JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any];demand(!$0.contains("\\n") && !$0.contains("\\r"),"one frame");return d["command"] as! [String]}}
func run(_ values:[String?]?,_ expected:Bool,_ command:[String]?,_ title:String="keep",host:Bool=true){
 let ctrl=PPController();let panel=Panel();panel.superview=host ? ctrl:nil
 demand(panel.performDragOperation(sender(values))==expected,"return");count+=1
 demand(decoded(ctrl.captured)==(command.map{[$0]} ?? []),"command and first-valid item");count+=1
 demand(ctrl.iptvChannelTitle==title,"title ownership");count+=1
}
run(nil,false,nil)
run([],false,nil)
run([nil,"http://[","file:///tmp/a.txt"],false,nil)
for ext in ["srt","ass","ssa","vtt","sub","SRT"] {run(["file:///tmp/a."+ext],true,["sub-add","/tmp/a."+ext])}
for ext in ["mkv","mp4","avi","mov","m4v","webm","ts","flv","MP4"] {run(["file:///tmp/a."+ext],true,["loadfile","/tmp/a."+ext],"")}
run(["file:///tmp/a.srt","file:///tmp/b.mp4"],true,["sub-add","/tmp/a.srt"])
run(["file:///tmp/a.mp4","file:///tmp/b.srt"],true,["loadfile","/tmp/a.mp4"],"")
run([nil,"file:///tmp/a.txt","file:///tmp/b.vtt"],true,["sub-add","/tmp/b.vtt"])
run(["file:///tmp/a.srt"],true,nil,host:false)
run(["file:///tmp/a.mp4"],true,nil,host:false)
run(["file:///tmp/a%0A%22%5C%F0%9F%8E%AC.srt"],true,["sub-add","/tmp/a\\n\\"\\\\🎬.srt"])
print("PASS actual MusicPanel drag/drop + typed backend: \\(count) assertions")
'''
program=harness.replace('import Foundation\n','import Foundation\n'+builder+'\n'+sample+'\n'+packet+'\n'+operations+'\n',1)
if a.emit:a.emit.write_text(program)
compiler=shutil.which('swiftc')
if not compiler:
 print('NOT_RUN actual Swift executor unavailable; emitted harness is not runtime proof');raise SystemExit(77)
with tempfile.TemporaryDirectory() as td:
 td=Path(td);f=td/'main.swift';f.write_text(program);exe=td/'check'
 subprocess.run([compiler,str(f),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
 mutants={
  'wrong_subtitle_command':program.replace('MPVCommand.make(["sub-add",path])','MPVCommand.make(["loadfile",path])'),
  'wrong_media_command':program.replace('MPVCommand.make(["loadfile",path])','MPVCommand.make(["sub-add",path])'),
  'clear_title_for_subtitle':program.replace('ctrl.playbackOperations.addSubtitle(path:url.path)','ctrl.iptvChannelTitle = "";ctrl.playbackOperations.addSubtitle(path:url.path)'),
  'keep_video_title':program.replace('ctrl.iptvChannelTitle = ""\n',''),
  'continue_after_subtitle':program.replace('                return true','                continue',1),
 }
 for name,body in mutants.items():
  assert body!=program,'mutation did not apply: '+name
  f.write_text(body);build=subprocess.run([compiler,str(f),'-o',str(exe)],capture_output=True,text=True)
  assert build.returncode==0,'compile error is not mutant kill: '+name+'\n'+build.stderr
  result=subprocess.run([str(exe)],capture_output=True,text=True)
  assert result.returncode!=0,'mutant survived: '+name
  print('PASS compiled runtime mutant rejected',name,result.returncode)

print(json.dumps({'scope':__doc__,'source_sha256':{str(x.relative_to(r)):hashlib.sha256(x.read_bytes()).hexdigest() for x in [r/'Sources/gor/Modes/MusicPanel.swift',r/'Sources/gor/Engine/MPVCommand.swift']},'harness_sha256':hashlib.sha256(program.encode()).hexdigest()},indent=2))
