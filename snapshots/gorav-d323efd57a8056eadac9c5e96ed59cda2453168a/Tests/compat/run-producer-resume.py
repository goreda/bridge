#!/usr/bin/env python3
"""Run extracted production sink witness/admission with real ring+decoder.
Not native AudioUnit or AppKit execution.
"""
from pathlib import Path
import argparse, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--swiftc',required=True);p.add_argument('--modules',required=True);p.add_argument('--ffmpeg',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2]
s=(root/'Sources/GorAVMacShell/AudioUnitSink.swift').read_text()
def extract(text,marker):
 start=text.index(marker);brace=text.index('{',start);depth=1;end=brace+1
 while depth:
  if text[end]=='{':depth+=1
  elif text[end]=='}':depth-=1
  end+=1
 return text[start:end]
parts=[extract(s,'private enum ProducerState:'),extract(s,'public func markProducerJoined('),extract(s,'public func producerNotExpected('),extract(s,'public func resumeProducerAfterJoin('),extract(s,'public func pushIfUnpaused(')]
ad=(root/'Sources/GorAVAudioClockSwift/AudioPacing.swift').read_text()
ad=extract(ad,'public enum AudioAdmissionRefusal:')+'\n'+extract(ad,'public final class AudioAdmissionState:')
header='''import Foundation
import GorAVCore
import GorAVPlaybackCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVSeekComposition
'''
harness='''
final class WitnessSink: AudioSinkControlling, @unchecked Sendable {
 private let stateLock=NSLock()
 let lifecycle=SessionLifecycle(), fence=GenerationFence()
 private let admission=AudioAdmissionState()
 private var producerState: ProducerState = .idle
 var producerWitnessViolations=0, witnessRejectedPushBytes=0, pushedWhileStopped=0
 var ringStorage:SPSCPCMRing?=SPSCPCMRing(capacityFrames:1<<18)
 var ledger:TimingLedger?=nil
 var ledgerSession:UInt64=0
 var emitted:[UInt8]=[]
 var currentFenceGeneration:UInt64 { fence.active }
 var available:Int { 0 } // immediate simulated device drain after each admitted chunk
 func start()->UInt64 { let g=lifecycle.beginStart()!;_ = lifecycle.commitStart(g);producerState = .pending(g);return g }
 func push(_ pcm:[UInt8]) { _ = pushIfUnpaused(pcm,expectedGeneration:fence.active) }
 func resetRingForSeek() async -> UInt64? { fence.advance();return fence.active }
 func drain(){
  guard let ringStorage else{return}
  let frames=ringStorage.availableFrames
  var bytes=[UInt8](repeating:0,count:Int(frames)*4)
  bytes.withUnsafeMutableBufferPointer { _ = ringStorage.render(into:$0.baseAddress!,frames:UInt32(frames)) }
  emitted += bytes
 }
 func paused(_ value:Bool){ admission.pausedCell?.store(value ? 1:0) }
 func joined(_ g:UInt64)->Bool { producerState == .joined(g) }
'''+ '\n'.join(parts)+ '\n}\n'
# Insert drain only AFTER actual production admission returns, in a wrapper.
# Ring write/producer admission code above remains exact extracted production.
main='''
func check(_ b:Bool,_ m:String){if !b { print("FAIL "+m);exit(1)}}
@main struct Proof {
 static func main() async throws {
 let sink=WitnessSink();let g=sink.start();let f=sink.currentFenceGeneration
 check(sink.pushIfUnpaused([1,2,3,4],expectedGeneration:f) == .admitted,"initial pending admits")
 sink.drain();sink.markProducerJoined(generation:g)
 check(sink.pushIfUnpaused([5,6,7,8],expectedGeneration:f) == .stopped,"old bug joined refuses first resumed PCM")
 check(!sink.resumeProducerAfterJoin(expectedSessionGeneration:g+1,expectedFenceGeneration:f),"stale session refused")
 check(!sink.resumeProducerAfterJoin(expectedSessionGeneration:g,expectedFenceGeneration:f+1),"stale fence refused")
 check(sink.joined(g),"refusal retains joined witness")
 check(sink.resumeProducerAfterJoin(expectedSessionGeneration:g,expectedFenceGeneration:f),"video-refused unchanged fence rearm")
 check(!sink.resumeProducerAfterJoin(expectedSessionGeneration:g,expectedFenceGeneration:f),"duplicate refused")
 sink.markProducerJoined(generation:g);sink.fence.advance();let nf=sink.currentFenceGeneration
 check(sink.resumeProducerAfterJoin(expectedSessionGeneration:g,expectedFenceGeneration:nf),"committed new fence rearm")
 sink.paused(true)
 check(sink.pushIfUnpaused([5,6,7,8],expectedGeneration:nf) == .heldPaused,"paused holds same chunk")
 sink.paused(false)
 check(sink.pushIfUnpaused([5,6,7,8],expectedGeneration:nf) == .admitted,"same chunk resumed")
 sink.drain();check(sink.emitted == [1,2,3,4,5,6,7,8],"byte identity")
 // Real decoder + actual bound pump through extracted production admission.
 let root=CommandLine.arguments[1]
 let session=PlaybackIdentityAuthority.shared.issue()!
 let dec=FFmpegSoftwareAudioDecoder();try dec.pinLocalRoots([root])
 let source=SourceDescriptor(id:root+"/synthetic-h264-aac.mp4",kind:.local,seekable:true)
 try await dec.open(source:source,session:session)
 let descriptor=await dec.seekDescriptor(session:session)!
 let zero=try RationalTime(value:0,timescale:1)
 let seek=await dec.seek(binding:descriptor.binding,videoRelativeTarget:zero,correlation:1)
 guard case .nativeReady(let binding,let correlation,_,_)=seek else{fatalError("real seek")}
 let realSink=WitnessSink();let rg=realSink.start()
 realSink.markProducerJoined(generation:rg)
 check(realSink.resumeProducerAfterJoin(expectedSessionGeneration:rg,expectedFenceGeneration:realSink.currentFenceGeneration),"actual producer rearmed")
 let out=await BoundAudioPump.run(decoder:dec,session:session,binding:binding,correlation:correlation,sink:realSink)
 check(out.terminal == .endOfStream && out.pushed == 530612,"real AAC post-seek PCM/EOS")
 realSink.drain()
 check(realSink.emitted.count == out.pushed,"all actual PCM drained")
 await dec.close(session:session)
 // Independent same-seek decode byte identity, same provider/fixture.
 let baseline=FFmpegSoftwareAudioDecoder();try baseline.pinLocalRoots([root]);try await baseline.open(source:source,session:session)
 let bd=await baseline.seekDescriptor(session:session)!
 let bs=await baseline.seek(binding:bd.binding,videoRelativeTarget:zero,correlation:2)
 guard case .nativeReady(let bb,_,_,_)=bs else{fatalError("baseline seek")}
 var expected:[UInt8]=[]
 while let env=await baseline.nextBoundEvent(binding:bb){if case .pcm(let p)=env.event{expected += p.bytes}}
 await baseline.close(session:session)
 check(realSink.emitted == expected,"exact post-seek PCM identity vs independent same-seek decoder")
 realSink.markProducerJoined(generation:rg);_ = realSink.lifecycle.beginStop();realSink.lifecycle.finishStop(rg)
 // Both orchestration branches must type-refuse unsafe resume tokens.
 for committed in [false,true] {
  let d=FFmpegSoftwareAudioDecoder();try d.pinLocalRoots([root]);try await d.open(source:source,session:session)
  let desc=await d.seekDescriptor(session:session)!
  let ws=WitnessSink();let sg=ws.start();ws.markProducerJoined(generation:sg)
  var launched=false,closed=false
  let result=await SeekOrchestration.coordinateSeekAudio(audioBinding:desc.binding,audioCorrelation:nil,
    videoSeek:{committed},commitAnchor:{nil},decoder:d,session:session,sink:ws,target:zero,targetSeconds:0,correlation:9,
    stopAndJoinProducer:{},resumeProducer:{_,_,_,expectedFence in
      ws.fence.advance() // interpose AFTER operation token captured/reset returned
      let ok=ws.resumeProducerAfterJoin(expectedSessionGeneration:sg,expectedFenceGeneration:expectedFence)
      if ok { launched=true };return ok
    },closeAudio:{await d.close(session:session);closed=true})
  check(result == .resumeRefusedMuted && closed && !launched && ws.joined(sg),"stale operation mute/no launch/keep joined")
 }
 sink.markProducerJoined(generation:g);_ = sink.lifecycle.beginStop()
 check(!sink.resumeProducerAfterJoin(expectedSessionGeneration:g,expectedFenceGeneration:nf),"stop before rearm refused")
 check(sink.joined(g),"stop retains joined witness")
 sink.lifecycle.finishStop(g)
 print("PRODUCER_RESUME_PASS old bug witnessed/rearm/session/fence/duplicate/pause/stop/bytes")
 }
}
'''
with tempfile.TemporaryDirectory() as d:
 d=Path(d);(d/'proof.swift').write_text(header+ad+harness+main)
 cmd=[a.swiftc,'-parse-as-library','-package-name','gorav','-I'+a.modules,'-Xcc','-fmodule-map-file='+str(root/'Sources/GorAVCAtomics/module.modulemap'),'-Xcc','-fmodule-map-file='+str(root/'Sources/CFFmpeg/module.modulemap'),'-Xcc','-I'+a.ffmpeg,str(d/'proof.swift'),'-L'+a.modules,'-lGorAVSeekComposition','-lGorAVFFmpegAdapter','-lGorAVPlaybackCore','-lGorAVNativeProbeKit','-lGorAVCore',a.modules+'/atomics.o']
 for lib in ['avformat','avcodec','swscale','swresample','avutil']:cmd+=['-L'+a.ffmpeg+'/lib'+lib,'-l'+lib]
 cmd+=['-lz','-lm','-lpthread','-o',str(d/'proof')]
 subprocess.run(cmd,check=True)
 import os
 env=dict(os.environ,LD_LIBRARY_PATH=a.modules)
 subprocess.run([str(d/'proof'),str(root/'fixtures/m1')],check=True,env=env)
