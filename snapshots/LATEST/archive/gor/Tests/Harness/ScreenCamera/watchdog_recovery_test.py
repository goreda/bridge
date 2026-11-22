#!/usr/bin/env python3
"""Execute shipped self-sampling and retirement decision with an owned fake sampler."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import tempfile,subprocess,shutil
r=Path(__file__).resolve().parents[3]
s=_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift');a=s.index('    private func sampleHungVision(epoch: UInt64)');b=s.index('    private func endVisionWatchdog',a)
source_method=s[a:b]
method=source_method.replace('    private func','    func',1).replace('exit(75)','self.testExit(75)')
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);sampler=p/'sample';sampler.write_text('#!/bin/sh\nprintf "LIVE_HELPER_STACK" > "$4"\n');sampler.chmod(0o755)
 method=method.replace('"/usr/bin/sample"','"'+str(sampler)+'"')
 main='''import Foundation
#if canImport(Glibc)
import Glibc
#endif
enum StagedRunPaths {static func tmp(_ p:String)->String {CommandLine.arguments[1]}}
enum BoundedDiskWriter {static func append(_ data:Data,to url:URL,cap:UInt64)->Bool {try! data.write(to:url);return true}}
struct Config {var generation:UInt64=7;var headPose=true,blink=false,ambientOnly=false}
final class Engine {
 let visionEpochLock=NSLock();var activeVisionEpoch:UInt64?=3
 var config=Config();var exits=[Int32]()
 func snapshot()->Config {config}
 func mediaLog(_ s:String) {}
 func testExit(_ n:Int32) {exits.append(n)}
'''+method+'''
}
for mode in 0..<5 {
 let e=Engine()
 if mode==1 {e.activeVisionEpoch=nil}
 if mode==2 {e.config.headPose=false}
 if mode==3 {e.config.ambientOnly=true}
 e.sampleHungVision(epoch:3)
 if mode==4 {e.config.generation=8}
 Thread.sleep(forTimeInterval:0.35)
 precondition(e.exits==(mode==0 ? [75]:[]),"retired healthy/new/stopped epoch")
 let receipt=try! String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
 precondition(receipt.contains("LIVE_HELPER_STACK") && receipt.contains("result=sampled"))
 print("PASS actual sample+retire mode=\\(mode)")
}
'''
 (p/'main.swift').write_text(main)
 subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(p/'receipt')],check=True)
# Production binds sample to self, not a name/PID lookup; hard timeout signals sampler only.
assert 'sampler.arguments = [String(getpid()), "2"' in s
assert 'if sampler.isRunning { kill(sampler.processIdentifier, SIGKILL) }' in s
assert 'guard self.epoch == myEpoch else {return}; self.childExitedLocked()' in s
print('PASS active exact-self sampling; recovery only stuck current consumer epoch; stale termination callback rejected')

# Execute the actual parent exit reducer. No camera/session behavior is mocked as hardware proof.
parent=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
a=parent.index('        case .exited:',parent.index('private func handleHelperIncoming'))
b=parent.index('\n        }\n    }',a)
body=parent[a:b].split('DispatchQueue.main.async { [weak self] in',1)[1].rsplit('}',1)[0]
body=body.replace('guard let self, self.activeConsumers > 0 else { return }','guard self.activeConsumers > 0 else { return }')
program='''import Foundation
struct Diag {static func mediaRecord(_ s:String) {}}
enum State {case idle,starting,running,failed}
final class Parent {
 var activeConsumers=1;var lifecycleGeneration:UInt64=7;var relaunchGeneration:UInt64=0
 var cameraState=State.running;var launches=0
 func beginSession(){launches+=1;cameraState = .starting}
 func exited(){'''+body+'''}
}
let p=Parent();p.exited();precondition(p.launches==1 && p.cameraState == .starting)
p.cameraState = .running;p.exited();precondition(p.launches==1 && p.cameraState == .failed)
p.exited();precondition(p.launches==1)
p.lifecycleGeneration=8;p.cameraState = .running;p.exited();precondition(p.launches==2)
p.activeConsumers=0;p.exited();precondition(p.launches==2)
print("PASS actual parent reducer: one relaunch, second failure terminal, fresh generation eligible, idle stays idle")
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(program)
 compiler=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([compiler,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
 mutant=program.replace('guard self.relaunchGeneration != self.lifecycleGeneration else {','guard true else {')
 (p/'main.swift').write_text(mutant);subprocess.run([compiler,str(p/'main.swift'),'-o',str(p/'bad')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 assert subprocess.run([str(p/'bad')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode != 0
 print('PASS unlimited-relaunch negative control rejected')
