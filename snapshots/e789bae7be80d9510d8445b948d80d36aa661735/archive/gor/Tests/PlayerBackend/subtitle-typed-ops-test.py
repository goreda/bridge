#!/usr/bin/env python3
"""Exact host methods for gorav subtitle visibility, SRT select/cycle, audio track cycle, typed delay wiring.
Production method text is sliced from GorAVPlayerHost.swift and compiled against recorder stubs only.
Swift needs swiftc (Darwin or Linux toolchain). --wiring-only checks slices and mutant distinctness without Swift.
Place at archive/gor/Tests/PlayerBackend/subtitle-typed-ops-test.py."""
from pathlib import Path
import os,subprocess,sys,tempfile,shutil
r=Path(__file__).resolve().parents[2]
def method(s,key):
 a=s.index(key);b=s.index('{',a);i=b+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
h=(r/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
def m(key):return method(h,key).replace('private func','func')
def slices():
 wire_line=[l for l in h.splitlines() if 'controls.embeddedDelay=' in l]
 assert len(wire_line)==1
 closure=wire_line[0].split('controls.embeddedDelay=',1)[1].strip()
 return dict(
  osd=m('    private func osd('),vis=m('    private func applySubtitleVisible('),sel=m('    private func selectTextSubtitle('),
  cyc=m('    private func cycleTextSubtitle('),aud=m('    private func cycleAudioTrack('),delay=m('    private func applyChromeDelay('),wire=closure)
def build(sl):
 return '''import Foundation
enum Slot {case primary}
enum SubSel {case selected(path:String,slot:Slot),noExactSidecar,refused(String)}
struct Cand {let path:String;let format:String}
struct TrackInfo {let index:Int;let language:String?;let title:String?}
enum Sel {case index(Int)}
struct Boom:Error {}
@MainActor final class Session {
 var owner=true;var visCalls:[Bool]=[];var selectOverride:SubSel?;var selectCalls:[String]=[]
 var candidates:[Cand]=[];var inventory:(tracks:[TrackInfo],activeIndex:Int?)?=nil
 var invDelay:UInt64=0;var selDelay:UInt64=0;var setDelay:UInt64=0;var setThrows=false;var setCalls:[Int]=[]
 var subRefuse=false;var audioThrows=false
 var subtitleCandidates:[Cand] {candidates}
 func setSubtitleVisible(_ v:Bool,slot:Slot)->Bool {visCalls.append(v);return owner}
 func selectSubtitle(path:String,slot:Slot) async->SubSel {
  selectCalls.append(path);if selDelay>0 {try? await Task.sleep(nanoseconds:selDelay)}
  return selectOverride ?? .selected(path:path,slot:.primary)}
 func audioTrackInventory() async->(tracks:[TrackInfo],activeIndex:Int?)? {if invDelay>0 {try? await Task.sleep(nanoseconds:invDelay)};return inventory}
 func setAudioTrack(_ s:Sel) async throws {
  if case .index(let i)=s {setCalls.append(i)}
  if setDelay>0 {try? await Task.sleep(nanoseconds:setDelay)};if setThrows {throw Boom()}}
 func setSubtitleDelay(_ v:Double,slot:Slot)->String? {subRefuse ? "closed" : nil}
 func setAudioDelay(seconds:Double) throws {if audioThrows {throw Boom()}}
}
@MainActor final class Spine {var lines:[String]=[];func showMPVOSD(_ t:String,duration:Double,force:Bool) {lines.append(t)}}
@MainActor final class Chrome {let spineUI=Spine()}
@MainActor final class Host {
 enum Refusal:Error {case missingSource,unsupportedSourceContext,unsupportedCapability(String)}
 var identity=UUID();var session:Session?;var chrome:Chrome?=Chrome();var gateControlTask:Task<Void,Never>?
 var volumeSessionReady=true;var fails:[String]=[]
 var subtitleVisible=true;var subtitleCycleIndex=0
 func fail(_ e:Error) {fails.append(String(describing:e))}
 var lines:[String] {chrome?.spineUI.lines ?? []}
 func makeWire()->((String,Double)->String?) {return '''+sl['wire']+'''}
'''+sl['osd']+'\n'+sl['vis']+'\n'+sl['sel']+'\n'+sl['cyc']+'\n'+sl['aud']+'\n'+sl['delay']+'\n}\n'
MAIN='''import Foundation
func settle() async {try? await Task.sleep(nanoseconds:160_000_000)}
@MainActor func fresh()->(Host,Session) {let h=Host();let s=Session();h.session=s;return (h,s)}
@MainActor func tracks()->[TrackInfo] {[TrackInfo(index:3,language:"tur",title:nil),TrackInfo(index:1,language:"eng",title:"main"),TrackInfo(index:2,language:"deu",title:nil)]}
@MainActor func run() async {
 // typed delay wiring: accepted (nil) must stay nil, refusal or unready must surface
 do {let (h,s)=fresh();let w=h.makeWire()
  precondition(w("audio-delay",0.5)==nil,"accepted audio delay must return nil")
  precondition(w("sub-delay",0.5)==nil,"accepted sub delay must return nil")
  s.subRefuse=true;precondition(w("sub-delay",0.5) != nil,"sub refusal surfaces")
  s.audioThrows=true;precondition(w("audio-delay",0.5) != nil,"audio refusal surfaces")
  h.volumeSessionReady=false;precondition(w("audio-delay",0.5)=="no open session","unready")
  h.volumeSessionReady=true;precondition(w("audio-delay",.nan)=="delay must be finite","non finite")
  _=h}
 // subtitle visibility Bool
 do {let (h,s)=fresh();h.applySubtitleVisible(false)
  precondition(s.visCalls==[false] && h.subtitleVisible==false && h.lines==["subtitles off"] && h.fails.isEmpty,"vis off")
  h.applySubtitleVisible(true);precondition(h.subtitleVisible && h.lines.last=="subtitles on","vis on")}
 do {let (h,s)=fresh();s.owner=false;h.applySubtitleVisible(false)
  precondition(h.subtitleVisible==true && h.lines.isEmpty && h.fails.count==1,"no owner: no state change, no announce, one refusal")}
 do {let (h,_)=fresh();h.session=nil;h.applySubtitleVisible(false)
  precondition(h.lines.isEmpty && h.fails.count==1,"no session")}
 // SRT select
 do {let (h,s)=fresh();h.selectTextSubtitle(path:"/x/a.ass");await settle()
  precondition(s.selectCalls.isEmpty && h.fails.count==1 && h.lines.isEmpty,"non srt refused before session call")}
 do {let (h,s)=fresh();h.subtitleVisible=false;h.selectTextSubtitle(path:"/x/a.srt",candidateIndex:2);await settle()
  precondition(s.selectCalls==["/x/a.srt"] && s.visCalls==[true] && h.subtitleVisible && h.subtitleCycleIndex==2 && h.lines==["subtitle: a.srt"] && h.fails.isEmpty,"selected")}
 for o in [SubSel.refused("bad"),SubSel.noExactSidecar] {let (h,s)=fresh();h.subtitleCycleIndex=1;s.selectOverride=o
  h.selectTextSubtitle(path:"/x/a.srt",candidateIndex:2);await settle()
  precondition(h.subtitleCycleIndex==1 && h.lines.isEmpty && h.fails.count==1 && s.visCalls.isEmpty,"refused select: no advance, no announce")}
 do {let (h,s)=fresh();h.subtitleCycleIndex=1;s.owner=false;h.selectTextSubtitle(path:"/x/a.srt",candidateIndex:2);await settle()
  precondition(h.subtitleCycleIndex==1 && h.lines.isEmpty && h.fails.count==1,"owner closed after select")}
 do {let (h,s)=fresh();s.selDelay=50_000_000;h.selectTextSubtitle(path:"/x/a.srt",candidateIndex:2);h.identity=UUID();await settle()
  precondition(h.subtitleCycleIndex==0 && h.lines.isEmpty && h.fails.isEmpty && s.visCalls.isEmpty,"stale identity during select")}
 do {let (h,s)=fresh();s.selDelay=50_000_000;h.selectTextSubtitle(path:"/x/a.srt",candidateIndex:2);h.session=Session();await settle()
  precondition(h.subtitleCycleIndex==0 && h.lines.isEmpty && h.fails.isEmpty && s.visCalls.isEmpty,"stale source during select")}
 // SRT cycle
 do {let (h,s)=fresh();s.candidates=[Cand(path:"/x/a.srt",format:"srt"),Cand(path:"/x/b.srt",format:"srt"),Cand(path:"/x/c.ass",format:"ass")]
  h.cycleTextSubtitle(forward:true);await settle();precondition(h.subtitleCycleIndex==1,"cycle a")
  h.cycleTextSubtitle(forward:true);await settle();precondition(h.subtitleCycleIndex==2,"cycle b")
  h.cycleTextSubtitle(forward:true);await settle();precondition(h.subtitleCycleIndex==0 && h.subtitleVisible==false && s.visCalls.last==false,"wrap to off")
  h.cycleTextSubtitle(forward:false);await settle();precondition(h.subtitleCycleIndex==2 && h.subtitleVisible,"down wraps to last")
  precondition(!s.selectCalls.contains("/x/c.ass"),"non srt excluded from cycle")}
 do {let (h,s)=fresh();h.cycleTextSubtitle(forward:true);await settle()
  precondition(h.fails.count==1 && s.selectCalls.isEmpty,"no candidates")}
 do {let (h,s)=fresh();s.candidates=[Cand(path:"/x/a.srt",format:"srt"),Cand(path:"/x/b.srt",format:"srt")];s.selectOverride = .refused("bad")
  h.cycleTextSubtitle(forward:true);await settle();h.cycleTextSubtitle(forward:true);await settle()
  precondition(s.selectCalls==["/x/a.srt","/x/a.srt"] && h.subtitleCycleIndex==0,"refused select does not advance cycle")}
 // audio track
 do {let (h,s)=fresh();s.inventory=nil;s.invDelay=50_000_000;h.cycleAudioTrack(forward:true);h.identity=UUID();await settle()
  precondition(s.setCalls.isEmpty && h.lines.isEmpty && h.fails.isEmpty,"stale nil inventory: no stale refusal")}
 do {let (h,s)=fresh();s.inventory=(tracks(),1);h.cycleAudioTrack(forward:true);await settle()
  precondition(s.setCalls==[2] && h.lines==["audio track: deu (#2)"] && h.fails.isEmpty,"sorted, next after active")}
 do {let (h,s)=fresh();s.inventory=(tracks(),3);h.cycleAudioTrack(forward:true);await settle();precondition(s.setCalls==[1],"wrap forward")}
 do {let (h,s)=fresh();s.inventory=(tracks(),1);h.cycleAudioTrack(forward:false);await settle();precondition(s.setCalls==[3],"wrap down")}
 do {let (h,s)=fresh();s.inventory=(tracks(),nil);h.cycleAudioTrack(forward:true);await settle();precondition(s.setCalls==[2],"unknown active starts at first")}
 do {let (h,s)=fresh();s.inventory=([TrackInfo(index:1,language:nil,title:nil)],1);h.cycleAudioTrack(forward:true);await settle()
  precondition(s.setCalls.isEmpty && h.fails.count==1 && h.lines.isEmpty,"single track refused")}
 do {let (h,s)=fresh();s.inventory=nil;h.cycleAudioTrack(forward:true);await settle()
  precondition(s.setCalls.isEmpty && h.fails.count==1,"no inventory refused")}
 do {let (h,s)=fresh();s.inventory=(tracks(),1);s.setThrows=true;h.cycleAudioTrack(forward:true);await settle()
  precondition(h.lines.isEmpty && h.fails.count==1,"switch failure: no announce")}
 do {let (h,s)=fresh();s.inventory=(tracks(),1);s.invDelay=50_000_000;h.cycleAudioTrack(forward:true);h.identity=UUID();await settle()
  precondition(s.setCalls.isEmpty && h.lines.isEmpty && h.fails.isEmpty,"stale identity during inventory: no switch")}
 do {let (h,s)=fresh();s.inventory=(tracks(),1);s.invDelay=50_000_000;h.cycleAudioTrack(forward:true);h.session=Session();await settle()
  precondition(s.setCalls.isEmpty && h.lines.isEmpty && h.fails.isEmpty,"stale source during inventory: no switch")}
 for throwing in [false,true] {let (h,s)=fresh();s.inventory=(tracks(),1);s.setDelay=60_000_000;s.setThrows=throwing
  h.cycleAudioTrack(forward:true);try? await Task.sleep(nanoseconds:15_000_000);h.identity=UUID();await settle()
  precondition(h.lines.isEmpty && h.fails.isEmpty,"stale source during switch: no announce, no failure")}
 print("PASS accepted delay nil vs refusal, visibility Bool, SRT select/cycle, audio inventory selection, stale source fences")
}
await run()
'''
def mut(sl,key,old,new):
 d=dict(sl);assert d[key].count(old)>=1,(key,old);d[key]=d[key].replace(old,new,1);assert d[key]!=sl[key];return d
sl=slices()
variants=[('fixed',sl),
 ('mutant-r2-nil-flatten (baseline r2 wiring)',mut(sl,'wire','return self.applyChromeDelay(property,seconds) }','return self.applyChromeDelay(property,seconds) ?? "host closed" }') if False else dict(sl,wire='{ [weak self] property,seconds in self?.applyChromeDelay(property,seconds) ?? "host closed" }')),
 ('mutant-delay-unready-ignored',mut(sl,'delay','guard let session,volumeSessionReady else','guard let session else')),
 ('mutant-vis-ignore-bool',mut(sl,'vis','guard let session,session.setSubtitleVisible(visible,slot:.primary) else','guard let session,(session.setSubtitleVisible(visible,slot:.primary) || true) else')),
 ('mutant-srt-select-unfiltered',mut(sl,'sel','guard path.lowercased().hasSuffix(".srt") else','guard path.count>=0 else')),
 ('mutant-select-announces-refusal',mut(sl,'sel','case .refused(let refusal):self.fail(Refusal.unsupportedCapability("text subtitle: \\(refusal)"))','case .refused(_):self.osd("subtitle: x")')),
 ('mutant-select-no-fence',mut(sl,'sel','guard let self,self.identity==token,self.session===session else {return}','guard let self else {return}')),
 ('mutant-select-owner-closed-announces',mut(sl,'sel','if session.setSubtitleVisible(true,slot:.primary) {','if session.setSubtitleVisible(true,slot:.primary) || true {')),
 ('mutant-cycle-srt-unfiltered',mut(sl,'cyc','.filter{$0.format=="srt"}','.filter{_ in true}')),
 ('mutant-cycle-no-wrap',mut(sl,'cyc','let next=(subtitleCycleIndex+(forward ? 1 : slots-1))%slots','let next=min(subtitleCycleIndex+(forward ? 1 : -1),slots-1)')),
 ('mutant-audio-no-inventory-fence (baseline 0003)',mut(sl,'aud','guard let self,self.identity==token,self.session===session else {return}','guard let self else {return}')),
 ('mutant-audio-no-post-switch-fence',mut(sl,'aud','guard self.identity==token,self.session===session else {return}','')),
 ('mutant-audio-announce-before-result',mut(sl,'aud','try await session.setAudioTrack(.index(target.index))','self.osd("audio track: early");try await session.setAudioTrack(.index(target.index))')),
 ('mutant-audio-unsorted',mut(sl,'aud','.sorted{$0.index<$1.index}','')),
 ('mutant-audio-no-wrap',mut(sl,'aud','tracks[(at+(forward ? 1 : tracks.count-1))%tracks.count]','tracks[min(at+(forward ? 1 : -1),tracks.count-1)]')),
 ('mutant-audio-single-track-allowed',mut(sl,'aud',',inventory.tracks.count>1','')),
]
codes=[(l,build(s)) for l,s in variants]
assert len({c for _,c in codes})==len(codes)
if '--wiring-only' in sys.argv or not shutil.which(os.environ.get('SWIFTC','swiftc')):
 print('PASS slices found, %d exact-source variants distinct (1 fixed + %d mutants); Swift NOT_RUN%s'%(len(codes),len(codes)-1,'' if '--wiring-only' in sys.argv else ' (swiftc missing)'))
 raise SystemExit(0 if '--wiring-only' in sys.argv else 2)
with tempfile.TemporaryDirectory(prefix='subtitle-typed-') as td:
 t=Path(td);(t/'main.swift').write_text(MAIN)
 for label,code in codes:
  (t/'Production.swift').write_text(code)
  for opt in ['-Onone','-O']:
   q=subprocess.run([os.environ.get('SWIFTC','swiftc'),opt,str(t/'Production.swift'),str(t/'main.swift'),'-o',str(t/'probe')],capture_output=True,text=True)
   assert q.returncode==0,('all variants must compile before semantic comparison',label,opt,q.stderr)
   q=subprocess.run([str(t/'probe')],capture_output=True,text=True)
   assert (q.returncode==0)==(label=='fixed'),(label,opt,q.stdout,q.stderr)
   print(label,opt,'GREEN' if q.returncode==0 else 'RED')
print('NOT_RUN actual subtitle renderer, audio output, owner pixels')
