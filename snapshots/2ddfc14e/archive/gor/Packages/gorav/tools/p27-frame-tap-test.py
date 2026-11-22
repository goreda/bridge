#!/usr/bin/env python3
"""Runs actual FrameTap state on Linux using a CV object boundary stand-in.
On macOS compiles/runs the unchanged CoreVideo producer too. Never a render test.
"""
from pathlib import Path
import subprocess,tempfile,sys,os,shutil
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/GorAVMacShell/FrameTap.swift').read_text()
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
mac=sys.platform=='darwin'
# SourceToken is already validated by the owning source's exact fence binding.
# State-only test strips the imported token type, not any tap logic.
s=s.replace('import GorAVNativeProbeKit','')
if not mac:
 s=s.split('public enum YUV420PixelBufferProducer',1)[0]
 s=s.replace('#if canImport(AppKit) && canImport(CoreVideo)','').replace('import CoreVideo','')
 s+='\n'
 s='public typealias CVPixelBuffer=NSObject\npublic typealias SourceToken=UInt64\n'+s
else:
 s=s.replace('#if canImport(AppKit) && canImport(CoreVideo)','').removesuffix('#endif\n')
 s='public typealias SourceToken=UInt64\n'+s
main='''import Foundation
func chk(_ value:Bool,_ label:String) {if !value {fatalError(label)};print("PASS",label)}
'''
if mac:
 main+='''import CoreVideo
let production=YUV420PixelBufferProducer.makePlanar(planes:[Array(repeating:17,count:15),Array(repeating:33,count:6),Array(repeating:44,count:6)],width:5,height:3)
chk(production != nil,"real CoreVideo odd5x3 producer")
let pb=production!.buffer
chk(production!.retainedBytes>0,"real stride accounting")
chk(YUV420PixelBufferProducer.makePlanar(planes:[[],[],[]],width:Int.max,height:2)==nil,"overflow dimensions refuse")
'''
else:main+='let pb=NSObject()\n'
main+='''func frame(_ bytes:Int=10,_ gen:UInt64=0,_ session:UInt64=7)->TappedFrame {
 TappedFrame(session:session,seekGeneration:gen,source:1,handle:42,pts:128,ptsSeconds:1,width:5,height:3,pixelFormatName:"yuv420p",retainedBytes:bytes,pixelBuffer:pb)
}
let tap=FrameTap.makeForSession(session:7,capacity:2,maxPerSecond:2,byteBudget:100)
chk(tap.offer(frame(),clockNow:0)==.accepted,"first accepted")
chk(tap.retainedBytes==20,"FIFO plus newest retained accounts")
chk(tap.offer(frame(),clockNow:0.25)==.droppedRateLimit,"2Hz refusal")
chk(tap.offer(frame(),clockNow:Double.nan)==.refusedInvalidClock,"nan clock refuses")
chk(tap.offer(frame(),clockNow:Double.infinity)==.refusedInvalidClock,"infinite clock refuses")
chk(tap.offer(frame(40),clockNow:0.5)==.accepted,"growing frame fits final account")
chk(tap.retainedBytes<=100,"final state budget never exceeded")
_ = tap.next();_ = tap.next()
chk(tap.retainedBytes==40,"newest still accounted after consumption")
tap.fence(newGeneration:1)
chk(tap.latestForReadback()==nil && tap.retainedBytes==0,"seek fence clears retained old frame")
chk(tap.offer(frame(10,0),clockNow:1)==.refusedStaleGeneration,"old async completion refuses")
chk(tap.offer(frame(10,1,8),clockNow:1)==.refusedStaleSession,"foreign session refuses")
chk(tap.offer(frame(Int.max,1),clockNow:1)==.refusedOverflow,"overflow account refuses")
chk(tap.retainedBytes==0,"overflow refusal retains nothing")
chk(tap.offer(frame(10,1),clockNow:1)==.accepted,"postseek accepted with own identity")
tap.close();chk(tap.isClosed && tap.retainedBytes==0,"close releases")
chk(tap.offer(frame(10,1),clockNow:2)==.refusedClosed,"close latch rejects later work")
'''
# Swift lexing needs whitespace between equality and enum-dot.
main=main.replace('==.',' == .')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'Tap.swift').write_text(s);(p/'main.swift').write_text(main)
 subprocess.run([swift,str(p/'Tap.swift'),str(p/'main.swift'),'-o',str(p/'tap')],check=True)
 subprocess.run([str(p/'tap')],check=True)
source=(r/'Sources/GorAVMacShell/ShellFrameSource.swift').read_text();session=(r/'Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
assert 'generation: admittedGeneration, source: origin.source' in source
assert source.count('guard let fence = bridge.currentFence else { return nil }')==2
assert source.count('frame.source == fence.source')==2
assert source.count('frame.seekGeneration == fence.providerRevision.rawValue')==2
assert session.count('FrameTap.makeForSession(session: issued.epoch)')==2
assert 'public func latestTappedFrame()' in session and 'public func consumeTappedFrame()' in session
print('PASS producer admission origin, exact source/current-fence guards and both session compositions')
print('Scope:', 'real CVPixelBuffer producer + tap state on Mac' if mac else 'actual tap state with CV object boundary only; Mac CoreVideo types/producer NOT_RUN')
