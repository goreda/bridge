#!/usr/bin/env python3
"""Execute current host activation against session services, plus actual f8 runtime params.
Does not substitute for the requested native host/render run.
"""
from pathlib import Path
import os,subprocess,tempfile,shutil,hashlib
root=Path(__file__).resolve().parents[2]
host=(root/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
def method(signature):
 a=host.index(signature);return host[a:host.index('\n    }',a)+6].replace('private func','func')
activate=method('    private func setLivePhotonProducer(')
install=method('    private func installLivePhotonForCurrentSession()')
prefix='''import Foundation
@MainActor final class Spine {func clearPhotonHUD(){}}
@MainActor final class Chrome {let spineUI=Spine();var refusal:String?;func setEngineRefusalHUD(_ line:String){refusal=line}}
@MainActor final class GorAVEmbeddedSession {
 var calls:[Bool]=[];var families:[String]=[];var accept=true
 func setPhotonProducerEnabled(_ enabled:Bool,sharp:Bool,grain:Bool)->Bool{calls.append(enabled);families.append(String(sharp)+String(grain));return accept}
}
@MainActor final class Host {
 var identity=UUID();var session:GorAVEmbeddedSession?;var livePhotonTarget=true;var livePhotonSharpTarget=true,livePhotonGrainTarget=true
 var photonHUDTask:Task<Void,Never>?;var photonHUDRevision:UInt64?;let chrome:Chrome?=Chrome();var published=0
 func publishPhotonHUD(sourceIdentity:UUID,session:GorAVEmbeddedSession){published += 1}
'''
post='''
}
@main struct Main {
 @MainActor static func main() async throws {
  let h=Host(),s=GorAVEmbeddedSession();h.session=s
  h.installLivePhotonForCurrentSession();precondition(s.calls==[true]);await Task.yield()
  try await Task.sleep(nanoseconds:20_000_000);precondition(h.published>0)
  let calls=s.calls.count
  precondition(!h.setLivePhotonProducer(true,session:s,sourceIdentity:UUID()) && s.calls.count==calls)
  let foreign=GorAVEmbeddedSession()
  precondition(!h.setLivePhotonProducer(true,session:foreign,sourceIdentity:h.identity) && foreign.calls.isEmpty)
  h.identity=UUID();let publications=h.published
  try await Task.sleep(nanoseconds:300_000_000);precondition(h.published==publications)
  h.livePhotonTarget=false;h.installLivePhotonForCurrentSession()
  precondition(s.calls.last==false && h.photonHUDTask==nil)
  s.accept=false;h.installLivePhotonForCurrentSession();precondition(h.chrome?.refusal != nil)
  s.accept=true;h.livePhotonTarget=true;h.installLivePhotonForCurrentSession()
  precondition(s.calls.last==true);h.photonHUDTask?.cancel()
  for sharp in [false,true] {for grain in [false,true] {
   h.livePhotonSharpTarget=sharp;h.livePhotonGrainTarget=grain;h.installLivePhotonForCurrentSession()
   precondition(s.families.last==String(sharp)+String(grain));h.photonHUDTask?.cancel()
   var owned=PhotonPresenterProducer();owned.setTargets(sharp:sharp,grain:grain)
   for epoch:UInt64 in [1,1,2] {
    let family=try owned.snapshot(epoch:epoch,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:0,now:1)
    precondition(family.sharpEnabled==sharp && family.grainEnabled==grain)
   }
  }}
  var p=PhotonPresenterProducer()
  let snap=try p.snapshot(epoch:1,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:0,now:1)
  precondition(snap.sharp.count==19 && snap.grain.count==29 && !snap.hasSceneFeed)
  precondition(snap.sharp["PHOTON_SHARP_AMOUNT"]==0.312 && snap.sharp["PHOTON_SHARP_FACTOR_RENDERED"]==1)
  precondition(snap.grain["BASE_STRENGTH"]==6 && snap.grain["GRAIN_SIZE"]==0.8)
  let redraw=try p.snapshot(epoch:1,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:0,now:100)
  precondition(snap.sharp==redraw.sharp && snap.grain==redraw.grain && snap.token==redraw.token)
  print("PASS current host default-on/off, activation refusal, source/session fence, stale HUD cancellation; actual f8 19+29 params/defaults and paused redraw")
 }
}
'''
core=root/'Packages/gorav/Sources/GorAVPlaybackCore'
files=['PhotonSharpRuntime.swift','PhotonGrainRuntime.swift','PhotonGrainClock.swift','PhotonSceneFeed.swift','PhotonParameterPublisher.swift','PhotonPresenterProducer.swift']
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-install/usr/bin/swiftc'
variants={'green':activate,
 'red-source-fence':activate.replace('identity==sourceIdentity,session===current,','session===current,'),
 'red-session-fence':activate.replace('identity==sourceIdentity,session===current,','identity==sourceIdentity,'),
 'red-master-off':activate.replace('setPhotonProducerEnabled(enabled,','setPhotonProducerEnabled(true,'),
 'red-family-mapping':activate.replace('sharp:livePhotonSharpTarget,grain:livePhotonGrainTarget','sharp:true,grain:true'),
 'red-hud-source-fence':activate.replace('self.identity==sourceIdentity,self.session===current','self.session===current')}
with tempfile.TemporaryDirectory() as td:
 t=Path(td);p=t/'main.swift'
 for mode in ['-Onone','-O']:
  for name,a in variants.items():
   p.write_text(prefix+install+'\n'+a+post);out=t/name
   c=subprocess.run([swift,mode,'-swift-version','5','-parse-as-library',str(p),*[str(core/f) for f in files],'-o',str(out)],capture_output=True,text=True)
   assert c.returncode==0,(name,c.stderr)
   v=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
   if name=='green':assert v.returncode==0,v.stderr;print(mode+' '+v.stdout.strip())
   else:assert v.returncode!=0,'mutant survived '+name;print(mode+' PASS semantic runtime RED: '+name)
# Exact ordinary bring-up hooks, not the test qualification method.
consume=method('    private func consume(')
opened=consume.split('case .opened:',1)[1].split('case .firstFrame:',1)[0]
seek=consume.split('case .seekCommitted:',1)[1].split('case .durationKnown',1)[0]
assert 'installLivePhotonForCurrentSession()' in opened and 'installLivePhotonForCurrentSession()' in seek
assert 'activatePhotonProducerCandidate' not in opened+seek
assert 'livePhotonTarget=photonOwner?.photonEnabled ?? true' in host
assert 'photonOwner?.goravPhotonFamilyTargets' in host
native=(root/'Tests/gorTests/PhotonProducerHostNativeTests.swift').read_text()
assert 'activatePhotonProducerCandidate()' not in native
assert 'XCTAssertEqual(completed.sharp,expected.sharp' in native
renderer=(root/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalRenderer.swift').read_text()
graph=(root/'Packages/gorav/Sources/GorAVMetalPresenter/core/PhotonWorkingGraph.swift').read_text()
assert 'photonProducer.snapshot(' in renderer and 'completePhoton(' in renderer
assert 'parameters:block(.sharp,snapshot.sharp)' in graph and 'parameters:block(.grain,snapshot.grain)' in graph
assert 'length:MemoryLayout<PhotonCompositeUniforms>.stride' in renderer
assert 'snapshot.sharpEnabled ? effects.encodeSharp' in graph and 'snapshot.grainEnabled ? effects.encodeGrain' in graph
print('PASS current ordinary open/seek hooks and actual producer->parameter graph->completion wiring; native host/Metal acceptance pending')
