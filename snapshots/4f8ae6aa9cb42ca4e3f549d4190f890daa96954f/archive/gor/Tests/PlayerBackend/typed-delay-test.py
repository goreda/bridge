#!/usr/bin/env python3
"""Exact host delay and chrome adjustment methods, recorder session/HUD only."""
from pathlib import Path
import os,re,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
def method(s,key):
 a=s.index(key);b=s.index('{',a);i=b+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
h=(r/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text();p=(r/'Sources/gor/Player/PPController.swift').read_text()  # live file: current-behavior tests read live, the pp-split rebuild is historical
assert 'guard let self else {return "host closed"};return self.applyChromeDelay(property,seconds)' in h
# Extractions end at the closing brace with no trailing newline: join with
# newlines or the next func lands on the same line (Swift: consecutive
# declarations on a line must be separated by semicolon).
host='\n'.join(m.replace('private func','func') for m in (
    method(h,'    private func applyChromeDelay('),
    method(h,'    private func applyChromeSubtitleScale(')))
chrome=method(p,'    private func adjustEmbeddedSubtitleProperty(').replace('private func','func')
assert not re.search(r'\}[ \t]*func ', host), 'extracted host methods must be newline-joined'
assert re.search(r'(?m)^[ \t]*func applyChromeDelay\(', host) and re.search(r'(?m)^[ \t]*func applyChromeSubtitleScale\(', host), 'each extracted func starts on its own line'
prod='''import Foundation
final class Session {var rejects=false;var subCalls:[Double]=[];var audioCalls:[Double]=[];var scaleCalls:[Double]=[]
 enum Slot {case primary};enum Refusal:Error {case rejected}
 func setSubtitleDelay(_ v:Double,slot:Slot)->String? {subCalls.append(v);return rejects ? "closed" : nil}
 func setAudioDelay(seconds:Double) throws {audioCalls.append(seconds);if rejects {throw Refusal.rejected}}
 func setSubtitleFontScale(_ v:Double)->String? {if rejects {return "closed"};if !(0.1...10).contains(v) {return "out of range"};scaleCalls.append(v);return nil}  // accepted commits only: rejected/out-of-range attempts never enter scaleCalls
}
final class Host {var session:Session?;var volumeSessionReady=false
'''+host+'''
}
final class Spine {var lines:[String]=[];func showMPVOSD(_ text:String,duration:Double,force:Bool) {lines.append(text)}}
final class Chrome {var embeddedSubDelay=0.0;var embeddedAudioDelay=0.0;var embeddedSubScale=1.0;var embeddedDelay:((String,Double)->String?)?;var embeddedSubtitleScale:((_ scale:Double)->String?)?;var spineUI=Spine()
 func refuseEmbedded(_ control:String)->Bool {spineUI.lines.append("gorav unavailable: "+control);return true}
'''+chrome+'\n}\n'
main='''import Foundation
let h=Host(),c=Chrome(),s=Session();h.session=s
c.embeddedDelay={ [weak h] property,seconds in guard let h else {return "host closed"};return h.applyChromeDelay(property,seconds) }
c.embeddedSubtitleScale={ [weak h] scale in guard let h else {return "host closed"};return h.applyChromeSubtitleScale(scale) }
precondition(!c.adjustEmbeddedSubtitleProperty("audio-delay",delta:0.5,reset:false))
precondition(c.embeddedAudioDelay==0 && s.audioCalls.isEmpty)
precondition(!c.adjustEmbeddedSubtitleProperty("sub-scale",delta:0.1,reset:false))
precondition(c.embeddedSubScale==1.0 && s.scaleCalls.isEmpty)
precondition(c.spineUI.lines.last?.contains("unavailable") == true)
h.volumeSessionReady=true
precondition(c.adjustEmbeddedSubtitleProperty("audio-delay",delta:0.5,reset:false))
precondition(c.embeddedAudioDelay==0.5 && s.audioCalls==[0.5])
s.rejects=true
precondition(!c.adjustEmbeddedSubtitleProperty("audio-delay",delta:0.2,reset:false))
precondition(c.embeddedAudioDelay==0.5)
precondition(!c.adjustEmbeddedSubtitleProperty("sub-delay",delta:0.2,reset:false))
precondition(c.embeddedSubDelay==0)
precondition(!c.adjustEmbeddedSubtitleProperty("sub-scale",delta:0.2,reset:false))
precondition(c.embeddedSubScale==1.0 && s.scaleCalls.isEmpty)
s.rejects=false
precondition(c.adjustEmbeddedSubtitleProperty("sub-delay",delta:0.25,reset:false))
precondition(c.embeddedSubDelay==0.25)
precondition(c.adjustEmbeddedSubtitleProperty("sub-scale",delta:0.1,reset:false))
precondition(c.embeddedSubScale==1.1 && s.scaleCalls==[1.1])
precondition(c.spineUI.lines.last == "subtitle font size: 110%")
precondition(!c.adjustEmbeddedSubtitleProperty("sub-scale",delta:20,reset:false))
precondition(c.embeddedSubScale==1.1 && s.scaleCalls==[1.1])
precondition(c.adjustEmbeddedSubtitleProperty("sub-scale",delta:0,reset:true))
precondition(c.embeddedSubScale==1.0 && s.scaleCalls==[1.1,1.0])
precondition(c.spineUI.lines.last == "subtitle font size: 100%")
precondition(!c.adjustEmbeddedSubtitleProperty("sub-pos",delta:1,reset:false))
precondition(h.applyChromeDelay("audio-delay",.nan) != nil)
precondition(h.applyChromeSubtitleScale(.nan) != nil)
print("PASS accepted nil success, rejected/unready delay and scale do not commit, sub-scale commits through the actual renderer path, out-of-range scale and sub-pos refusals preserved")
'''
variants=[('fixed',prod),('mutant-ignore-reject',prod.replace('if let reason=apply(property,target)','if let reason=Optional<String>.none')),('mutant-ignore-scale-reject',prod.replace('if let reason=apply(target)','if let reason=Optional<String>.none')),('mutant-unready',prod.replace('guard let session,volumeSessionReady else','guard let session else'))]
with tempfile.TemporaryDirectory(prefix='typed-delay-') as td:
 t=Path(td);(t/'main.swift').write_text(main)
 for label,code in variants:
  (t/'Production.swift').write_text(code)
  for opt in ['-Onone','-O']:
   q=subprocess.run([os.environ.get('SWIFTC','swiftc'),opt,str(t/'Production.swift'),str(t/'main.swift'),'-o',str(t/'probe')],capture_output=True,text=True)
   assert q.returncode==0,(label,q.stderr)
   q=subprocess.run([str(t/'probe')],capture_output=True,text=True)
   assert (q.returncode==0)==(label=='fixed'),(label,opt,q.stdout,q.stderr)
   print(label,opt,'GREEN' if q.returncode==0 else 'RED')
print('NOT_RUN actual subtitle renderer/audio output/owner pixels')
